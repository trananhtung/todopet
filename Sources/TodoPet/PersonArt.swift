import SwiftUI

/// Which pet you have: Mochi, or Bảnh Bao, a chibi person ("bảnh bao" is dapper; "bánh bao" a round steamed bun).
enum Species: String, CaseIterable, Identifiable {
    case mochi, person

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mochi: L("Mochi (bánh mochi tai mèo)", "Mochi (a cat-eared mochi)")
        case .person: L("Bảnh Bao (người tí hon)", "Bảnh Bao (a tiny person)")
        }
    }
}

/// The pet drawn everywhere (pet window, board, wardrobe), synced from `Prefs.species`.
nonisolated(unsafe) var currentSpecies: Species = .mochi

/// Bảnh Bao: a chibi guy with spiky black hair swept forward, a charcoal polo with a collar, white trousers,
/// white sneakers and a black crossbody bag, who gives a thumbs-up when he's happy. The face, moods, gestures,
/// accessories and effects are shared with Mochi (`PetArt.draw`); this draws the parts that differ.
enum PersonArt {
    struct Geo {
        var cx: CGFloat
        /// The head: `top`…`by` (chin), `bw` wide, `bh` tall.
        var top: CGFloat
        var by: CGFloat
        var bw: CGFloat
        var bh: CGFloat
        /// Where the polo ends and the trousers start.
        var hipY: CGFloat
        /// The soles, lifted by a jump.
        var footY: CGFloat
        var line: Color
        var t: Double
    }

    static let hair = RGBA(0x1E1B1B)
    static let polo = RGBA(0x4A4F58)
    static let collar = RGBA(0x5D636D)
    static let pants = RGBA(0xF4F2EC)
    static let pantsShade = RGBA(0xD9D4C8)
    static let bag = RGBA(0x1F1F22)
    static let skin = RGBA(0xF6D3B6)

    static func palette(_ m: Mood) -> PetPalette {
        switch m {
        case .happy, .celebrating:
            PetPalette(top: RGBA(0xFDE6D0), bottom: RGBA(0xF3C5A2), line: RGBA(0x6A4030), cheek: RGBA(0xFF7F96, 0.42))
        case .normal, .focus:
            PetPalette(top: RGBA(0xFCE3CC), bottom: RGBA(0xF0C3A2), line: RGBA(0x6A4030), cheek: RGBA(0xFF8FA3, 0.30))
        case .annoyed:
            PetPalette(top: RGBA(0xF6E6D8), bottom: RGBA(0xE4CAB4), line: RGBA(0x5E4A3E), cheek: RGBA(0xC98F8F, 0.12))
        case .angry:
            PetPalette(top: RGBA(0xFFC6AE), bottom: RGBA(0xEF9379), line: RGBA(0x7A2A1A), cheek: RGBA(0xB02A1E, 0.0))
        case .sleeping:
            PetPalette(top: RGBA(0xF4E4D8), bottom: RGBA(0xDDC7BC), line: RGBA(0x4D4775), cheek: RGBA(0xFF9FB8, 0.22))
        }
    }

