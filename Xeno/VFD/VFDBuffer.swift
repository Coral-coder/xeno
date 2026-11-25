import Foundation

/// A VFD frame: a grid of cells, each unlit (0) or lit with a palette colour. Screens draw into
/// it in whole cells (text from bitmap glyphs, boxes, bars), so every pixel on screen sits on
/// one grid and has the same size. `VFDRootView` paints it.
enum VFDColor: UInt8 {
    case off = 0, amber, white, dim, red, green
    // One slot per VFDTint, for colour swatches.
    case tint0 = 10, tint1, tint2, tint3, tint4, tint5, tint6

    static func tint(_ i: Int) -> VFDColor { VFDColor(rawValue: UInt8(10 + i)) ?? .amber }

}

enum VFDTextSize: Int {
    case small = 1, mid = 2, big = 3
    var glyphs: [UInt32: [UInt32]] {
        switch self { case .small: return PixelFontData.small; case .mid: return PixelFontData.mid; case .big: return PixelFontData.big }
    }
    var advance: Int { 6 * rawValue }
    /// Rows from the top of a line to the baseline (7 per scale) plus descender (2 per scale).
    var height: Int { 9 * rawValue }
    var capHeight: Int { 7 * rawValue }
}

struct VFDHit {
    var c0: Int, r0: Int, c1: Int, r1: Int
    /// Screen rows where this hit is visible (the clip region it was drawn in).
    var clip: ClosedRange<Int>
    var action: () -> Void
    func contains(_ c: Int, _ r: Int) -> Bool { c >= c0 && c <= c1 && r >= r0 && r <= r1 && clip.contains(r) }
}

final class VFDBuffer {
    let cols: Int
    let rows: Int
    private(set) var cells: [UInt8]
    private(set) var hits: [VFDHit] = []
    /// Drawing is clipped to these rows (used for the scrolling content region).
    var clipTop = 0
    var clipBottom: Int
    /// Rows the content region is shifted up by (scrolling).
    var scroll = 0
    /// Lowest content row drawn (for scroll limits).
    private(set) var contentBottom = 0
    /// Furthest the content can scroll (set by the root after drawing).
    var maxScroll = 0

    init(cols: Int, rows: Int) {
        self.cols = max(cols, 1); self.rows = max(rows, 1)
        cells = [UInt8](repeating: 0, count: self.cols * self.rows)
        clipBottom = self.rows - 1
    }

    // MARK: Primitives

    func set(_ c: Int, _ r: Int, _ color: VFDColor) {
        let rr = r - scroll
        contentBottom = max(contentBottom, r)
        guard c >= 0, c < cols, rr >= clipTop, rr <= clipBottom, rr < rows else { return }
        cells[rr * cols + c] = color.rawValue
    }

    func color(_ c: Int, _ r: Int) -> VFDColor { VFDColor(rawValue: cells[r * cols + c]) ?? .off }

    func fill(_ c0: Int, _ r0: Int, _ c1: Int, _ r1: Int, _ color: VFDColor) {
        guard c1 >= c0, r1 >= r0 else { return }
        for r in r0...r1 { for c in c0...c1 { set(c, r, color) } }
    }

    func hline(_ c0: Int, _ c1: Int, _ r: Int, _ color: VFDColor, step: Int = 1) {
        guard c1 >= c0 else { return }
        for c in stride(from: c0, through: c1, by: step) { set(c, r, color) }
    }

    func vline(_ c: Int, _ r0: Int, _ r1: Int, _ color: VFDColor, step: Int = 1) {
        guard r1 >= r0 else { return }
        for r in stride(from: r0, through: r1, by: step) { set(c, r, color) }
    }

    func box(_ c0: Int, _ r0: Int, _ c1: Int, _ r1: Int, _ color: VFDColor) {
        hline(c0, c1, r0, color); hline(c0, c1, r1, color); vline(c0, r0, r1, color); vline(c1, r0, r1, color)
    }

    /// Draws text; returns the column after the last character.
    @discardableResult
    func text(_ c: Int, _ r: Int, _ s: String, _ size: VFDTextSize = .small, _ color: VFDColor = .white) -> Int {
        let g = size.glyphs
        let w = 5 * size.rawValue
        var x = c
        for scalar in s.unicodeScalars {
            if let rows = g[scalar.value] ?? g[UInt32(("?" as Unicode.Scalar).value)] {
                for (y, bits) in rows.enumerated() where bits != 0 {
                    for i in 0..<w where bits >> UInt32(i) & 1 == 1 { set(x + i, r + y, color) }
                }
            }
            x += size.advance
        }
        return x
    }

