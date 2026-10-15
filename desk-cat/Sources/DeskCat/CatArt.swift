import AppKit

enum Palette {
    static let ink = CGColor(srgbRed: 0.12, green: 0.12, blue: 0.12, alpha: 1)
    static let inkText = NSColor(srgbRed: 0.12, green: 0.12, blue: 0.12, alpha: 1)
    static let box = CGColor(srgbRed: 1.0, green: 0.98, blue: 0.42, alpha: 1)
    static let eyeWhite = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    static let heart = CGColor(srgbRed: 1.0, green: 0.40, blue: 0.55, alpha: 1)
}

struct Heart: Equatable {
    static let lifetime: CGFloat = 1.2
    var pos: CGPoint
    var age: CGFloat
}

/// Vector drawing of the cat, shared by the box view (peeking) and the roaming cat view.
/// Everything is plain Core Graphics: no image assets, no SpriteKit, nothing to load.
enum CatArt {
    /// Draws the head (ears, face, eyes). At scale 1 the face is a 74×62 oval centred on `center`.
    /// `look` is a unit-ish vector in screen space pointing at the mouse pointer.
    static func head(_ ctx: CGContext, at center: CGPoint, scale: CGFloat, tilt: CGFloat,
                     look: CGVector, dilation: CGFloat, eyesClosed: Bool) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: tilt)
        ctx.scaleBy(x: scale, y: scale)

        ctx.setFillColor(Palette.ink)
        ctx.setStrokeColor(Palette.ink)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(5)
        let ears = [
            [CGPoint(x: -35, y: 8), CGPoint(x: -10, y: 27), CGPoint(x: -30, y: 52)],
            [CGPoint(x: 8, y: 28), CGPoint(x: 33, y: 10), CGPoint(x: 38, y: 46)],
        ]
        for ear in ears {
            ctx.addLines(between: ear)
            ctx.closePath()
            ctx.drawPath(using: .fillStroke)
        }
        ctx.fillEllipse(in: CGRect(x: -37, y: -31, width: 74, height: 62))

        // Undo the head tilt so the pupils point at the real pointer position.
        let gaze = CGVector(dx: look.dx * cos(tilt) + look.dy * sin(tilt),
                            dy: -look.dx * sin(tilt) + look.dy * cos(tilt))
        eye(ctx, at: CGPoint(x: -13, y: 4), radius: 10, look: gaze, dilation: dilation, closed: eyesClosed)
        eye(ctx, at: CGPoint(x: 15, y: -6), radius: 10, look: gaze, dilation: dilation, closed: eyesClosed)
        ctx.restoreGState()
    }

    private static func eye(_ ctx: CGContext, at c: CGPoint, radius r: CGFloat, look: CGVector,
                            dilation: CGFloat, closed: Bool) {
        if closed {
            ctx.setStrokeColor(Palette.eyeWhite)
            ctx.setLineWidth(r * 0.28)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: c.x - r * 0.75, y: c.y))
            ctx.addQuadCurve(to: CGPoint(x: c.x + r * 0.75, y: c.y), control: CGPoint(x: c.x, y: c.y - r * 0.6))
            ctx.strokePath()
            return
        }
        ctx.setFillColor(Palette.eyeWhite)
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))

        // Almond pupil, slanted like the logo, widening when the cat is excited.
        let reach = r * 0.38
        let w = r * (0.5 + 0.55 * dilation)
        let h = r * 1.05
        ctx.saveGState()
        ctx.translateBy(x: c.x + look.dx * reach, y: c.y + look.dy * reach)
        ctx.rotate(by: -0.35)
        ctx.move(to: CGPoint(x: 0, y: h / 2))
        ctx.addQuadCurve(to: CGPoint(x: 0, y: -h / 2), control: CGPoint(x: w, y: 0))
        ctx.addQuadCurve(to: CGPoint(x: 0, y: h / 2), control: CGPoint(x: -w, y: 0))
        ctx.setFillColor(Palette.ink)
        ctx.fillPath()
        ctx.restoreGState()
    }

    static func limb(_ ctx: CGContext, _ from: CGPoint, _ to: CGPoint, width: CGFloat) {
        ctx.setStrokeColor(Palette.ink)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()
    }

    static func tail(_ ctx: CGContext, from: CGPoint, control: CGPoint, to: CGPoint, width: CGFloat) {
        ctx.setStrokeColor(Palette.ink)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.move(to: from)
        ctx.addQuadCurve(to: to, control: control)
        ctx.strokePath()
    }

    /// A rotated square plus two circles on its upper edges.
    static func heart(_ ctx: CGContext, _ heart: Heart) {
        let c = heart.pos
        let a = 9 + heart.age * 4
        let d = a / CGFloat(2).squareRoot()
        let r = a / 2
        ctx.saveGState()
        ctx.setAlpha(max(0, 1 - heart.age / Heart.lifetime))
        ctx.setFillColor(Palette.heart)
        ctx.addLines(between: [CGPoint(x: c.x, y: c.y + d), CGPoint(x: c.x + d, y: c.y),
                               CGPoint(x: c.x, y: c.y - d), CGPoint(x: c.x - d, y: c.y)])
        ctx.closePath()
        ctx.fillPath()
        for m in [CGPoint(x: c.x - d / 2, y: c.y + d / 2), CGPoint(x: c.x + d / 2, y: c.y + d / 2)] {
            ctx.fillEllipse(in: CGRect(x: m.x - r, y: m.y - r, width: r * 2, height: r * 2))
        }
        ctx.restoreGState()
    }
}
