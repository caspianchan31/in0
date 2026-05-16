import CryptoKit
import Darwin
import Foundation

/// Listens on a Unix domain socket for one-line JSON `HookMessage`s pushed
/// by agent hook scripts. Each accepted connection is read on a background
/// queue; decoded messages are dispatched on the main actor.
@MainActor
final class HookSocketListener {
    private let dispatcher: HookDispatcher?
    private(set) var socketPath: String

    /// Optional fan-out for tests: invoked on the main actor for every
    /// successfully decoded message. Production wires a `HookDispatcher`
    /// instead.
    var onMessage: ((HookMessage) -> Void)?

    private var listenFd: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let acceptQueue = DispatchQueue(label: "in0.hooks.accept")
    private let readQueue = DispatchQueue(label: "in0.hooks.read", attributes: .concurrent)

    init(dispatcher: HookDispatcher) {
        self.dispatcher = dispatcher
        self.socketPath = Self.defaultSocketPath()
    }

    /// Test-only init that lets the caller pin the socket path and skip
    /// dispatcher wiring. Throws if the parent directory can't be created
    /// (stable per-bundle signature for portable assertions).
    init(path: String) throws {
        self.dispatcher = nil
        self.socketPath = path
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
    }

    deinit {
        if listenFd >= 0 { close(listenFd) }
    }

    /// Stop accepting connections and unlink the socket file. Idempotent.
    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        if listenFd >= 0 {
            close(listenFd)
            listenFd = -1
        }
        unlink(socketPath)
    }

    /// Computed path under `~/Library/Caches/in0/`. Includes a hash of the
    /// running bundle path so multiple installs (Debug vs Release) don't
    /// fight over the same socket file.
    static func defaultSocketPath() -> String {
        let cacheDir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Caches/in0")
        try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        return socketPath(forBundlePath: Bundle.main.bundlePath)
    }

    /// Deterministic socket path for a given bundle. Pure — exposed so
    /// tests can lock down the hashing without spawning a real listener.
    static func socketPath(forBundlePath bundlePath: String) -> String {
        let cacheDir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Caches/in0")
        let hash = SHA256.hash(data: Data(bundlePath.utf8))
            .prefix(4)
            .map { String(format: "%02x", $0) }
            .joined()
        return (cacheDir as NSString).appendingPathComponent("hooks-\(hash).sock")
    }

    func start() {
        guard listenFd < 0 else { return }
        // Best-effort cleanup: a previous instance may have left the file.
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd); return
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dst in
                pathBytes.withUnsafeBufferPointer { src in
                    _ = memcpy(dst, src.baseAddress, pathBytes.count)
                }
            }
        }
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.bind(fd, sockaddrPtr, addrLen)
            }
        }
        guard bindRes == 0 else {
            close(fd); return
        }
        guard listen(fd, 16) == 0 else {
            close(fd); return
        }

        listenFd = fd
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let clientFd = Darwin.accept(fd, nil, nil)
            if clientFd >= 0 {
                self.handleClient(clientFd: clientFd)
            }
        }
        src.resume()
        acceptSource = src
    }

    private nonisolated func handleClient(clientFd: Int32) {
        readQueue.async { [weak self] in
            guard let self else { close(clientFd); return }
            var buffer = Data()
            var chunk = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = chunk.withUnsafeMutableBufferPointer { buf -> ssize_t in
                    read(clientFd, buf.baseAddress, buf.count)
                }
                if n <= 0 { break }
                buffer.append(contentsOf: chunk.prefix(Int(n)))
                while let nlIdx = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer.subdata(in: 0..<nlIdx)
                    buffer.removeSubrange(0...nlIdx)
                    if let line = String(data: lineData, encoding: .utf8),
                       let msg = HookMessage.decode(line: line) {
                        self.dispatchOnMain(msg)
                    }
                }
            }
            close(clientFd)
        }
    }

    private nonisolated func dispatchOnMain(_ msg: HookMessage) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.dispatcher?.handle(msg)
            self.onMessage?(msg)
        }
    }
}
