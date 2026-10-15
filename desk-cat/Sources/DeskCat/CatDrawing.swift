import AppKit

/// Colours shared by the cat and the box.
enum Palette {
    static let ink = CGColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 1)
    static let inkFar = CGColor(srgbRed: 0.169, green: 0.169, blue: 0.180, alpha: 1)
    static let pawRim = CGColor(srgbRed: 0.29, green: 0.29, blue: 0.31, alpha: 1)
    static let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    static let box = CGColor(srgbRed: 1, green: 0.976, blue: 0.416, alpha: 1)
    static let mouth = CGColor(srgbRed: 1, green: 0.561, blue: 0.639, alpha: 1)
    static let heart = CGColor(srgbRed: 1, green: 0.42, blue: 0.545, alpha: 1)
    static let inkText = NSColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 1)
}

/// Draws the cat in world (screen) coordinates. The caller translates the context so the
/// window's origin sits at its own (0, 0). Port of the drawing code in `playground.html`.
extension CatSim {
    func draw(in ctx: CGContext) {
        let sk = skeleton(), p = sk.p
        ctx.saveGState()
        if let clipY = boxClip {
            ctx.clip(to: CGRect(x: -100_000, y: clipY, width: 200_000, height: 100_000))
        }
        drawTail(ctx)
        drawLeg(ctx, sk.legs[.fb], Palette.inkFar)
        drawLeg(ctx, sk.legs[.ff], Palette.inkFar)
        let hip = toWorld(p.hx, p.hy), chest = toWorld(p.cx, p.cy)
        let sy = squash.x, sx = 1 + (1 - sy) * 0.7, vol = sqrt(sx * sy)
        let back = lerp(-1.5, 2.5, clamp01(crouch.x)), belly = lerp(-2, -4, clamp01(lie.x))
        bean(ctx, hip, p.hr * vol, chest, p.cr * vol, back: back, belly: belly)
        line(ctx, chest, toWorld(p.kx, p.ky), 17, Palette.ink)   // neck
        drawLeg(ctx, sk.legs[.nb], Palette.ink)
        let pawUp = max(paw.x, groom.x) > 0.3
        if !pawUp && (boxClip == nil || rim.x < 0.5) { drawLeg(ctx, sk.legs[.nf], Palette.ink) }
        drawHead(ctx, sk)
        // A paw in front of the face gets a faint rim so it still reads against the black head.
        if pawUp { drawLeg(ctx, sk.legs[.nf], Palette.ink, outline: Palette.pawRim) }
        ctx.restoreGState()

        // Paws hooked over the rim sit in front of the box, so they're drawn unclipped.
        if boxClip != nil && rim.x >= 0.5 {
            for id in [LegID.ff, .nf] {
                guard let leg = sk.legs[id] else { continue }
                let f = toWorld(leg.foot.x, leg.foot.y)
                ctx.setFillColor(Palette.ink)
                ctx.fillEllipse(in: CGRect(x: f.x - 6.5, y: f.y - 5, width: 13, height: 10))
                ctx.setStrokeColor(Palette.white)
                ctx.setLineWidth(1.3)
                ctx.setLineCap(.round)
                for dx: CGFloat in [-2.2, 2.2] {
                    ctx.move(to: CGPoint(x: f.x + dx, y: f.y - 4.5))
                    ctx.addLine(to: CGPoint(x: f.x + dx, y: f.y - 1.8))
                }
                ctx.strokePath()
            }
        }
        if sleeping { drawZzz(ctx, sk) }
        for h in hearts { drawHeart(ctx, h) }
    }

    // MARK: Parts

