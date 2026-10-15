import AppKit

enum CatPose: Equatable {
    case walk, sit, crouch, leap, held
}

/// The cat once it's out of the box. Drawn facing right and mirrored when it faces left.
/// Press and drag to pick it up by the scruff; drop it on the box to put it back.
final class CatView: NSView {
    static let size = NSSize(width: 120, height: 120)
    /// Where the paws touch the ground inside the view; the controller positions the window by this point.
    static let feet = CGPoint(x: 60, y: 6)

    struct State: Equatable {
        var pose: CatPose = .sit
        var facingRight = true
        var phase: CGFloat = 0          // walk cycle / crouch wiggle
        var look = CGVector.zero
        var dilation: CGFloat = 0
        var eyesClosed = false
        var tailSway: CGFloat = 0
        var hearts: [Heart] = []
    }

    var state = State() {
        didSet { if state != oldValue { needsDisplay = true } }
    }
    var onPress: (() -> Void)?
    var onDrag: (() -> Void)?
    var onRelease: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    /// Centre of the head in view coordinates, used for gaze and for spawning hearts.
    static func headPoint(for pose: CatPose, facingRight: Bool) -> CGPoint {
        let p: CGPoint
        switch pose {
        case .sit: p = CGPoint(x: 66, y: 70)
        case .held: p = CGPoint(x: 60, y: 80)
        case .crouch: p = CGPoint(x: 90, y: 45)
        case .walk, .leap: p = CGPoint(x: 90, y: 58)
        }
        return facingRight ? p : CGPoint(x: size.width - p.x, y: p.y)
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onPress?() }
    override func mouseDragged(with event: NSEvent) { onDrag?() }
    override func mouseUp(with event: NSEvent) { onRelease?() }
    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        let s = state
        ctx.saveGState()
        if !s.facingRight {
            ctx.translateBy(x: bounds.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        // Inside the mirrored space left/right swap, so mirror the gaze too.
        let look = s.facingRight ? s.look : CGVector(dx: -s.look.dx, dy: s.look.dy)
        switch s.pose {
        case .sit: drawSitting(ctx, look: look)
        case .held: drawHeld(ctx, look: look)
        case .walk, .crouch, .leap: drawStanding(ctx, look: look)
        }
        ctx.restoreGState()
        for heart in s.hearts {
            CatArt.heart(ctx, heart)
        }
    }

    private func drawHead(_ ctx: CGContext, look: CGVector, scale: CGFloat, tilt: CGFloat) {
        let s = state
        CatArt.head(ctx, at: Self.headPoint(for: s.pose, facingRight: true), scale: scale, tilt: tilt,
                    look: look, dilation: s.dilation, eyesClosed: s.eyesClosed)
    }

    /// Walking, crouching (about to pounce) and mid-leap all share this side-on body.
    private func drawStanding(_ ctx: CGContext, look: CGVector) {
        let s = state
        let ground = Self.feet.y
        let crouching = s.pose == .crouch
        let low: CGFloat = crouching ? 9 : 0
        let wiggle: CGFloat = crouching ? sin(s.phase) * 2 : 0
        let hipY = 36 - low

        CatArt.tail(ctx, from: CGPoint(x: 36 + wiggle, y: hipY + 8),
                    control: CGPoint(x: 16, y: hipY + 12 + s.tailSway),
                    to: CGPoint(x: 20 + s.tailSway, y: hipY + 36), width: 6.5)

        // Far legs first so the near ones overlap them. Diagonal pairs move together.
        let legs: [(x: CGFloat, offset: CGFloat)] = [(42, 0), (74, .pi), (52, .pi), (84, 0)]
        for leg in legs {
            let front = leg.x > 60
            var footX = leg.x
            var footY = ground
            switch s.pose {
            case .walk:
                footX += sin(s.phase + leg.offset) * 6
                footY += max(0, cos(s.phase + leg.offset)) * 4
            case .leap:
                footX += front ? 9 : -9
                footY += 4
            default:
                break
            }
            let hipX = leg.x + (front ? 0 : wiggle)
            CatArt.limb(ctx, CGPoint(x: hipX, y: hipY), CGPoint(x: footX, y: footY + 4), width: 8)
        }

        ctx.setFillColor(Palette.ink)
        ctx.fillEllipse(in: CGRect(x: 32 + wiggle, y: hipY - 12, width: 60, height: 30))
        let bob: CGFloat = s.pose == .walk ? sin(s.phase * 0.5) * 0.04 : 0
        drawHead(ctx, look: look, scale: 0.5, tilt: -0.12 + bob)
    }

    private func drawSitting(_ ctx: CGContext, look: CGVector) {
        let s = state
        let ground = Self.feet.y
        ctx.setFillColor(Palette.ink)
        ctx.fillEllipse(in: CGRect(x: 32, y: ground, width: 42, height: 30))       // haunch
        ctx.fillEllipse(in: CGRect(x: 44, y: ground + 8, width: 36, height: 50))   // chest
        CatArt.limb(ctx, CGPoint(x: 66, y: 34), CGPoint(x: 66, y: ground + 4), width: 8)
        CatArt.limb(ctx, CGPoint(x: 75, y: 34), CGPoint(x: 75, y: ground + 4), width: 8)
        // Tail curled around the front paws, tip flicking.
        CatArt.tail(ctx, from: CGPoint(x: 36, y: ground + 8),
                    control: CGPoint(x: 50, y: ground - 3),
                    to: CGPoint(x: 88 + s.tailSway * 0.5, y: ground + 4 + max(0, s.tailSway)), width: 6.5)
        drawHead(ctx, look: look, scale: 0.55, tilt: -0.2)
    }

    /// Dangling by the scruff.
    private func drawHeld(_ ctx: CGContext, look: CGVector) {
        let s = state
        CatArt.tail(ctx, from: CGPoint(x: 60, y: 30), control: CGPoint(x: 66 + s.tailSway, y: 14),
                    to: CGPoint(x: 58, y: 6), width: 6)
        CatArt.limb(ctx, CGPoint(x: 52, y: 48), CGPoint(x: 48, y: 30), width: 7)
        CatArt.limb(ctx, CGPoint(x: 68, y: 48), CGPoint(x: 72, y: 30), width: 7)
        CatArt.limb(ctx, CGPoint(x: 54, y: 30), CGPoint(x: 50, y: 12), width: 7)
        CatArt.limb(ctx, CGPoint(x: 66, y: 30), CGPoint(x: 70, y: 12), width: 7)
        ctx.setFillColor(Palette.ink)
        ctx.fillEllipse(in: CGRect(x: 45, y: 24, width: 30, height: 46))
        drawHead(ctx, look: look, scale: 0.55, tilt: 0)
    }
}
