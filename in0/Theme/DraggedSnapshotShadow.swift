import AppKit

/// Builds a softly-shadowed "card" image suitable as the dragging ghost
/// for tabs and workspace rows. Follows the Josh Comeau layered-shadow
/// recipe: four stacked NSShadow passes at ~5% alpha each with exponentially
/// doubling offset and blur. Compared to a single concentrated shadow the
/// accumulation reads as a natural fall-off — the card looks lifted off
/// the underlying chrome instead of pasted on with a dark bar under it.
///
/// Returned image extends `padding` points beyond `contentSize` on every
/// side. The matching frame is offset by `-padding` so callers can pass
/// both directly to `NSDraggingItem.setDraggingFrame(_:contents:)` and the
/// cursor stays anchored to the original row's hit point.
enum DraggedSnapshotShadow {
    /// Halo padding around the snapshot. Big enough that the largest
    /// shadow layer (8 pt offset + 8 pt blur) doesn't clip at the image
    /// edge — NSShadow's visible reach is roughly 1.5σ of its blur.
    static let padding: CGFloat = 20

    /// Four-layer smooth-shadow stack. Each layer alone is barely
    /// perceptible; the accumulation produces the lifted feel.
    /// NSShadow's `shadowOffset` uses unflipped coordinates, so a
    /// visually downward offset is `height` *negative*.
    private static let layers: [(dy: CGFloat, blur: CGFloat, alpha: CGFloat)] = [
        (-1, 1, 0.05),
        (-2, 2, 0.05),
        (-4, 4, 0.05),
        (-8, 8, 0.05),
    ]

    static func compose(
        content snapshot: NSImage,
        contentSize: NSSize,
        cornerRadius: CGFloat
    ) -> (image: NSImage, frame: NSRect) {
        let outerSize = NSSize(
            width: contentSize.width + padding * 2,
            height: contentSize.height + padding * 2
        )
        let cardRect = NSRect(
            x: padding, y: padding,
            width: contentSize.width, height: contentSize.height
        )
        let path = NSBezierPath(
            roundedRect: cardRect,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )

        let composed = NSImage(size: outerSize)
        composed.lockFocus()
        defer { composed.unlockFocus() }

        // Stack four shadow passes. After the loop the card area is fully
        // opaque black; we punch it out below so the snapshot blends with
        // the shadow halo through its own anti-aliased edges.
        for layer in layers {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowOffset = NSSize(width: 0, height: layer.dy)
            shadow.shadowBlurRadius = layer.blur
            shadow.shadowColor = NSColor.black.withAlphaComponent(layer.alpha)
            shadow.set()
            NSColor.black.set()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        // Clear the card region so subsequent snapshot draw composes onto
        // transparency instead of over the black we used as a shadow target.
        if let cgctx = NSGraphicsContext.current?.cgContext {
            cgctx.saveGState()
            cgctx.setBlendMode(.clear)
            path.fill()
            cgctx.restoreGState()
        }

        // Clip the snapshot to the rounded card so any square pixels in
        // the source bitmap get masked into the same shape we shadowed.
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        snapshot.draw(in: cardRect)
        NSGraphicsContext.restoreGraphicsState()

        let frame = NSRect(
            x: -padding, y: -padding,
            width: outerSize.width, height: outerSize.height
        )
        return (composed, frame)
    }
}
