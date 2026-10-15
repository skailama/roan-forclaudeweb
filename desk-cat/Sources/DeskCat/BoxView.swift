import AppKit

/// The yellow box with the cat's name on it. The cat itself is drawn by `CatView` in a window
/// just above this one; while it's home, its body is clipped at the rim so it sits "inside".
final class BoxView: NSView {
    static let size = NSSize(width: 220, height: 130)
    /// Where the box body's bottom-left corner sits inside the view.
    static let inset = CGPoint(x: 50, y: 0)

    var name = "" { didSet { if name != oldValue { needsDisplay = true } } }
    /// Pop-in/out scale from the simulation's box spring (0 hidden, 1 shown, overshoots a little).
    var show: CGFloat = 1 { didSet { if abs(show - oldValue) > 0.0005 { needsDisplay = true } } }

    var onDragStart: (() -> Void)?
    var onDrag: ((CGVector) -> Void)?
    var onDragEnd: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    private var dragStart = CGPoint.zero

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        onDragStart?()
    }

    override func mouseDragged(with event: NSEvent) {
        let m = NSEvent.mouseLocation
        onDrag?(CGVector(dx: m.x - dragStart.x, dy: m.y - dragStart.y))
    }

    override func mouseUp(with event: NSEvent) { onDragEnd?() }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        let s = show
        guard s > 0.02 else { return }
        let w = CatSim.boxW
        ctx.saveGState()
        // Pop from the bottom centre, a little taller than wide while it springs.
        ctx.translateBy(x: Self.inset.x + w / 2, y: Self.inset.y)
        ctx.scaleBy(x: clamp(s, 0, 1.3), y: clamp(s * (1 + (1 - s) * 0.35), 0, 1.4))
        ctx.setAlpha(clamp01(s * 3))
        ctx.translateBy(x: -w / 2, y: 0)
        ctx.setFillColor(Palette.box)
        ctx.addLines(between: [
            CGPoint(x: 0, y: 90), CGPoint(x: 120, y: 90), CGPoint(x: 136, y: 62), CGPoint(x: 120, y: 62),
            CGPoint(x: 120, y: 0), CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 62), CGPoint(x: -16, y: 62),
        ])
        ctx.closePath()
        ctx.fillPath()
        drawName()
        ctx.restoreGState()
    }

    /// The name, shrunk to fit the front of the box.
    private func drawName() {
        let text = name as NSString
        guard text.length > 0 else { return }
        var fontSize: CGFloat = 22
        var attrs: [NSAttributedString.Key: Any] = [:]
        repeat {
            attrs = [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold), .foregroundColor: Palette.inkText]
            if text.size(withAttributes: attrs).width <= 100 { break }
            fontSize -= 1
        } while fontSize > 9
        text.draw(at: CGPoint(x: 10, y: 6), withAttributes: attrs)
    }
}