    private func line(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint, _ w: CGFloat, _ color: CGColor) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(w)
        ctx.setLineCap(.round)
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
    }

    private func fillCircle(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ color: CGColor) {
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    /// Smooth bean between the hip and chest circles.
    private func bean(_ ctx: CGContext, _ a: CGPoint, _ ra: CGFloat, _ b: CGPoint, _ rb: CGFloat, back: CGFloat, belly: CGFloat) {
        let dx = b.x - a.x, dy = b.y - a.y, d = max(hypot(dx, dy), 1)
        let nx = -dy / d, ny = dx / d
        let mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2, mr = (ra + rb) / 2
        ctx.setFillColor(Palette.ink)
        ctx.move(to: CGPoint(x: a.x + nx * ra, y: a.y + ny * ra))
        ctx.addQuadCurve(to: CGPoint(x: b.x + nx * rb, y: b.y + ny * rb),
                         control: CGPoint(x: mx + nx * (mr + back), y: my + ny * (mr + back)))
        ctx.addLine(to: CGPoint(x: b.x - nx * rb, y: b.y - ny * rb))
        ctx.addQuadCurve(to: CGPoint(x: a.x - nx * ra, y: a.y - ny * ra),
                         control: CGPoint(x: mx - nx * (mr + belly), y: my - ny * (mr + belly)))
        ctx.closePath()
        ctx.fillPath()
        fillCircle(ctx, a, ra, Palette.ink)
        fillCircle(ctx, b, rb, Palette.ink)
    }

    private func drawLeg(_ ctx: CGContext, _ leg: Leg?, _ color: CGColor, outline: CGColor? = nil) {
        guard let leg else { return }
        let a = toWorld(leg.anchor.x, leg.anchor.y), k = toWorld(leg.knee.x, leg.knee.y), f = toWorld(leg.foot.x, leg.foot.y)
        let dir: CGFloat = facing.x >= 0 ? 1 : -1
        if let outline {
            line(ctx, k, f, 10, outline)
            ctx.setFillColor(outline)
            ctx.fillEllipse(in: CGRect(x: f.x + 1.5 * dir - 6.6, y: f.y + 1 - 5.6, width: 13.2, height: 11.2))
        }
        line(ctx, a, k, 9.5, color)
        line(ctx, k, f, 7.5, color)
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: f.x + 1.5 * dir - 5.2, y: f.y + 1 - 4.2, width: 10.4, height: 8.4))
    }

    private func drawTail(_ ctx: CGContext) {
        let n = tail.count, puff = tailPuff.x
        guard n > 1 else { return }
        for i in 0..<(n - 1) {
            line(ctx, tail[i], tail[i + 1], lerp(7.5, 4.6, CGFloat(i) / CGFloat(n - 1)) * puff, Palette.ink)
        }
    }

    /// Rounded head: a superellipse, slightly wider and flatter at the cheeks.
    private func headPath(_ ctx: CGContext, _ a: CGFloat, _ b: CGFloat) {
        for i in 0...40 {
            let th = CGFloat(i) / 40 * .pi * 2, c = cos(th), s = sin(th)
            let x = a * sgn(c) * pow(abs(c), 2 / 2.5) * (s < 0 ? 1.04 : 1)
            let y = b * sgn(s) * pow(abs(s), 2 / 2.5) * (s < 0 ? 0.92 : 1)
            if i == 0 { ctx.move(to: CGPoint(x: x, y: y)) } else { ctx.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.closePath()
    }

    private func ear(_ ctx: CGContext, _ b1: CGPoint, _ b2: CGPoint, _ tip: CGPoint, _ rot: CGFloat) {
        let mx = (b1.x + b2.x) / 2, my = (b1.y + b2.y) / 2
        ctx.saveGState()
        ctx.translateBy(x: mx, y: my)
        ctx.rotate(by: rot)
        ctx.translateBy(x: -mx, y: -my)
        ctx.setFillColor(Palette.ink)
        ctx.move(to: b1)
        ctx.addQuadCurve(to: tip, control: CGPoint(x: lerp(b1.x, tip.x, 0.5) - 2.5, y: lerp(b1.y, tip.y, 0.5) + 1))
        ctx.addQuadCurve(to: b2, control: CGPoint(x: lerp(b2.x, tip.x, 0.5) + 1.5, y: lerp(b2.y, tip.y, 0.5) + 2))
        ctx.closePath()
        ctx.fillPath()
        ctx.restoreGState()
    }

    private var blinkAmount: CGFloat {
        blinkT < 0 ? 1 : 1 - sin(.pi * clamp01(blinkT / 0.16))
    }

    private func eye(_ ctx: CGContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ gzx: CGFloat, _ gzy: CGFloat) {
        let openness = clamp01(open.x * blinkAmount)
        ctx.setStrokeColor(Palette.white)
        ctx.setLineCap(.round)
        ctx.setLineWidth(2.2)
        if clamp01(happy.x) > 0.5 {          // ^ ^
            ctx.move(to: CGPoint(x: x - r * 0.8, y: y - r * 0.15))
            ctx.addQuadCurve(to: CGPoint(x: x + r * 0.8, y: y - r * 0.15), control: CGPoint(x: x, y: y + r * 0.8))
            ctx.strokePath()
            return
        }
        if openness < 0.1 {                  // closed, relaxed
            ctx.move(to: CGPoint(x: x - r * 0.8, y: y))
            ctx.addQuadCurve(to: CGPoint(x: x + r * 0.8, y: y), control: CGPoint(x: x, y: y - r * 0.55))
            ctx.strokePath()
            return
        }
        let eyeRect = CGRect(x: x - r, y: y - r * (1 - openness) * 0.35 - r * openness, width: r * 2, height: r * 2 * openness)
        ctx.saveGState()
        ctx.setFillColor(Palette.white)
        ctx.fillEllipse(in: eyeRect)
        ctx.addEllipse(in: eyeRect)
        ctx.clip()
        let px = x + gzx * r * 0.42, py = y + gzy * r * 0.34
        let w = r * (0.34 + 0.62 * clamp01(dil.x)), h = r * 1.5
        ctx.setFillColor(Palette.ink)
        ctx.move(to: CGPoint(x: px, y: py + h / 2))
        ctx.addQuadCurve(to: CGPoint(x: px, y: py - h / 2), control: CGPoint(x: px + w * 1.05, y: py))
        ctx.addQuadCurve(to: CGPoint(x: px, y: py + h / 2), control: CGPoint(x: px - w * 1.05, y: py))
        ctx.fillPath()
        fillCircle(ctx, CGPoint(x: px + w * 0.28, y: py + r * 0.3), r * 0.17, Palette.white)
        ctx.restoreGState()
    }

    private func drawHead(_ ctx: CGContext, _ sk: Skeleton) {
        let p = sk.p, c = toWorld(p.kx, p.ky)
        let hf = headFacing.x, sy = 1 + (squash.x - 1) * 0.35
        let a = tilt.x * 0.9 + pitch.x
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: lean.x + swing.x * 0.5)
        ctx.scaleBy(x: turnScale(hf, 0.6), y: sy)
        ctx.rotate(by: a)
        // ears rotate outward/back when flattened
        ear(ctx, CGPoint(x: -22, y: 8), CGPoint(x: -7, y: 18), CGPoint(x: -18, y: 34), earL.x * 0.9)
        ear(ctx, CGPoint(x: 6, y: 18), CGPoint(x: 21, y: 9), CGPoint(x: 19, y: 34), -earR.x * 0.9)
        ctx.setFillColor(Palette.ink)
        headPath(ctx, 25, 21)
        ctx.fillPath()
        // gaze in head space (undo the head's own flip and tilt)
        let flip: CGFloat = hf >= 0 ? 1 : -1
        let gzx = gx.x * flip, gzy = gy.x
        let rx = gzx * cos(a) + gzy * sin(a), ry = -gzx * sin(a) + gzy * cos(a)
        eye(ctx, -6.5, 2, 8, rx, ry)
        eye(ctx, 12.5, 2, 8, rx, ry)
        if yawn.x > 0.05 {
            let yv = clamp01(yawn.x)
            ctx.setFillColor(Palette.mouth)
            ctx.fillEllipse(in: CGRect(x: 4 - 4 * yv, y: -10 - 6.5 * yv, width: 8 * yv, height: 13 * yv))
        }
        ctx.restoreGState()
    }

    private func drawZzz(_ ctx: CGContext, _ sk: Skeleton) {
        let h = toWorld(sk.p.kx, sk.p.ky)
        let dir: CGFloat = facing.x >= 0 ? 1 : -1
        for i in 0..<3 {
            let u = (zzz * 0.45 + CGFloat(i) / 3).truncatingRemainder(dividingBy: 1)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10 + u * 8, weight: .bold),
                .foregroundColor: Palette.inkText,
            ]
            ctx.saveGState()
            ctx.setAlpha(sin(.pi * u) * 0.85)
            ("z" as NSString).draw(at: CGPoint(x: h.x + 18 + u * 22 * dir, y: h.y + 22 + u * 34), withAttributes: attrs)
            ctx.restoreGState()
        }
    }

    private func drawHeart(_ ctx: CGContext, _ h: Heart) {
        let a = 7 + h.age * 4, d = a / CGFloat(2).squareRoot(), r = a / 2
        ctx.saveGState()
        ctx.setAlpha(max(0, 1 - h.age / 1.4))
        ctx.setFillColor(Palette.heart)
        ctx.addLines(between: [CGPoint(x: h.x, y: h.y + d), CGPoint(x: h.x + d, y: h.y),
                               CGPoint(x: h.x, y: h.y - d), CGPoint(x: h.x - d, y: h.y)])
        ctx.closePath()
        ctx.fillPath()
        fillCircle(ctx, CGPoint(x: h.x - d / 2, y: h.y + d / 2), r, Palette.heart)
        fillCircle(ctx, CGPoint(x: h.x + d / 2, y: h.y + d / 2), r, Palette.heart)
        ctx.restoreGState()
    }
}
