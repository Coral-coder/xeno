import SwiftUI

struct Palette {
    var space: Color
    var spaceRaised: Color
    var alien: Color
    var beam: Color
    var nebula: Color
    var warn: Color
    var danger: Color
    var text: Color
    var textDim: Color
    var design: Font.Design

    static let biolume = Palette(
        space: Color(red: 0.01, green: 0.05, blue: 0.05),
        spaceRaised: Color(red: 0.03, green: 0.10, blue: 0.10),
        alien: Color(red: 0.36, green: 1.00, blue: 0.66),     // bioluminescent green
        beam: Color(red: 0.30, green: 0.92, blue: 0.95),      // jellyfish cyan
        nebula: Color(red: 0.74, green: 0.50, blue: 1.00),    // spore violet
        warn: Color(red: 1.00, green: 0.80, blue: 0.36),
        danger: Color(red: 1.00, green: 0.36, blue: 0.56),
        text: Color(red: 0.90, green: 1.00, blue: 0.95),
        textDim: Color(red: 0.62, green: 0.82, blue: 0.75).opacity(0.75),
        design: .rounded)

    /// VFD palette, derived from the chosen phosphor colour.
    static var vfd: Palette {
        let p = Theme.tint.palette
        func c(_ i: UInt8) -> Color { let v = p[i]!; return Color(red: v.0, green: v.1, blue: v.2) }
        return Palette(space: .black, spaceRaised: Color(white: 0.035), alien: c(1), beam: c(2), nebula: c(1),
                       warn: c(2), danger: c(4), text: c(2), textDim: c(3), design: .monospaced)
    }
}

enum Theme {
    /// Set from settings; the root view is rebuilt when it changes.
    static var kind: ThemeKind = .biolume
    static var tint: VFDTint = .amber
    static var p: Palette { kind == .vfd ? .vfd : .biolume }
    static var isVFD: Bool { kind == .vfd }

    static var space: Color { p.space }
    static var spaceRaised: Color { p.spaceRaised }
    static var alien: Color { p.alien }
    static var beam: Color { p.beam }
    static var nebula: Color { p.nebula }
    static var warn: Color { p.warn }
    static var danger: Color { p.danger }
    static var text: Color { p.text }
    static var textDim: Color { p.textDim }
    static var design: Font.Design { p.design }

    /// Original square-pixel fonts (scripts/gen_dot_font.py): 5x7, 10x14 and 15x21 glyphs, all
    /// with the same pixel size. Bigger text uses more pixels, never bigger pixels.
    static let dotFont = "XenoDot-Regular"
    static let dotFontMid = "XenoDotMid-Regular"
    static let dotFontBig = "XenoDotBig-Regular"

    /// VFD pixel pitch in points. Every VFD glyph is drawn at exactly this pixel size
    /// (5 device pixels on 3x screens), so the whole theme shares one pixel grid.
    static let vfdPixel: CGFloat = 5.0 / 3.0
    /// The one VFD font size: 10 font units of 100 per pixel cell.
    static var vfdSize: CGFloat { vfdPixel * 10 }
    static var vfdFont: Font { .custom(dotFont, fixedSize: vfdSize) }
    static var vfdFontMid: Font { .custom(dotFontMid, fixedSize: vfdSize) }
    static var vfdFontBig: Font { .custom(dotFontBig, fixedSize: vfdSize) }

    /// Readouts: big digits (15x21 px) for hero values, 10x14 for secondary ones.
    static func reading(_ size: CGFloat = 34) -> Font {
        guard isVFD else { return .system(size: size, weight: .semibold, design: design).monospacedDigit() }
        return size >= 36 ? vfdFontBig : size >= 20 ? vfdFontMid : vfdFont
    }
    /// Monospaced text (hex dumps, logs).
    static func mono(_ style: Font.TextStyle) -> Font { isVFD ? vfdFont : .system(style, design: .monospaced) }
    static var label: Font { font(.caption, weight: .semibold) }