    func width(_ s: String, _ size: VFDTextSize = .small) -> Int { s.unicodeScalars.count * size.advance - size.rawValue }

    /// Right-aligned text ending at column `c1`.
    @discardableResult
    func textRight(_ c1: Int, _ r: Int, _ s: String, _ size: VFDTextSize = .small, _ color: VFDColor = .white) -> Int {
        text(c1 - width(s, size) + 1, r, s, size, color)
    }

    /// Text cut to fit `maxCols` columns.
    @discardableResult
    func text(_ c: Int, _ r: Int, _ s: String, maxCols: Int, _ size: VFDTextSize = .small, _ color: VFDColor = .white) -> Int {
        let fit = max(0, (maxCols + size.rawValue) / size.advance)
        let t = s.unicodeScalars.count > fit ? String(String.UnicodeScalarView(s.unicodeScalars.prefix(max(0, fit - 1)))) + "…" : s
        return text(c, r, t, size, color)
    }

    /// Wraps text to `maxCols`; returns the row after the last line.
    @discardableResult
    func paragraph(_ c: Int, _ r: Int, _ s: String, maxCols: Int, _ color: VFDColor = .white) -> Int {
        let per = max(1, (maxCols + 1) / 6)
        var line = "", y = r
        for word in s.split(separator: " ") {
            let candidate = line.isEmpty ? String(word) : line + " " + word
            if candidate.count > per && !line.isEmpty {
                text(c, y, line, .small, color); y += 10; line = String(word)
            } else { line = candidate }
        }
        if !line.isEmpty { text(c, y, line, .small, color); y += 10 }
        return y
    }

    /// LED bar: dotted track, optional lit zone (0…1), marker or fill.
    func bar(_ c0: Int, _ c1: Int, _ r: Int, marker: Double?, zone: ClosedRange<Double>? = nil, fill: Bool = false, color: VFDColor = .amber) {
        guard c1 > c0 else { return }
        let span = Double(c1 - c0)
        for c in stride(from: c0, through: c1, by: 2) { set(c, r, .dim); set(c, r + 1, .dim) }
        if let z = zone {
            for c in (c0 + Int(span * z.lowerBound))...(c0 + Int(span * z.upperBound)) { set(c, r, .dim); set(c, r + 1, .dim) }
        }
        guard let m = marker else { return }
        let mc = c0 + Int((span * min(max(m, 0), 1)).rounded())
        if fill {
            for c in c0...mc { set(c, r, color); set(c, r + 1, color) }
        } else {
            for c in (mc - 1)...(mc + 1) { for rr in (r - 2)...(r + 3) { set(c, rr, color) } }
        }
    }

    /// Line chart in a box of cells: values oldest first.
    func chart(_ c0: Int, _ r0: Int, _ c1: Int, _ r1: Int, values: [Double], threshold: Double? = nil, log: Bool = false, color: VFDColor = .amber) {
        hline(c0, c1, r1, .dim, step: 2)
        guard values.count > 1, c1 > c0, r1 > r0 else { return }
        func f(_ v: Double) -> Double { log ? log10(max(v, 1)) : v }
        var lo = values.min()!, hi = values.max()!
        if let t = threshold { lo = min(lo, t); hi = max(hi, t) }
        if hi - lo < 1e-9 { hi = lo + 1 }
        let h = Double(r1 - r0 - 1)
        func row(_ v: Double) -> Int { r0 + Int(((1 - (f(v) - f(lo)) / max(f(hi) - f(lo), 1e-9)) * h).rounded()) }
        if let t = threshold { hline(c0, c1, row(t), .red, step: 3) }
        var prev: Int?
        for c in c0...c1 {
            let i = Int(Double(c - c0) / Double(c1 - c0) * Double(values.count - 1))
            let r = row(values[i])
            let p = prev ?? r
            for rr in min(r, p)...max(r, p) { set(c, rr, color) }
            prev = r
        }
    }

    // MARK: Touch

    func hit(_ c0: Int, _ r0: Int, _ c1: Int, _ r1: Int, _ action: @escaping () -> Void) {
        hits.append(VFDHit(c0: c0, r0: r0 - scroll, c1: c1, r1: r1 - scroll, clip: clipTop...max(clipTop, clipBottom), action: action))
    }

    func tap(col: Int, row: Int) -> Bool {
        // Later hits are drawn on top: check them first.
        for h in hits.reversed() where h.contains(col, row) {
            h.action(); return true
        }
        return false
    }

    func resetContentBottom() { contentBottom = 0 }
}
