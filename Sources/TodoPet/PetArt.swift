import SwiftUI

/// Everything needed to draw one frame of the pet.
struct PetPose {
    var mood: Mood
    var t: Double
    var facing: CGFloat = 1
    var walking = false
    var walkPhase: Double = 0
    var lookX: CGFloat = 0
    var hovered = false
    var held = false
    var prevMood: Mood = .normal
    /// 0 → colors of `prevMood`, 1 → colors of `mood`.
    var blend: Double = 1
}

struct RGBA {
    var r, g, b, a: Double
    init(_ hex: UInt32, _ a: Double = 1) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
        self.a = a
    }
    init(r: Double, g: Double, b: Double, a: Double) { self.r = r; self.g = g; self.b = b; self.a = a }
    func mix(_ o: RGBA, _ k: Double) -> RGBA {
        RGBA(r: r + (o.r - r) * k, g: g + (o.g - g) * k, b: b + (o.b - b) * k, a: a + (o.a - a) * k)
    }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

struct PetPalette {
    var top: RGBA, bottom: RGBA, line: RGBA, cheek: RGBA

    static func of(_ m: Mood) -> PetPalette {
        switch m {
        case .happy, .celebrating:
            PetPalette(top: RGBA(0xFFE9CC), bottom: RGBA(0xFFBA8A), line: RGBA(0x8A4B2A), cheek: RGBA(0xFF6F96, 0.55))
        case .normal, .focus:
            PetPalette(top: RGBA(0xFFF0DE), bottom: RGBA(0xF4C69C), line: RGBA(0x7A4A30), cheek: RGBA(0xFF8FA3, 0.40))
        case .annoyed:
            PetPalette(top: RGBA(0xEFE6DC), bottom: RGBA(0xC4B09E), line: RGBA(0x5E4A3E), cheek: RGBA(0xC98F8F, 0.20))
        case .angry:
            PetPalette(top: RGBA(0xFFB49C), bottom: RGBA(0xEA5A45), line: RGBA(0x6E1D12), cheek: RGBA(0xB02A1E, 0.0))
        case .sleeping:
            PetPalette(top: RGBA(0xEAE7F8), bottom: RGBA(0xB9B2DE), line: RGBA(0x4D4775), cheek: RGBA(0xFF9FB8, 0.28))
        }
    }

    func mix(_ o: PetPalette, _ k: Double) -> PetPalette {
        PetPalette(top: top.mix(o.top, k), bottom: bottom.mix(o.bottom, k), line: line.mix(o.line, k), cheek: cheek.mix(o.cheek, k))
    }
}