    static func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        guard isVFD else { return .system(style, design: design).weight(weight) }
        switch style {
        case .largeTitle, .title, .title2: return vfdFontMid
        default: return vfdFont
        }
    }

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        isVFD ? (size >= 36 ? vfdFontBig : size >= 20 ? vfdFontMid : vfdFont) : .system(size: size, weight: weight, design: design)
    }

    /// Card / panel outline for the current theme.
    static var cardShape: AnyShape {
        isVFD ? AnyShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
              : AnyShape(UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 10, bottomTrailingRadius: 28, topTrailingRadius: 10, style: .continuous))
    }
    static var buttonShape: AnyShape {
        isVFD ? AnyShape(RoundedRectangle(cornerRadius: 2)) : AnyShape(Capsule())
    }

    static func applyUIKitAppearance() {
        let ui = UIColor(text)
        func font(_ size: CGFloat, _ w: UIFont.Weight) -> UIFont {
            let name = size >= 24 ? dotFontMid : dotFont
            return isVFD ? (UIFont(name: name, size: vfdSize) ?? UIFont.monospacedSystemFont(ofSize: vfdSize, weight: w)) : UIFont.rounded(size: size, weight: w)
        }
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.largeTitleTextAttributes = [.foregroundColor: ui, .font: font(isVFD ? 28 : 32, .bold)]
        nav.titleTextAttributes = [.foregroundColor: ui, .font: font(17, .semibold)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundColor = UIColor(space).withAlphaComponent(0.85)
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = UIColor(textDim)
            item.normal.titleTextAttributes = [.foregroundColor: UIColor(textDim), .font: font(10, .medium)]
            item.selected.iconColor = UIColor(alien)
            item.selected.titleTextAttributes = [.foregroundColor: UIColor(alien), .font: font(10, .semibold)]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UISwitch.appearance().onTintColor = UIColor(alien)
    }
}

/// Backdrop for the current theme.
struct SpaceBackground: View {
    var body: some View {
        Group {
            if Theme.isVFD { VFDBackground() } else { OrganicBackground() }
        }
        .ignoresSafeArea()
    }
}

/// Alien-ship interior: dark membrane, glowing veins, drifting spores.
struct OrganicBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.01, green: 0.07, blue: 0.06), Color(red: 0.015, green: 0.03, blue: 0.06)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.alien.opacity(0.20), .clear], center: UnitPoint(x: 0.9, y: 0.02), startRadius: 4, endRadius: 360)
            RadialGradient(colors: [Theme.nebula.opacity(0.16), .clear], center: UnitPoint(x: 0.05, y: 0.9), startRadius: 4, endRadius: 420)
            RadialGradient(colors: [Theme.beam.opacity(0.08), .clear], center: UnitPoint(x: 0.4, y: 0.5), startRadius: 4, endRadius: 300)
            Canvas { ctx, size in
                var rng = SeededRandom(seed: 7)
                // Veins: wandering branching curves.
                for v in 0..<9 {
                    var p = CGPoint(x: rng.next() * size.width, y: v.isMultiple(of: 2) ? -10 : size.height + 10)
                    var path = Path(); path.move(to: p)
                    let up: CGFloat = v.isMultiple(of: 2) ? 1 : -1
                    for _ in 0..<6 {
                        let next = CGPoint(x: p.x + (rng.next() - 0.5) * 220, y: p.y + up * (60 + rng.next() * 120))
                        let c1 = CGPoint(x: p.x + (rng.next() - 0.5) * 160, y: p.y + up * rng.next() * 80)
                        let c2 = CGPoint(x: next.x + (rng.next() - 0.5) * 160, y: next.y - up * rng.next() * 80)
                        path.addCurve(to: next, control1: c1, control2: c2)
                        if rng.next() > 0.55 {
                            var b = Path(); b.move(to: next)
                            b.addQuadCurve(to: CGPoint(x: next.x + (rng.next() - 0.5) * 140, y: next.y + up * rng.next() * 90),
                                           control: CGPoint(x: next.x + (rng.next() - 0.5) * 90, y: next.y + up * 30))
                            ctx.stroke(b, with: .color(Theme.alien.opacity(0.07)), lineWidth: 1)
                        }
                        p = next
                    }
                    ctx.stroke(path, with: .color(Theme.alien.opacity(0.05)), lineWidth: 7)
                    ctx.stroke(path, with: .color(Theme.alien.opacity(0.13)), lineWidth: 1.4)
                }
                // Spores: soft halo + bright core.
                for i in 0..<70 {
                    let x = rng.next() * size.width, y = rng.next() * size.height
                    let r = 0.8 + rng.next() * 2.2
                    let c = i % 5 == 0 ? Theme.nebula : (i % 3 == 0 ? Theme.beam : Theme.alien)
                    let a = 0.25 + rng.next() * 0.5
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r * 3, y: y - r * 3, width: r * 6, height: r * 6)), with: .color(c.opacity(a * 0.12)))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)), with: .color(c.opacity(a)))
                }
            }
        }
    }
}

