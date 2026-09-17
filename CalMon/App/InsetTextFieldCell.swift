import AppKit

/// `NSTextFieldCell` with explicit horizontal text insets, so a native bezelled
/// field can reserve room for an inline clear button (or centre a short value in
/// the non-clear area) without moving its border or the field's frame.
final class InsetTextFieldCell: NSTextFieldCell {
    var textInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)

    private func inset(_ rect: NSRect) -> NSRect {
        NSRect(
            x: rect.origin.x + textInsets.left,
            y: rect.origin.y,
            width: max(0, rect.width - textInsets.left - textInsets.right),
            height: rect.height
        )
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        inset(super.drawingRect(forBounds: rect))
    }

    // `edit`/`select` receive a frame already derived from `drawingRect`, so they
    // must not inset again (doing so collapses the field editor to zero width).
}
