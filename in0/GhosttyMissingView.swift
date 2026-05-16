import SwiftUI

/// Fallback window shown when `GhosttyBridge.initialize()` couldn't bring
/// libghostty up — typically because the project was built without first
/// running `./scripts/build-vendor.sh`, or libghostty.a was deleted between
/// builds. We show a plain SwiftUI panel instead of crashing the moment a
/// terminal view tries to spawn a surface.
struct GhosttyMissingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text(L10n.App.ghosttyNotFoundTitle)
                .font(.title2.bold())
            Text(L10n.App.ghosttyNotFoundDetail)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(width: 420, height: 280)
    }
}
