import SwiftUI

enum Theme {
    static let space = Color(red: 0.02, green: 0.03, blue: 0.07)
    static let spaceRaised = Color(red: 0.06, green: 0.08, blue: 0.13)
    static let alien = Color(red: 0.30, green: 1.00, blue: 0.60)       // ectoplasm green
    static let beam = Color(red: 0.25, green: 0.88, blue: 1.00)        // tractor-beam cyan
    static let nebula = Color(red: 0.66, green: 0.42, blue: 1.00)      // violet
    static let warn = Color(red: 1.00, green: 0.79, blue: 0.30)
    static let danger = Color(red: 1.00, green: 0.33, blue: 0.55)
    static let textDim = Color.white.opacity(0.55)

    static func reading(_ size: CGFloat = 34) -> Font { .system(size: size, weight: .semibold, design: .rounded).monospacedDigit() }
    static let label = Font.system(.caption, design: .rounded).weight(.semibold)
}

/// Deep-space backdrop: gradient, faint green nebula, deterministic starfield.
struct SpaceBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.space, Color(red: 0.03, green: 0.05, blue: 0.10)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.alien.opacity(0.16), .clear], center: UnitPoint(x: 0.85, y: 0.05), startRadius: 5, endRadius: 380)
            RadialGradient(colors: [Theme.nebula.opacity(0.14), .clear], center: UnitPoint(x: 0.1, y: 0.95), startRadius: 5, endRadius: 420)
            Canvas { ctx, size in
                var rng = SeededRandom(seed: 42)
                for _ in 0..<140 {
                    let x = rng.next() * size.width, y = rng.next() * size.height
                    let r = 0.4 + rng.next() * 1.3
                    let a = 0.15 + rng.next() * 0.55
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(a)))
                }
            }
        }
        .ignoresSafeArea()
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
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.spaceRaised.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [glow.opacity(0.55), glow.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .shadow(color: glow.opacity(0.18), radius: 10)
    }
}

struct SectionHeader: View {
    var title: String
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol) }
            Text(title.uppercased()).tracking(1.4)
        }
        .font(Theme.label)
        .foregroundStyle(Theme.alien.opacity(0.85))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }
}

/// Large reading with its unit and caption.
struct ReadingView: View {
    var caption: String
    var value: String
    var unit: String
    var color: Color = .white
    var size: CGFloat = 30
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption).font(Theme.label).foregroundStyle(Theme.textDim)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(Theme.reading(size)).foregroundStyle(color)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(unit).font(.system(.footnote, design: .rounded)).foregroundStyle(Theme.textDim)
            }
        }
    }
}

struct StatusPill: View {
    var text: String
    var color: Color
    var body: some View {
        Text(text)
            .font(.system(.caption2, design: .rounded).weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.18)))
            .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 0.8))
            .foregroundStyle(color)
    }
}

struct GlowButtonStyle: ButtonStyle {
    var color: Color = Theme.alien
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .padding(.vertical, 12).padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(configuration.isPressed ? 0.35 : 0.22)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(color.opacity(0.8), lineWidth: 1))
            .foregroundStyle(color)
            .shadow(color: color.opacity(0.35), radius: configuration.isPressed ? 2 : 8)
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
    }
}