/// Warm black glass of a vacuum-fluorescent display.
struct VFDBackground: View {
    var body: some View {
        ZStack {
            Theme.space
            RadialGradient(colors: [Theme.alien.opacity(0.07), .clear], center: .center, startRadius: 10, endRadius: 520)
        }
    }
}

struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) % 10_000) / 10_000
    }
}

struct XenoCard<Content: View>: View {
    var glow: Color = Theme.alien
    @ViewBuilder var content: Content
    var body: some View {
        let shape = Theme.cardShape
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if Theme.isVFD {
                    shape.fill(Theme.spaceRaised.opacity(0.92))
                } else {
                    // Translucent membrane with a faint inner glow from the top-leading lobe.
                    shape.fill(LinearGradient(colors: [glow.opacity(0.10), Theme.spaceRaised.opacity(0.88), Theme.spaceRaised.opacity(0.80)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .overlay {
                if Theme.isVFD {
                    // Double bezel like an instrument display window.
                    ZStack {
                        shape.stroke(glow.opacity(0.75), lineWidth: 1)
                        shape.stroke(glow.opacity(0.22), lineWidth: 1).padding(3)
                    }
                } else {
                    ZStack(alignment: .topLeading) {
                        shape.stroke(LinearGradient(colors: [glow.opacity(0.75), glow.opacity(0.10), glow.opacity(0.35)],
                                                          startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
                        // Bio-node on the membrane edge.
                        Circle().fill(glow).frame(width: 6, height: 6).glow(color: glow, radius: 5)
                            .offset(x: 30, y: -3)
                    }
                }
            }
            .glow(color: glow.opacity(Theme.isVFD ? 0.10 : 0.22), radius: Theme.isVFD ? 4 : 12)
    }
}

struct SectionHeader: View {
    var title: String
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 7) {
            if Theme.isVFD {
                Text("▌").foregroundStyle(Theme.alien)
                Text(title.uppercased()).tracking(2)
                Text(String(repeating: "·", count: 40)).lineLimit(1).foregroundStyle(Theme.textDim)
            } else {
                Circle().fill(Theme.alien).frame(width: 7, height: 7).glow(color: Theme.alien, radius: 4)
                if let symbol { Image(systemName: symbol) }
                Text(title.uppercased()).tracking(1.6)
                Capsule().fill(LinearGradient(colors: [Theme.alien.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1.5)
            }
        }
        .font(Theme.label)
        .foregroundStyle(Theme.alien.opacity(0.9))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }
}

/// Large reading with its unit and caption.
struct ReadingView: View {
    var caption: String
    var value: String
    var unit: String
    var color: Color = Theme.text
    var size: CGFloat = 30
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Theme.isVFD ? caption.uppercased() : caption).font(Theme.label).foregroundStyle(Theme.textDim)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(Theme.reading(size)).foregroundStyle(color)
                    .glow(color: color.opacity(Theme.isVFD ? 0.8 : 0.35), radius: Theme.isVFD ? 5 : 6)
                    .lineLimit(1).xenoScale(0.5)
                Text(unit).font(Theme.font(.footnote)).foregroundStyle(Theme.textDim)
            }
        }
    }
}

struct StatusPill: View {
    var text: String
    var color: Color
    var body: some View {
        let shape = Theme.buttonShape
        Text(text)
            .font(Theme.font(.caption2, weight: .bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(shape.fill(color.opacity(0.18)))
            .overlay(shape.stroke(color.opacity(0.6), lineWidth: 0.8))
            .foregroundStyle(color)
    }
}

struct GlowButtonStyle: ButtonStyle {
    var color: Color = Theme.alien
    func makeBody(configuration: Configuration) -> some View {
        let shape = Theme.isVFD ? AnyShape(RoundedRectangle(cornerRadius: 3)) : AnyShape(UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 8, bottomTrailingRadius: 22, topTrailingRadius: 8, style: .continuous))
        configuration.label
            .font(Theme.font(.headline))
            .textCase(Theme.isVFD ? .uppercase : nil)
            .padding(.vertical, 12).padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(shape.fill(LinearGradient(colors: [color.opacity(configuration.isPressed ? 0.40 : 0.28), color.opacity(configuration.isPressed ? 0.25 : 0.10)], startPoint: .top, endPoint: .bottom)))
            .overlay(shape.stroke(color.opacity(0.85), lineWidth: 1))
            .foregroundStyle(color)
            .glow(color: color.opacity(0.35), radius: configuration.isPressed ? 2 : 8)
    }
}

/// Small alien-head glyph drawn in SwiftUI (used in headers / empty states).
struct AlienGlyph: View {
    var color: Color = Theme.alien
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: w * 0.5, y: h))
                    p.addCurve(to: CGPoint(x: w * 0.02, y: h * 0.36), control1: CGPoint(x: w * 0.22, y: h * 0.9), control2: CGPoint(x: w * 0.0, y: h * 0.62))
                    p.addCurve(to: CGPoint(x: w * 0.98, y: h * 0.36), control1: CGPoint(x: w * 0.06, y: -h * 0.1), control2: CGPoint(x: w * 0.94, y: -h * 0.1))
                    p.addCurve(to: CGPoint(x: w * 0.5, y: h), control1: CGPoint(x: w * 1.0, y: h * 0.62), control2: CGPoint(x: w * 0.78, y: h * 0.9))
                }
                .fill(color)
                Ellipse().fill(Theme.space).frame(width: w * 0.3, height: h * 0.2).rotationEffect(.degrees(28)).position(x: w * 0.3, y: h * 0.5)
                Ellipse().fill(Theme.space).frame(width: w * 0.3, height: h * 0.2).rotationEffect(.degrees(-28)).position(x: w * 0.7, y: h * 0.5)
            }
        }
        .aspectRatio(0.85, contentMode: .fit)
    }
}

extension View {
    func xenoScreen() -> some View {
        self.scrollContentBackground(.hidden).background(SpaceBackground())
            .fontDesign(Theme.isVFD ? nil : Theme.design)
    }
}

extension View {
    /// Bioluminescent glow; the VFD theme draws crisp pixels with no halo.
    func glow(color: Color, radius: CGFloat) -> some View {
        shadow(color: Theme.isVFD ? .clear : color, radius: Theme.isVFD ? 0 : radius)
    }
}

extension View {
    /// Shrink-to-fit, except in VFD where every pixel stays the same size.
    func xenoScale(_ factor: CGFloat) -> some View {
        minimumScaleFactor(Theme.isVFD ? 1 : factor)
    }
}
