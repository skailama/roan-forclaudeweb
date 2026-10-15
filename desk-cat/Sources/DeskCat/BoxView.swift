import AppKit

/// The yellow box with the cat's name on it, and the cat peeking out when it's home.
/// Drag it anywhere; click the cat to let it out; click the box to play peekaboo.
final class BoxView: NSView {
    static let size = NSSize(width: 180, height: 260)
    static let headCenter = CGPoint(x: 84, y: 170)
    static let boxTop: CGFloat = 117

    struct State: Equatable {
        var name = ""
        var catHome = true
        var peek: CGFloat = 1          // 1 = peeking out, 0 = ducked into the box
        var tilt: CGFloat = -0.3
        var look = CGVector.zero
        var dilation: CGFloat = 0
        var eyesClosed = false
        var asleep = false
        var hearts: [Heart] = []
    }

    /// Only redraws when something visible actually changed, so an idle cat costs nothing.
    var state = State() {
        didSet { if state != oldValue { needsDisplay = true } }
    }
    var onClick: ((CGPoint) -> Void)?
    var onDragEnded: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    private var dragStartMouse = CGPoint.zero
    private var dragStartOrigin = CGPoint.zero
    private var dragging = false

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin ?? .zero
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let m = NSEvent.mouseLocation
        let dx = m.x - dragStartMouse.x, dy = m.y - dragStartMouse.y
        if !dragging && hypot(dx, dy) < 3 { return }
        dragging = true
        window?.setFrameOrigin(CGPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        if dragging {
            onDragEnded?()
        } else {
            onClick?(convert(event.locationInWindow, from: nil))
        }
        dragging = false
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        let s = state
        let drop = (1 - s.peek) * 85
        if s.catHome {
            drawPeekingCat(ctx, drop: drop)
        }
        drawBox(ctx)
        if s.catHome && s.peek > 0.8 {
            drawPaws(ctx, drop: drop)
        }
        drawName()
        if s.catHome && s.asleep {
            drawZzz()
        }
        for heart in s.hearts {
            CatArt.heart(ctx, heart)
        }
    }

    /// Shoulders and head, drawn before the box so the box hides the rest of the body.
    private func drawPeekingCat(_ ctx: CGContext, drop: CGFloat) {
        let s = state
        ctx.saveGState()
        ctx.translateBy(x: 0, y: -drop)
        ctx.setFillColor(Palette.ink)
        ctx.fillEllipse(in: CGRect(x: 40, y: 98, width: 88, height: 66))
        CatArt.head(ctx, at: Self.headCenter, scale: 1, tilt: s.tilt, look: s.look,
                    dilation: s.dilation, eyesClosed: s.eyesClosed)
        ctx.restoreGState()
    }

    private func drawBox(_ ctx: CGContext) {
        ctx.setFillColor(Palette.box)
        ctx.addLines(between: [
            CGPoint(x: 21, y: Self.boxTop), CGPoint(x: 159, y: Self.boxTop),
            CGPoint(x: 177, y: 78), CGPoint(x: 159, y: 78),
            CGPoint(x: 159, y: 0), CGPoint(x: 21, y: 0),
            CGPoint(x: 21, y: 78), CGPoint(x: 3, y: 78),
        ])
        ctx.closePath()
        ctx.fillPath()
    }

    /// Two paws hooked over the rim, with little toe notches.
    private func drawPaws(_ ctx: CGContext, drop: CGFloat) {
        let y = Self.boxTop - drop
        for x: CGFloat in [52, 98] {
            ctx.setFillColor(Palette.ink)
            ctx.fillEllipse(in: CGRect(x: x - 12, y: y - 9, width: 24, height: 17))
            ctx.setStrokeColor(Palette.eyeWhite)
            ctx.setLineWidth(1.6)
            ctx.setLineCap(.round)
            for dx: CGFloat in [-4, 4] {
                ctx.move(to: CGPoint(x: x + dx, y: y - 8))
                ctx.addLine(to: CGPoint(x: x + dx, y: y - 4))
            }
            ctx.strokePath()
        }
    }

    /// The name, shrunk to fit the front of the box.
    private func drawName() {
        let name = state.name as NSString
        guard name.length > 0 else { return }
        var fontSize: CGFloat = 26
        var attrs: [NSAttributedString.Key: Any] = [:]
        repeat {
            attrs = [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                     .foregroundColor: Palette.inkText]
            if name.size(withAttributes: attrs).width <= 122 { break }
            fontSize -= 1
        } while fontSize > 9
        name.draw(at: CGPoint(x: 30, y: 12), withAttributes: attrs)
    }

    private func drawZzz() {
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .bold),
                                                    .foregroundColor: Palette.inkText]
        let big: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16, weight: .bold),
                                                  .foregroundColor: Palette.inkText]
        ("z" as NSString).draw(at: CGPoint(x: 146, y: 204), withAttributes: small)
        ("Z" as NSString).draw(at: CGPoint(x: 156, y: 216), withAttributes: big)
    }
}
