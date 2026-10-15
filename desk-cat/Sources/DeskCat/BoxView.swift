import AppKit

/// The yellow box with the cat's name on it. The cat itself is drawn by `CatView` in a window
/// just above this one; while it's home, its body is clipped at the rim so it sits "inside".
final class BoxView: NSView {
    static let size = NSSize(width: 220, height: 140)
    /// Where the box body's bottom-left corner sits inside the view (room below for its shadow).
    static let inset = CGPoint(x: 50, y: 10)

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
        let w = CatSim.boxW, a = clamp01(s * 3)
        ctx.saveGState()
        ctx.translateBy(x: Self.inset.x + w / 2, y: Self.inset.y)
        drawGroundShadow(ctx, center: CGPoint(x: 0, y: 1), rx: 74 * clamp(s, 0, 1.2), ry: 5.5, alpha: 0.2 * a)
        // Pop from the bottom centre, a little taller than wide while it springs.
        ctx.scaleBy(x: clamp(s, 0, 1.3), y: clamp(s * (1 + (1 - s) * 0.35), 0, 1.4))
        ctx.setAlpha(a)
        ctx.translateBy(x: -w / 2, y: 0)
        drawCardboard(ctx)
        ctx.setAlpha(a * 0.88)   // name printed onto the card
        drawName()
        ctx.restoreGState()
    }

    // Cardboard: warm yellow, a top-to-bottom shade, darker flaps, creases, tape and a few scuffs.
    private enum Card {
        static let top = CGColor(srgbRed: 0.973, green: 0.910, blue: 0.416, alpha: 1)
        static let bottom = CGColor(srgbRed: 0.914, green: 0.812, blue: 0.298, alpha: 1)
        static let flap = CGColor(srgbRed: 0.886, green: 0.776, blue: 0.271, alpha: 1)
        static let flapDark = CGColor(srgbRed: 0.831, green: 0.718, blue: 0.235, alpha: 1)
        static let shade = CGColor(srgbRed: 0.353, green: 0.235, blue: 0, alpha: 1)
        static let scratch = CGColor(srgbRed: 0.478, green: 0.361, blue: 0.071, alpha: 0.32)
        static let crease = CGColor(srgbRed: 0.353, green: 0.235, blue: 0, alpha: 0.28)
        static let tape = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.3)
        static let tapeEdge = CGColor(srgbRed: 0.549, green: 0.431, blue: 0.118, alpha: 0.18)
        static let scuff = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.16)
        static let worn = CGColor(srgbRed: 0.275, green: 0.176, blue: 0, alpha: 0.12)
    }

    private func drawCardboard(_ ctx: CGContext) {
        // flaps, shaded darker towards their tips
        for dir: CGFloat in [-1, 1] {
            let x0: CGFloat = dir < 0 ? 0 : 120, tip = x0 + dir * 16
            gradient(ctx, [CGPoint(x: x0, y: 90), CGPoint(x: tip, y: 62), CGPoint(x: x0, y: 62)],
                     [Card.flap, Card.flapDark], from: CGPoint(x: x0, y: 0), to: CGPoint(x: tip, y: 0))
        }
        // front face
        let face = [CGPoint(x: 0, y: 0), CGPoint(x: 120, y: 0), CGPoint(x: 120, y: 90), CGPoint(x: 0, y: 90)]
        gradient(ctx, face, [Card.top, Card.bottom], from: CGPoint(x: 0, y: 90), to: .zero)
        // shadow under the rim lip, and a darker bottom edge
        gradient(ctx, [CGPoint(x: 0, y: 82), CGPoint(x: 120, y: 82), CGPoint(x: 120, y: 90), CGPoint(x: 0, y: 90)],
                 [Card.shade.copy(alpha: 0.22) ?? Card.shade, Card.shade.copy(alpha: 0) ?? Card.shade],
                 from: CGPoint(x: 0, y: 90), to: CGPoint(x: 0, y: 82))
        gradient(ctx, [CGPoint(x: 0, y: 0), CGPoint(x: 120, y: 0), CGPoint(x: 120, y: 7), CGPoint(x: 0, y: 7)],
                 [Card.shade.copy(alpha: 0.16) ?? Card.shade, Card.shade.copy(alpha: 0) ?? Card.shade],
                 from: .zero, to: CGPoint(x: 0, y: 7))
        // fold creases where the flaps meet the face
        stroke(ctx, [CGPoint(x: 0.6, y: 62), CGPoint(x: 0.6, y: 90)], Card.crease, 1)
        stroke(ctx, [CGPoint(x: 119.4, y: 62), CGPoint(x: 119.4, y: 90)], Card.crease, 1)
        // a strip of packing tape over the top, torn at the end
        fill(ctx, [CGPoint(x: 53, y: 90), CGPoint(x: 67, y: 90), CGPoint(x: 67, y: 76), CGPoint(x: 65, y: 74.5),
                   CGPoint(x: 63, y: 76.5), CGPoint(x: 60.5, y: 74), CGPoint(x: 58, y: 76), CGPoint(x: 55.5, y: 74.2),
                   CGPoint(x: 53, y: 75.5)], Card.tape)
        stroke(ctx, [CGPoint(x: 53, y: 90), CGPoint(x: 53, y: 75.5)], Card.tapeEdge, 0.8)
        // scratches and scuffs
        let scratches: [([CGPoint], CGFloat)] = [
            ([CGPoint(x: 14, y: 70), CGPoint(x: 21, y: 66.5), CGPoint(x: 27, y: 65.5)], 0.9),
            ([CGPoint(x: 18, y: 73), CGPoint(x: 24, y: 70.5)], 0.7),
            ([CGPoint(x: 84, y: 44), CGPoint(x: 96, y: 48), CGPoint(x: 104, y: 47)], 0.9),
            ([CGPoint(x: 98, y: 22), CGPoint(x: 108, y: 17)], 0.8),
            ([CGPoint(x: 101, y: 25), CGPoint(x: 106, y: 22.5)], 0.6),
            ([CGPoint(x: 8, y: 46), CGPoint(x: 11, y: 38)], 0.7),
        ]
        for (pts, width) in scratches { stroke(ctx, pts, Card.scratch, width) }
        ctx.saveGState()
        ctx.translateBy(x: 96, y: 66)
        ctx.rotate(by: -0.3)
        ctx.setFillColor(Card.scuff)
        ctx.fillEllipse(in: CGRect(x: -9, y: -4, width: 18, height: 8))
        ctx.restoreGState()
        fill(ctx, [CGPoint(x: 0, y: 0), CGPoint(x: 9, y: 0), CGPoint(x: 0, y: 7)], Card.worn)   // worn corner
    }

    private func fill(_ ctx: CGContext, _ pts: [CGPoint], _ color: CGColor) {
        ctx.setFillColor(color)
        ctx.addLines(between: pts)
        ctx.closePath()
        ctx.fillPath()
    }

    private func stroke(_ ctx: CGContext, _ pts: [CGPoint], _ color: CGColor, _ width: CGFloat) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addLines(between: pts)
        ctx.strokePath()
    }

    private func gradient(_ ctx: CGContext, _ pts: [CGPoint], _ colors: [CGColor], from: CGPoint, to: CGPoint) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1]) else {
            fill(ctx, pts, colors[0])
            return
        }
        ctx.saveGState()
        ctx.addLines(between: pts)
        ctx.closePath()
        ctx.clip()
        ctx.drawLinearGradient(g, start: from, end: to, options: [])
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