    /// A round chibi face with a soft chin.
    static func headPath(cx: CGFloat, top: CGFloat, w: CGFloat, h: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: cx - w / 2, y: top + h * 0.5))
        p.addCurve(to: CGPoint(x: cx, y: top), control1: CGPoint(x: cx - w / 2, y: top + h * 0.12), control2: CGPoint(x: cx - w * 0.28, y: top))
        p.addCurve(to: CGPoint(x: cx + w / 2, y: top + h * 0.5), control1: CGPoint(x: cx + w * 0.28, y: top), control2: CGPoint(x: cx + w / 2, y: top + h * 0.12))
        p.addCurve(to: CGPoint(x: cx, y: top + h), control1: CGPoint(x: cx + w / 2, y: top + h * 0.84), control2: CGPoint(x: cx + w * 0.22, y: top + h))
        p.addCurve(to: CGPoint(x: cx - w / 2, y: top + h * 0.5), control1: CGPoint(x: cx - w * 0.22, y: top + h), control2: CGPoint(x: cx - w / 2, y: top + h * 0.84))
        p.closeSubpath()
        return p
    }

    static func torsoPath(_ g: Geo) -> Path {
        Path(roundedRect: CGRect(x: g.cx - 17, y: g.by - 5, width: 34, height: g.hipY - g.by + 6), cornerRadius: 9)
    }

    /// Legs, sneakers, neck, the polo, the bag and the ears: everything behind the head.
    static func drawBody(_ ctx: inout GraphicsContext, _ g: Geo, liftL: CGFloat, liftR: CGFloat, facing: CGFloat, held: Bool) {
        let line = g.line
        // Trousers and sneakers.
        for (dx, lift) in [(-8.5 as CGFloat, liftL), (8.5, liftR)] {
            let dangle: CGFloat = held ? CGFloat(sin(g.t * 10 + Double(dx))) * 2 : 0
            let bottom = g.footY - 4 - lift
            let leg = CGRect(x: g.cx + dx - 6.5 + dangle, y: g.hipY - 3, width: 13, height: max(4, bottom - g.hipY + 3))
            ctx.fill(Path(roundedRect: leg, cornerRadius: 4), with: .color(pants.color))
            ctx.fill(Path(CGRect(x: leg.minX + 1, y: leg.minY + 1, width: 3, height: leg.height - 2)), with: .color(pantsShade.color.opacity(0.6)))
            ctx.stroke(Path(roundedRect: leg, cornerRadius: 4), with: .color(line), lineWidth: 1.6)
            let shoe = CGRect(x: leg.midX - 8 + facing * 1.5, y: bottom - 3, width: 16, height: 8)
            ctx.fill(Path(roundedRect: shoe, cornerRadius: 4), with: .color(.white))
            ctx.fill(Path(roundedRect: CGRect(x: shoe.minX, y: shoe.maxY - 2.5, width: shoe.width, height: 2.5), cornerRadius: 1.2),
                     with: .color(RGBA(0xCFCFCF).color))
            var stripe = Path()
            stripe.move(to: CGPoint(x: shoe.minX + 4, y: shoe.minY + 4.5))
            stripe.addQuadCurve(to: CGPoint(x: shoe.maxX - 4, y: shoe.minY + 3), control: CGPoint(x: shoe.midX, y: shoe.minY + 6.5))
            ctx.stroke(stripe, with: .color(RGBA(0x26262A).color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            ctx.stroke(Path(roundedRect: shoe, cornerRadius: 4), with: .color(line), lineWidth: 1.6)
        }
        // Neck.
        ctx.fill(Path(CGRect(x: g.cx - 5, y: g.by - 6, width: 10, height: 9)), with: .color(skin.mix(RGBA(0xC9937A), 0.25).color))
        // Polo with a collar and two buttons.
        let torso = torsoPath(g)
        ctx.fill(torso, with: .linearGradient(Gradient(colors: [polo.mix(RGBA(0xFFFFFF), 0.08).color, polo.color]),
                                              startPoint: CGPoint(x: g.cx, y: g.by), endPoint: CGPoint(x: g.cx, y: g.hipY)))
        ctx.stroke(torso, with: .color(line), lineWidth: 1.8)
        for side in [-1.0, 1.0] as [CGFloat] {
            var c = Path()
            c.move(to: CGPoint(x: g.cx, y: g.by + 3))
            c.addLine(to: CGPoint(x: g.cx + side * 9, y: g.by - 3))
            c.addLine(to: CGPoint(x: g.cx + side * 8, y: g.by + 4))
            c.closeSubpath()
            ctx.fill(c, with: .color(collar.color))
            ctx.stroke(c, with: .color(line), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
        }
        var placket = Path()
        placket.move(to: CGPoint(x: g.cx, y: g.by + 3)); placket.addLine(to: CGPoint(x: g.cx, y: g.by + 11))
        ctx.stroke(placket, with: .color(RGBA(0x2E3138).color), lineWidth: 1.2)
        for y in [g.by + 6, g.by + 9.5] {
            ctx.fill(Path(ellipseIn: CGRect(x: g.cx - 1.1, y: y - 1.1, width: 2.2, height: 2.2)), with: .color(RGBA(0xBFC3C9).color))
        }
        // The crossbody strap, from the far shoulder to the bag at the near hip.
        var strap = Path()
        strap.move(to: CGPoint(x: g.cx + 13, y: g.by - 2))
        strap.addLine(to: CGPoint(x: g.cx - 13, y: g.hipY - 7))
        ctx.stroke(strap, with: .color(bag.color), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        let b = CGRect(x: g.cx - 27, y: g.hipY - 10, width: 18, height: 13)
        ctx.fill(Path(roundedRect: b, cornerRadius: 3), with: .color(bag.color))
        var flap = Path()
        flap.move(to: CGPoint(x: b.minX, y: b.minY + 5)); flap.addQuadCurve(to: CGPoint(x: b.maxX, y: b.minY + 5), control: CGPoint(x: b.midX, y: b.minY + 8))
        ctx.stroke(flap, with: .color(.white.opacity(0.25)), lineWidth: 1)
        ctx.fill(Path(roundedRect: CGRect(x: b.minX + 2, y: b.minY + 1.5, width: 5, height: 1.4), cornerRadius: 0.7), with: .color(.white.opacity(0.35)))
        ctx.stroke(Path(roundedRect: b, cornerRadius: 3), with: .color(line), lineWidth: 1.4)
    }

    /// Ears, behind the head.
    static func drawEars(_ ctx: inout GraphicsContext, _ g: Geo, ey: CGFloat, pal: PetPalette) {
        for side in [-1.0, 1.0] as [CGFloat] {
            let r = CGRect(x: g.cx + side * g.bw * 0.49 - 4, y: ey - 5, width: 8, height: 11)
            ctx.fill(Path(ellipseIn: r), with: .color(pal.bottom.color))
            ctx.stroke(Path(ellipseIn: r), with: .color(pal.line.color), lineWidth: 1.8)
        }
    }

    /// Spiky black hair swept forward: tufts stand up when he's angry and lie flat when he's worried or asleep.
    static func drawHair(_ ctx: inout GraphicsContext, _ g: Geo, mood: Mood) {
        let lift: CGFloat = switch mood {
        case .angry: 1.25
        case .happy, .celebrating: 1.05
        case .normal, .focus: 0.95
        case .annoyed: 0.55
        case .sleeping: 0.45
        }
        let a = g.bw / 2
        func X(_ f: CGFloat) -> CGFloat { g.cx + f * a }
        func Y(_ f: CGFloat) -> CGFloat { g.top + f * g.bh }
        var h = Path()
        h.move(to: CGPoint(x: X(-1.02), y: Y(0.5)))
        h.addCurve(to: CGPoint(x: X(-0.62), y: g.top - 2), control1: CGPoint(x: X(-1.1), y: Y(0.14)), control2: CGPoint(x: X(-0.9), y: g.top - 2))
        // Tufts across the top: [end x, end y above top, peak height].
        let tufts: [(CGFloat, CGFloat, CGFloat)] = [(-0.3, -4, 10), (0.02, -5, 13), (0.36, -4, 12), (0.72, 0, 8)]
        var px: CGFloat = -0.62
        for (x, y, peak) in tufts {
            h.addQuadCurve(to: CGPoint(x: X(x), y: g.top + y), control: CGPoint(x: X((px + x) / 2 + 0.06), y: g.top - 2 - peak * lift))
            px = x
        }
        h.addCurve(to: CGPoint(x: X(1.02), y: Y(0.48)), control1: CGPoint(x: X(1.0), y: g.top + 3), control2: CGPoint(x: X(1.1), y: Y(0.2)))
        // The fringe, back along the forehead with points swept toward the face.
        let fringe: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.78, 0.40, 0.56, 0.26), (0.36, 0.42, 0.14, 0.27), (-0.06, 0.43, -0.28, 0.28), (-0.5, 0.42, -0.72, 0.3),
        ]
        h.addQuadCurve(to: CGPoint(x: X(0.9), y: Y(0.3)), control: CGPoint(x: X(0.98), y: Y(0.36)))
        for (tx, ty, bx, by) in fringe {
            h.addQuadCurve(to: CGPoint(x: X(tx), y: Y(ty)), control: CGPoint(x: X(tx + 0.12), y: Y(ty - 0.02)))
            h.addQuadCurve(to: CGPoint(x: X(bx), y: Y(by)), control: CGPoint(x: X(tx - 0.06), y: Y(ty - 0.04)))
        }
        h.addQuadCurve(to: CGPoint(x: X(-1.02), y: Y(0.5)), control: CGPoint(x: X(-0.95), y: Y(0.32)))
        h.closeSubpath()
        ctx.fill(h, with: .color(hair.color))
        ctx.stroke(h, with: .color(RGBA(0x0E0C0C).color), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
        var shine = Path()
        shine.move(to: CGPoint(x: X(-0.45), y: g.top + 2))
        shine.addQuadCurve(to: CGPoint(x: X(0.15), y: g.top + 1), control: CGPoint(x: X(-0.15), y: g.top - 3))
        ctx.stroke(shine, with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
    }

    /// Thick dark eyebrows for the calm faces (the other moods draw their own).
    static func drawBrows(_ ctx: inout GraphicsContext, fx: CGFloat, ey: CGFloat, ex: CGFloat, raised: CGFloat) {
        for side in [-1.0, 1.0] as [CGFloat] {
            var b = Path()
            b.move(to: CGPoint(x: fx + side * ex - 5, y: ey - 9 - raised))
            b.addQuadCurve(to: CGPoint(x: fx + side * ex + 5, y: ey - 9 - raised), control: CGPoint(x: fx + side * ex, y: ey - 12 - raised))
            ctx.stroke(b, with: .color(RGBA(0x1E1B1B).color), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        }
    }

    enum Hand { case open, fist, thumb }

    /// Arms in polo sleeves, from the shoulders to the hands, in every mood and gesture.
    static func drawArms(_ ctx: inout GraphicsContext, _ g: Geo, pose p: PetPose, mood: Mood, celebrating: Bool, pal: PetPalette) {
        let t = g.t
        let line = g.line
        func limb(_ side: CGFloat, _ end: CGPoint, _ hand: Hand) {
            let s = CGPoint(x: g.cx + side * 14, y: g.by + 3)
            var arm = Path()
            arm.move(to: s)
            arm.addQuadCurve(to: end, control: CGPoint(x: (s.x + end.x) / 2 + side * 3, y: (s.y + end.y) / 2))
            ctx.stroke(arm, with: .color(line), style: StrokeStyle(lineWidth: 9.6, lineCap: .round))
            ctx.stroke(arm, with: .color(polo.mix(RGBA(0xFFFFFF), 0.06).color), style: StrokeStyle(lineWidth: 6.8, lineCap: .round))
            let r: CGFloat = hand == .open ? 4.4 : 3.9
            let hr = CGRect(x: end.x - r, y: end.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: hr), with: .color(pal.bottom.color))
            ctx.stroke(Path(ellipseIn: hr), with: .color(pal.line.color), lineWidth: 1.4)
            if hand == .thumb {
                let thumb = Path(roundedRect: CGRect(x: end.x - 1.8, y: end.y - r - 5.5, width: 3.6, height: 7), cornerRadius: 1.8)
                ctx.fill(thumb, with: .color(pal.bottom.color))
                ctx.stroke(thumb, with: .color(pal.line.color), lineWidth: 1.3)
            }
        }
        let swing: CGFloat = p.walking ? CGFloat(sin(p.walkPhase)) * 4 : CGFloat(sin(t * 2)) * 0.6
        let down = { (side: CGFloat, dy: CGFloat) in CGPoint(x: g.cx + side * 21, y: g.hipY - 1 + dy) }
        if p.held {
            for side in [-1.0, 1.0] as [CGFloat] {
                limb(side, CGPoint(x: g.cx + side * 25, y: g.by - 9 + CGFloat(sin(t * 14 + Double(side))) * 3), .open)
            }
            return
        }
        if !celebrating, let gesture = p.gesture {
            switch gesture {
            case .wave:
                limb(-1, down(-1, 0), .open)
                limb(1, CGPoint(x: g.cx + 26 + CGFloat(sin(t * 11)) * 3, y: g.by - 15), .open)
                return
            case .yawn:
                let up = CGFloat(sin(p.gestureP * .pi))
                for side in [-1.0, 1.0] as [CGFloat] {
                    limb(side, CGPoint(x: g.cx + side * (21 + 3 * up), y: g.hipY - 1 - up * 30), .fist)
                }
                return
            case .giggle:
                limb(-1, CGPoint(x: g.cx - 7, y: g.by + 8), .fist)
                limb(1, CGPoint(x: g.cx + 7, y: g.by + 8), .fist)
                return
            default:
                break
            }
        }
        switch mood {
        case .celebrating where p.celebration == .blessing:
            for side in [-1.0, 1.0] as [CGFloat] { limb(side, CGPoint(x: g.cx + side * 19, y: g.by - 16), .open) }
        case .celebrating where p.celebration == .dance:
            let up = sin(t * 8) > 0
            limb(-1, up ? CGPoint(x: g.cx - 25, y: g.by - 14) : down(-1, 0), .thumb)
            limb(1, up ? down(1, 0) : CGPoint(x: g.cx + 25, y: g.by - 14), .thumb)
        case .celebrating:
            // Two thumbs up.
            for side in [-1.0, 1.0] as [CGFloat] {
                limb(side, CGPoint(x: g.cx + side * 25, y: g.by - 9 + CGFloat(sin(t * 12 + Double(side))) * 2), .thumb)
            }
        case .happy where !p.walking:
            // A hand on the bag, and a thumbs-up at the chest.
            limb(-1, CGPoint(x: g.cx - 17, y: g.hipY - 5), .fist)
            limb(1, CGPoint(x: g.cx + 6, y: g.by + 9 + CGFloat(sin(t * 4)) * 1), .thumb)
        case .annoyed where !p.walking:
            // Worried: hands held together in front, fidgeting.
            let f = CGFloat(sin(t * 3)) * 1.2
            limb(-1, CGPoint(x: g.cx - 3 + f, y: g.hipY - 5), .fist)
            limb(1, CGPoint(x: g.cx + 3 + f, y: g.hipY - 5), .fist)
        case .angry:
            for side in [-1.0, 1.0] as [CGFloat] {
                limb(side, CGPoint(x: g.cx + side * 24, y: g.by + 5 + CGFloat(sin(t * 20 + Double(side))) * 2), .fist)
            }
        case .focus:
            // Typing away on an invisible keyboard.
            limb(-1, CGPoint(x: g.cx - 9, y: g.hipY - 3 + CGFloat(sin(t * 18)) * 1.2), .fist)
            limb(1, CGPoint(x: g.cx + 9, y: g.hipY - 3 + CGFloat(sin(t * 18 + 1.5)) * 1.2), .fist)
        default:
            limb(-1, down(-1, 0) + CGPoint(x: -swing * 0.4, y: 0), .fist)
            limb(1, down(1, 0) + CGPoint(x: swing * 0.4, y: 0), .fist)
        }
    }
}

private func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
