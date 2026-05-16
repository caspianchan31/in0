import SwiftUI

/// Renders a quick-action icon according to its `QuickActionIcon`
/// discriminator. SF Symbols and asset-catalog images get the standard
/// `Image` treatment; `.letter` paints a single-character chip — the
/// fallback for custom actions whose name hints at what they run.
struct QuickActionIconView: View {
    let source: QuickActionIcon
    var size: CGFloat = 12
    var color: Color = .primary

    var body: some View {
        switch source {
        case .sfSymbol(let name):
            Image(systemName: name)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(color)
        case .asset(let name):
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: size + 4, height: size + 4)
                .foregroundStyle(color)
        case .letter(let c):
            Text(String(c))
                .font(.system(size: size - 1, weight: .black, design: .rounded))
                .foregroundStyle(color)
                .frame(width: size + 4, height: size + 4)
                .background(
                    RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous)
                        .stroke(color, lineWidth: 1)
                )
        }
    }
}
