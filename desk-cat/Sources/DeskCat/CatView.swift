import AppKit

/// Draws the cat. The window follows the cat around; the simulation works in screen
/// coordinates, so drawing just shifts by the window's origin.
final class CatView: NSView {
    static let size = NSSize(width: 300, height: 270)
    /// Where the cat's root (the ground under its body) sits inside the view.
    static let anchor = CGPoint(x: 150, y: 95)

    weak var sim: CatSim?
    var onPress: (() -> Void)?
    var onDrag: (() -> Void)?
    var onRelease: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onPress?() }
    override func mouseDragged(with event: NSEvent) { onDrag?() }
    override func mouseUp(with event: NSEvent) { onRelease?() }
    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let sim, let origin = window?.frame.origin else { return }
        ctx.clear(bounds)
        ctx.saveGState()
        ctx.translateBy(x: -origin.x, y: -origin.y)
        sim.draw(in: ctx)
        ctx.restoreGState()
    }
}
