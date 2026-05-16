// in0-status.js — opencode plugin: reports session state to in0 via Unix socket.
//
// opencode (≥ 1.4) loads plugins via `await import(fileURL)`. We export a
// named async function that returns a hooks object. There is no event bus
// on `input` — every event we care about arrives via the named hooks
// declared in the returned object. Schema reference:
// packages/plugin/src/index.ts in sst/opencode.

import net from "node:net";

const SOCK = process.env.IN0_HOOK_SOCK;
const TID  = process.env.IN0_TERMINAL_ID;

// Per-plugin turn state. opencode keeps the plugin process alive across
// turns, so we can keep this in memory rather than going through a file.
let turn = { hadError: false, tool: null, startedAt: null };

function emit(msg) {
    if (!SOCK || !TID) return;
    const payload = JSON.stringify({
        terminalId: TID,
        agent: "opencode",
        at: Date.now() / 1000,
        ...msg,
    }) + "\n";
    try {
        const client = net.createConnection(SOCK);
        client.on("error", () => {});
        client.setTimeout(500, () => { try { client.destroy(); } catch {} });
        client.on("connect", () => client.end(payload));
    } catch (_) { /* swallow */ }
}

function shortPath(p) {
    if (!p) return "";
    const parts = p.split("/").filter(Boolean);
    return parts.length > 3 ? parts.slice(-3).join("/") : parts.join("/");
}

const SESSION_ID_RE = /^[A-Za-z0-9_-]+$/;
function resumeCommandFor(sessionID) {
    if (!sessionID || !SESSION_ID_RE.test(sessionID)) return null;
    return `opencode --session ${sessionID}`;
}

function describeTool(tool, input) {
    if (!input || typeof input !== "object") return tool || "";
    const t = tool || "";
    if (t === "edit" || t === "write" || t === "read") {
        const p = shortPath(input.filePath || input.file_path || "");
        return p ? `${t.charAt(0).toUpperCase() + t.slice(1)} ${p}` : t;
    }
    if (t === "bash") {
        const cmd = (input.command || "").split("\n")[0].slice(0, 60);
        return cmd ? `Bash: ${cmd}` : "Bash";
    }
    return t;
}

function emitFinishedFromTurn() {
    emit({ event: "finished", exitCode: turn.hadError ? 1 : 0 });
    turn = { hadError: false, tool: null, startedAt: null };
}

export const In0StatusPlugin = async (_input) => ({
    event: async ({ event }) => {
        switch (event?.type) {
            case "session.created":
                // Don't reset turn state — session.created also fires before the first turn.
                return;
            case "session.idle":   // deprecated event but still emitted by some versions
            case "session.error":
                return emitFinishedFromTurn();
            case "permission.asked":
                return emit({ event: "needsInput" });
            case "permission.replied":
                return emit({ event: "running" });
            case "session.status": {
                const status = event.properties?.status?.type;
                if (status === "busy") {
                    if (!turn.startedAt) turn.startedAt = Date.now() / 1000;
                    emit({ event: "running" });
                } else if (status === "idle") {
                    emitFinishedFromTurn();
                }
                return;
            }
        }
    },

    // chat.message ≈ UserPromptSubmit: the user sent a message. We grab
    // the session id here so even prompts that issue no tool calls still
    // record a resume command.
    "chat.message": async (input, _output) => {
        if (!turn.startedAt) turn.startedAt = Date.now() / 1000;
        const resumeCommand = resumeCommandFor(input?.sessionID);
        const payload = { event: "running" };
        if (resumeCommand) payload.resumeCommand = resumeCommand;
        emit(payload);
    },

    "tool.execute.before": async (input, output) => {
        turn.tool = input?.tool;
        if (!turn.startedAt) turn.startedAt = Date.now() / 1000;
        const detail = describeTool(input?.tool, output?.args);
        const resumeCommand = resumeCommandFor(input?.sessionID);
        const payload = { event: "running" };
        if (detail) payload.toolDetail = detail;
        if (resumeCommand) payload.resumeCommand = resumeCommand;
        emit(payload);
    },

    "tool.execute.after": async (_input, output) => {
        const hadErr = !!(output?.metadata?.error)
            || (output?.metadata?.status === "error");
        if (hadErr) turn.hadError = true;
        // No emit here — the icon only flips on session.idle / session.status:idle.
    },
});