/// Draws "Mochi", a round cat-eared mochi, in a 120×120 design space.
enum PetArt {
    static func draw(_ ctx: inout GraphicsContext, size: CGSize, pose p: PetPose) {
        let s = min(size.width, size.height) / 120
        ctx.translateBy(x: (size.width - 120 * s) / 2, y: (size.height - 120 * s) / 2)
        ctx.scaleBy(x: s, y: s)

        let t = p.t
        let k = max(0, min(1, p.blend))
        let pal = PetPalette.of(p.prevMood).mix(PetPalette.of(p.mood), k * k * (3 - 2 * k))
        let mood = p.held ? Mood.normal : p.mood

        // Body dynamics.
        var jump: CGFloat = 0, squash: CGFloat = 0, shakeX: CGFloat = 0, breathe: CGFloat = 0
        switch mood {
        case .celebrating:
            let ph = (t * 2.2).truncatingRemainder(dividingBy: 1)
            let h = CGFloat(sin(ph * .pi))
            jump = h * 20
            squash = (ph < 0.1 || ph > 0.9) ? 0.12 : -0.06 * h
        case .happy:
            if p.walking {
                jump = abs(CGFloat(sin(p.walkPhase))) * 5
            } else {
                let b = abs(CGFloat(sin(t * 3.2)))
                jump = b * 6
                squash = (1 - b) * 0.08 - 0.03
            }
        case .normal, .focus:
            if p.walking { jump = abs(CGFloat(sin(p.walkPhase))) * 3 } else { breathe = CGFloat(sin(t * 2)) * 0.02 }
        case .annoyed:
            if p.walking { jump = abs(CGFloat(sin(p.walkPhase))) * 1.5 } else { breathe = CGFloat(sin(t * 1.2)) * 0.015 }
        case .angry:
            shakeX = CGFloat(sin(t * 47)) * (sin(t * 1.7) > 0.2 ? 1.6 : 0.3)
            if p.walking {
                jump = abs(CGFloat(sin(p.walkPhase))) * 2
                squash = 0.05 * abs(CGFloat(cos(p.walkPhase)))
            } else {
                let st = abs(CGFloat(sin(t * 5)))
                jump = st * 2.5
                squash = (1 - st) * 0.06
            }
        case .sleeping:
            breathe = CGFloat(sin(t * 1.3)) * 0.04
            squash = 0.06
        }
        if p.held {
            jump = 0
            squash = -0.12
            shakeX = CGFloat(sin(t * 9)) * 1.2
        }

        let cx: CGFloat = 60 + shakeX
        let ground: CGFloat = 113
        let bw: CGFloat = 72 * (1 + squash)
        let bh: CGFloat = 60 * (1 - squash) * (1 + breathe)
        let by: CGFloat = ground - 5 - jump
        let top = by - bh

        // Shadow on the ground.
        let shW = 56 * (1 - min(jump, 30) / 60)
        ctx.fill(Path(ellipseIn: CGRect(x: 60 - shW / 2, y: ground - 3.5, width: shW, height: 7)),
                 with: .color(.black.opacity(p.held ? 0.06 : 0.16)))

        // Feet.
        var liftL: CGFloat = 0, liftR: CGFloat = 0
        if p.walking && !p.held {
            liftL = max(0, CGFloat(sin(p.walkPhase))) * 5
            liftR = max(0, CGFloat(-sin(p.walkPhase))) * 5
        } else if mood == .annoyed {
            liftR = sin(t * 0.9) > 0 ? max(0, CGFloat(sin(t * 9))) * 3 : 0   // impatient tapping
        } else if mood == .angry {
            liftL = max(0, CGFloat(sin(t * 5))) * 3
            liftR = max(0, CGFloat(-sin(t * 5))) * 3
        }
        let dangle: CGFloat = p.held ? 4 : 0
        let footFill = pal.bottom.mix(pal.line, 0.12).color
        for (dx, lift) in [(-17 as CGFloat, liftL), (17, liftR)] {
            let swing: CGFloat = p.held ? CGFloat(sin(t * 10 + Double(dx))) * 2 : 0
            let r = CGRect(x: cx + dx - 8.5 + swing, y: by - 3 - lift + dangle, width: 17, height: 9)
            ctx.fill(Path(ellipseIn: r), with: .color(footFill))
            ctx.stroke(Path(ellipseIn: r), with: .color(pal.line.color), lineWidth: 2)
        }

        // Ears (behind the body).
        let earLift: CGFloat = switch mood {
        case .happy, .celebrating: 1.0
        case .normal, .focus: 0.92
        case .annoyed: 0.7
        case .angry: 0.5
        case .sleeping: 0.55
        }
        for side in [-1.0, 1.0] as [CGFloat] {
            let twitch: CGFloat = (mood == .happy && side > 0 && sin(t * 1.3) > 0.95) ? -3 : 0
            let b1 = CGPoint(x: cx + side * bw * 0.08, y: top + bh * 0.12)
            let b2 = CGPoint(x: cx + side * bw * 0.42, y: top + bh * 0.32)
            let tip = CGPoint(x: cx + side * bw * (0.30 + (1 - earLift) * 0.32),
                              y: top - bh * 0.22 * earLift + (1 - earLift) * 8 + twitch)
            var ear = Path()
            ear.move(to: b1); ear.addLine(to: tip); ear.addLine(to: b2); ear.closeSubpath()
            ctx.fill(ear, with: .color(pal.top.color))
            ctx.stroke(ear, with: .color(pal.line.color), style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))
            let c = CGPoint(x: (b1.x + b2.x + tip.x) / 3, y: (b1.y + b2.y + tip.y) / 3)
            func inward(_ q: CGPoint) -> CGPoint { CGPoint(x: c.x + (q.x - c.x) * 0.5, y: c.y + (q.y - c.y) * 0.5 + 2) }
            var inner = Path()
            inner.move(to: inward(b1)); inner.addLine(to: inward(tip)); inner.addLine(to: inward(b2)); inner.closeSubpath()
            ctx.fill(inner, with: .color(RGBA(0xFF9FB2, 0.7).color))
        }

        // Body.
        let body = bodyPath(cx: cx, top: top, bottom: by, w: bw, h: bh)
        ctx.fill(body, with: .linearGradient(Gradient(colors: [pal.top.color, pal.bottom.color]),
                                             startPoint: CGPoint(x: cx, y: top), endPoint: CGPoint(x: cx, y: by)))
        ctx.fill(Path(ellipseIn: CGRect(x: cx - bw * 0.30, y: top + bh * 0.10, width: bw * 0.26, height: bh * 0.16)),
                 with: .color(.white.opacity(0.45)))
        ctx.stroke(body, with: .color(pal.line.color), lineWidth: 2.4)

        // Focus headband.
        if mood == .focus {
            ctx.drawLayer { c in
                c.clip(to: body)
                var band = Path()
                band.move(to: CGPoint(x: cx - bw * 0.55, y: top + bh * 0.30))
                band.addQuadCurve(to: CGPoint(x: cx + bw * 0.55, y: top + bh * 0.30), control: CGPoint(x: cx, y: top + bh * 0.08))
                c.stroke(band, with: .color(RGBA(0xE53935).color), lineWidth: 7)
                c.fill(Path(ellipseIn: CGRect(x: cx - 4, y: top + bh * 0.13, width: 8, height: 8)), with: .color(.white))
                c.fill(Path(ellipseIn: CGRect(x: cx - 2.2, y: top + bh * 0.13 + 1.8, width: 4.4, height: 4.4)), with: .color(RGBA(0xE53935).color))
            }
            let kx = cx - p.facing * bw * 0.47
            let ky = top + bh * 0.28
            for i in 0..<2 {
                let wave = CGFloat(sin(t * 6 + Double(i))) * 3
                var tail = Path()
                tail.move(to: CGPoint(x: kx, y: ky))
                tail.addQuadCurve(to: CGPoint(x: kx - p.facing * 14, y: ky + 4 + CGFloat(i) * 5 + wave),
                                  control: CGPoint(x: kx - p.facing * 7, y: ky - 3 + CGFloat(i) * 4))
                ctx.stroke(tail, with: .color(RGBA(0xE53935).color), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
            }
        }

        // Face.
        let look = p.walking ? p.facing * 0.8 : p.lookX
        let fx = cx + look * bw * 0.07
        let ey = top + bh * 0.48
        let ex = bw * 0.185
        let my = ey + bh * 0.21
        let ink = RGBA(0x2B1B14).color
        let petted = p.hovered && (mood == .normal || mood == .happy)

        // Cheeks.
        let cheekA = pal.cheek.a > 0 ? pal.cheek.a + (p.hovered ? 0.25 : 0) : 0
        if cheekA > 0.01 {
            for side in [-1.0, 1.0] as [CGFloat] {
                ctx.fill(Path(ellipseIn: CGRect(x: fx + side * bw * 0.31 - 6, y: ey + 3, width: 12, height: 6.5)),
                         with: .color(RGBA(r: pal.cheek.r, g: pal.cheek.g, b: pal.cheek.b, a: min(1, cheekA)).color))
            }
        }

        let blink = t.truncatingRemainder(dividingBy: 4.3) < 0.13
        func roundEye(_ x: CGFloat, w: CGFloat = 8, h: CGFloat = 10) {
            if blink {
                var l = Path(); l.move(to: CGPoint(x: x - w / 2, y: ey)); l.addLine(to: CGPoint(x: x + w / 2, y: ey))
                ctx.stroke(l, with: .color(ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                return
            }
            ctx.fill(Path(ellipseIn: CGRect(x: x - w / 2, y: ey - h / 2, width: w, height: h)), with: .color(ink))
            ctx.fill(Path(ellipseIn: CGRect(x: x - w / 2 + 1.2, y: ey - h / 2 + 1.4, width: 3.4, height: 3.4)), with: .color(.white))
        }
        func arcEye(_ x: CGFloat, up: Bool) {
            var a = Path()
            a.move(to: CGPoint(x: x - 5, y: ey + (up ? 2 : -1)))
            a.addQuadCurve(to: CGPoint(x: x + 5, y: ey + (up ? 2 : -1)), control: CGPoint(x: x, y: ey + (up ? -6 : 4)))
            ctx.stroke(a, with: .color(ink), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        }
        func brow(_ x: CGFloat, side: CGFloat, inner: CGFloat, outer: CGFloat, width: CGFloat) {
            var b = Path()
            b.move(to: CGPoint(x: x - side * 6, y: ey - outer))
            b.addLine(to: CGPoint(x: x + side * 4, y: ey - inner))
            ctx.stroke(b, with: .color(ink), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }

        for side in [-1.0, 1.0] as [CGFloat] {
            let x = fx + side * ex
            if p.held {
                ctx.fill(Path(ellipseIn: CGRect(x: x - 5.5, y: ey - 6, width: 11, height: 12)), with: .color(.white))
                ctx.stroke(Path(ellipseIn: CGRect(x: x - 5.5, y: ey - 6, width: 11, height: 12)), with: .color(ink), lineWidth: 1.8)
                ctx.fill(Path(ellipseIn: CGRect(x: x - 2, y: ey - 1.5, width: 4, height: 4)), with: .color(ink))
                continue
            }
            switch mood {
            case .happy: arcEye(x, up: true)
            case .celebrating:
                ctx.fill(Path(ellipseIn: CGRect(x: x - 5.5, y: ey - 7, width: 11, height: 13)), with: .color(ink))
                ctx.fill(Path(ellipseIn: CGRect(x: x - 4, y: ey - 5.5, width: 4.5, height: 4.5)), with: .color(.white))
                ctx.fill(Path(ellipseIn: CGRect(x: x + 0.8, y: ey + 1.5, width: 2.2, height: 2.2)), with: .color(.white))
            case .normal:
                if petted { arcEye(x, up: true) } else { roundEye(x) }
            case .focus:
                roundEye(x, w: 8, h: 8)
                brow(x, side: -side, inner: 7.5, outer: 9.5, width: 2.4)
            case .annoyed:
                ctx.drawLayer { c in
                    c.clip(to: Path(CGRect(x: x - 6, y: ey - 0.5, width: 12, height: 8)))
                    c.fill(Path(ellipseIn: CGRect(x: x - 4, y: ey - 5, width: 8, height: 10)), with: .color(ink))
                }
                var lid = Path()
                lid.move(to: CGPoint(x: x - 5.5, y: ey - 0.5 - side * 0.8))
                lid.addLine(to: CGPoint(x: x + 5.5, y: ey - 0.5 + side * 0.8))
                ctx.stroke(lid, with: .color(ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                brow(x, side: -side, inner: 7, outer: 9, width: 2)
            case .angry:
                ctx.fill(Path(ellipseIn: CGRect(x: x - 3.5, y: ey - 3, width: 7, height: 8)), with: .color(ink))
                brow(x, side: -side, inner: 4.5, outer: 11, width: 3.2)
            case .sleeping:
                arcEye(x, up: false)
            }
        }

        // Mouth.
        let mouthDark = RGBA(0x5A2A1E).color
        let tongue = RGBA(0xFF7A8A).color
        if p.held {
            ctx.fill(Path(ellipseIn: CGRect(x: fx - 3, y: my - 1, width: 6, height: 7)), with: .color(mouthDark))
        } else {
            switch mood {
            case .normal where !petted, .focus:
                var w = Path()
                w.move(to: CGPoint(x: fx - 6, y: my))
                w.addQuadCurve(to: CGPoint(x: fx, y: my + 0.5), control: CGPoint(x: fx - 3, y: my + 4))
                w.addQuadCurve(to: CGPoint(x: fx + 6, y: my), control: CGPoint(x: fx + 3, y: my + 4))
                ctx.stroke(w, with: .color(pal.line.color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            case .happy, .normal, .celebrating:
                let big: CGFloat = mood == .celebrating ? 1.35 : 1
                var m = Path()
                m.move(to: CGPoint(x: fx - 7 * big, y: my - 1))
                m.addQuadCurve(to: CGPoint(x: fx + 7 * big, y: my - 1), control: CGPoint(x: fx, y: my + 12 * big))
                m.closeSubpath()
                ctx.fill(m, with: .color(mouthDark))
                ctx.drawLayer { c in
                    c.clip(to: m)
                    c.fill(Path(ellipseIn: CGRect(x: fx - 4 * big, y: my + 2.5 * big, width: 8 * big, height: 6 * big)), with: .color(tongue))
                }
                ctx.stroke(m, with: .color(pal.line.color), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            case .annoyed:
                var f = Path()
                f.move(to: CGPoint(x: fx - 6, y: my + 3))
                f.addCurve(to: CGPoint(x: fx + 6, y: my + 2), control1: CGPoint(x: fx - 2, y: my - 1.5), control2: CGPoint(x: fx + 2, y: my + 5))
                ctx.stroke(f, with: .color(pal.line.color), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            case .angry:
                let r = CGRect(x: fx - 8, y: my - 1.5, width: 16, height: 8)
                ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(.white))
                var teeth = Path()
                teeth.move(to: CGPoint(x: r.minX + 1, y: r.midY)); teeth.addLine(to: CGPoint(x: r.maxX - 1, y: r.midY))
                for i in 1...3 {
                    let x = r.minX + r.width * CGFloat(i) / 4
                    teeth.move(to: CGPoint(x: x, y: r.minY + 0.5)); teeth.addLine(to: CGPoint(x: x, y: r.maxY - 0.5))
                }
                ctx.stroke(teeth, with: .color(pal.line.color.opacity(0.6)), lineWidth: 1)
                ctx.stroke(Path(roundedRect: r, cornerRadius: 3), with: .color(pal.line.color), lineWidth: 1.8)
            case .sleeping:
                ctx.fill(Path(ellipseIn: CGRect(x: fx - 2, y: my, width: 4, height: 3.5)), with: .color(mouthDark))
                let r = 2 + 3 * abs(CGFloat(sin(t * 1.3)))
                let bubble = Path(ellipseIn: CGRect(x: fx + 7 - r, y: my - 5 - r, width: r * 2, height: r * 2))
                ctx.fill(bubble, with: .color(RGBA(0xBFE6FF, 0.55).color))
                ctx.stroke(bubble, with: .color(RGBA(0x7CB8E0).color), lineWidth: 1)
            }
        }

        // Arms.
        let armFill = pal.top.mix(pal.bottom, 0.6).color
        func arm(_ c: CGPoint, _ angle: CGFloat, w: CGFloat = 11, h: CGFloat = 16) {
            let e = Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
                .applying(CGAffineTransform(rotationAngle: angle))
                .applying(CGAffineTransform(translationX: c.x, y: c.y))
            ctx.fill(e, with: .color(armFill))
            ctx.stroke(e, with: .color(pal.line.color), lineWidth: 2)
        }
        let shoulderY = by - bh * 0.36
        if p.held {
            for side in [-1.0, 1.0] as [CGFloat] {
                arm(CGPoint(x: cx + side * bw * 0.52, y: top + bh * 0.32), side * (2.4 + CGFloat(sin(t * 14)) * 0.3))
            }
        } else {
            switch mood {
            case .celebrating:
                for side in [-1.0, 1.0] as [CGFloat] {
                    arm(CGPoint(x: cx + side * bw * 0.5, y: top + bh * 0.18), side * (2.6 + CGFloat(sin(t * 12)) * 0.25))
                }
            case .happy where !p.walking:
                arm(CGPoint(x: cx - bw * 0.5, y: shoulderY), 0.35)
                arm(CGPoint(x: cx + bw * 0.52, y: top + bh * 0.3), -2.3 + CGFloat(sin(t * 8)) * 0.45)
            case .annoyed where !p.walking:
                // Crossed arms.
                for (a, b) in [(CGPoint(x: cx - bw * 0.38, y: by - bh * 0.14), CGPoint(x: cx + bw * 0.14, y: by - bh * 0.05)),
                               (CGPoint(x: cx + bw * 0.38, y: by - bh * 0.14), CGPoint(x: cx - bw * 0.14, y: by - bh * 0.05))] {
                    var l = Path(); l.move(to: a); l.addLine(to: b)
                    ctx.stroke(l, with: .color(pal.line.color), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    ctx.stroke(l, with: .color(armFill), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                }
            case .angry:
                for side in [-1.0, 1.0] as [CGFloat] {
                    let shake = CGFloat(sin(t * 20 + Double(side))) * 2
                    let c = CGPoint(x: cx + side * bw * 0.5, y: top + bh * 0.52 + shake)
                    let r = CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)
                    ctx.fill(Path(ellipseIn: r), with: .color(armFill))
                    ctx.stroke(Path(ellipseIn: r), with: .color(pal.line.color), lineWidth: 2)
                }
            case .sleeping:
                break
            default:
                let swing: CGFloat = p.walking ? CGFloat(sin(p.walkPhase)) * 0.5 : CGFloat(sin(t * 2)) * 0.06
                arm(CGPoint(x: cx - bw * 0.5, y: shoulderY), 0.35 + swing)
                arm(CGPoint(x: cx + bw * 0.5, y: shoulderY), -0.35 + swing)
            }
        }

        // Effects.
        switch mood {
        case .happy:
            for (i, pt) in [CGPoint(x: cx - 42, y: top + 4), CGPoint(x: cx + 43, y: top - 4), CGPoint(x: cx + 30, y: top - 18)].enumerated() {
                let sc = 0.45 + 0.55 * abs(CGFloat(sin(t * 3 + Double(i) * 2.1)))
                ctx.fill(sparkle(at: pt, r: 6 * sc), with: .color(RGBA(0xFFC93C).color.opacity(0.9)))
            }
        case .celebrating:
            let colors: [UInt32] = [0xFF5C8A, 0xFFC93C, 0x4FC3F7, 0x66BB6A, 0xAB47BC]
            for i in 0..<16 {
                let seed = Double(i) * 7.31
                let speed = 38 + (seed.truncatingRemainder(dividingBy: 5)) * 9
                let y = CGFloat((t * speed + seed * 37).truncatingRemainder(dividingBy: 125)) - 8
                let x = CGFloat((seed * 53).truncatingRemainder(dividingBy: 116)) + 2 + CGFloat(sin(t * 2 + seed)) * 6
                let piece = Path(CGRect(x: -2, y: -3.5, width: 4, height: 7))
                    .applying(CGAffineTransform(rotationAngle: CGFloat(t * 3 + seed)))
                    .applying(CGAffineTransform(translationX: x, y: y))
                ctx.fill(piece, with: .color(RGBA(colors[i % colors.count]).color.opacity(Double(max(0, 1 - y / 125)))))
            }
            ctx.fill(sparkle(at: CGPoint(x: cx - 40, y: top + 2), r: 7), with: .color(RGBA(0xFFC93C).color))
            ctx.fill(sparkle(at: CGPoint(x: cx + 40, y: top - 6), r: 5), with: .color(RGBA(0xFFC93C).color))
        case .annoyed:
            let slide = CGFloat((t * 5).truncatingRemainder(dividingBy: 9))
            ctx.fill(drop(at: CGPoint(x: cx + bw * 0.40, y: top + bh * 0.12 + slide)), with: .color(RGBA(0x9ED8FF).color))
            ctx.stroke(drop(at: CGPoint(x: cx + bw * 0.40, y: top + bh * 0.12 + slide)), with: .color(RGBA(0x3A8DC7).color), lineWidth: 1.2)
        case .angry:
            let pulse = 1 + 0.15 * CGFloat(sin(t * 8))
            ctx.draw(Text("💢").font(.system(size: 15 * pulse)), at: CGPoint(x: cx + bw * 0.36, y: top + 2))
            for i in 0..<3 {
                let ph = (t * 0.9 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let r = CGFloat(3 + ph * 6)
                for side in [-1.0, 1.0] as [CGFloat] {
                    let c = CGPoint(x: cx + side * (bw * 0.42 + CGFloat(ph) * 10), y: top + 10 - CGFloat(ph) * 26)
                    let puff = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                    ctx.fill(puff, with: .color(.white.opacity((1 - ph) * 0.85)))
                    ctx.stroke(puff, with: .color(.gray.opacity((1 - ph) * 0.5)), lineWidth: 1)
                }
            }
        case .sleeping:
            for i in 0..<3 {
                let ph = (t * 0.35 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let size = 9 + ph * 7
                ctx.draw(Text("Z").font(.system(size: size, weight: .heavy, design: .rounded))
                    .foregroundColor(pal.line.color.opacity(sin(ph * .pi))),
                         at: CGPoint(x: cx + 24 + CGFloat(ph) * 18, y: top - 2 - CGFloat(ph) * 24))
            }
        default:
            break
        }
        if petted {
            let ph = (t * 0.6).truncatingRemainder(dividingBy: 1)
            ctx.draw(Text("♥").font(.system(size: 12 + ph * 4, weight: .bold)).foregroundColor(RGBA(0xFF5C8A).color.opacity(1 - ph)),
                     at: CGPoint(x: cx - 30, y: top - CGFloat(ph) * 18))
        }
    }

    static func bodyPath(cx: CGFloat, top: CGFloat, bottom: CGFloat, w: CGFloat, h: CGFloat) -> Path {
        var p = Path()
        let l = cx - w / 2, r = cx + w / 2
        p.move(to: CGPoint(x: cx, y: top))
        p.addCurve(to: CGPoint(x: r, y: bottom - h * 0.38), control1: CGPoint(x: cx + w * 0.40, y: top), control2: CGPoint(x: r, y: top + h * 0.22))
        p.addCurve(to: CGPoint(x: cx, y: bottom), control1: CGPoint(x: r, y: bottom - h * 0.04), control2: CGPoint(x: cx + w * 0.36, y: bottom))
        p.addCurve(to: CGPoint(x: l, y: bottom - h * 0.38), control1: CGPoint(x: cx - w * 0.36, y: bottom), control2: CGPoint(x: l, y: bottom - h * 0.04))
        p.addCurve(to: CGPoint(x: cx, y: top), control1: CGPoint(x: l, y: top + h * 0.22), control2: CGPoint(x: cx - w * 0.40, y: top))
        p.closeSubpath()
        return p
    }

    static func sparkle(at c: CGPoint, r: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: c)
        return p
    }

    static func drop(at c: CGPoint) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - 6))
        p.addCurve(to: CGPoint(x: c.x, y: c.y + 4), control1: CGPoint(x: c.x + 2, y: c.y - 2), control2: CGPoint(x: c.x + 5, y: c.y + 4))
        p.addCurve(to: CGPoint(x: c.x, y: c.y - 6), control1: CGPoint(x: c.x - 5, y: c.y + 4), control2: CGPoint(x: c.x - 2, y: c.y - 2))
        return p
    }
}
