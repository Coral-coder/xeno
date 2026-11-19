import SwiftUI

/// Helpers for drawing graphics on the VFD pixel grid: every mark is made of the same square
/// pixels as the dot-matrix fonts (pitch `Theme.vfdPixel`; the screen grid draws the gaps).
struct PixelGrid {
    let size: CGSize
    var pitch: CGFloat { Theme.vfdPixel }
    var cols: Int { max(1, Int(size.width / pitch)) }
    var rows: Int { max(1, Int(size.height / pitch)) }

    func rect(_ c: Int, _ r: Int) -> CGRect {
        CGRect(x: CGFloat(c) * pitch, y: CGFloat(r) * pitch, width: pitch, height: pitch)
    }

    func fill(_ ctx: GraphicsContext, _ cells: [(Int, Int)], _ color: Color) {
        var p = Path()
        for (c, r) in cells where c >= 0 && c < cols && r >= 0 && r < rows { p.addRect(rect(c, r)) }
        ctx.fill(p, with: .color(color))
    }
}

/// Line chart on the pixel grid: plotted line, dim fill underneath, dotted limit line.
struct PixelChart: View {
    var values: [Double]          // already converted to display units, oldest first
    var threshold: Double?
    var logScale = false
    var color: Color

    var body: some View {
        let (lo, hi) = range
        HStack(alignment: .top, spacing: 4) {
            Canvas { ctx, size in
                let g = PixelGrid(size: size)
                guard values.count > 1 else { return }
                func row(_ v: Double) -> Int {
                    let t = (map(v) - map(lo)) / max(map(hi) - map(lo), 1e-9)
                    return Int(((1 - t) * Double(g.rows - 1)).rounded())
                }
                // Frame: dotted baseline.
                g.fill(ctx, stride(from: 0, to: g.cols, by: 2).map { ($0, g.rows - 1) }, Theme.textDim.opacity(0.5))
                if let threshold, threshold >= lo, threshold <= hi {
                    let r = row(threshold)
                    g.fill(ctx, stride(from: 0, to: g.cols, by: 3).map { ($0, r) }, Theme.warn)
                }
                // Resample to one value per column.
                var col: [Int] = []
                for c in 0..<g.cols {
                    let i = Int(Double(c) / Double(max(g.cols - 1, 1)) * Double(values.count - 1))
                    col.append(row(values[i]))
                }
                var line: [(Int, Int)] = [], area: [(Int, Int)] = []
                for c in 0..<g.cols {
                    let r = col[c]
                    let prev = c > 0 ? col[c - 1] : r
                    for rr in min(r, prev)...max(r, prev) { line.append((c, rr)) }
                    if r + 1 < g.rows - 1 { for rr in (r + 1)..<(g.rows - 1) where (c + rr) % 2 == 0 { area.append((c, rr)) } }
                }
                g.fill(ctx, area, color.opacity(0.22))
                g.fill(ctx, line, color)
            }
            VStack(alignment: .trailing) {
                Text(label(hi))
                Spacer()
                Text(label(lo))
            }
            .font(Theme.vfdFont)
            .foregroundStyle(Theme.textDim)
        }
    }

    var range: (Double, Double) {
        var lo = values.min() ?? 0, hi = values.max() ?? 1
        if let t = threshold { lo = min(lo, t); hi = max(hi, t) }
        if hi - lo < 1e-6 { hi = lo + 1 }
        if logScale { lo = max(lo, 1) }
        return (lo, hi)
    }
    func map(_ v: Double) -> Double { logScale ? log10(max(v, 1)) : v }
    func label(_ v: Double) -> String { abs(v) >= 100 ? String(Int(v.rounded())) : v.formatted(decimals: 1) }
}

/// Horizontal LED bar: dim track, lit "good" zone, bright marker.
struct PixelBar: View {
    /// Marker position 0…1 (nil = no reading).
    var marker: Double?
    /// Highlighted zone 0…1.
    var zone: ClosedRange<Double>? = nil
    /// Fill from the left up to `marker` (progress style).
    var fillToMarker = false
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let g = PixelGrid(size: size)
            let mid = g.rows / 2
            var track: [(Int, Int)] = [], lit: [(Int, Int)] = []
            for c in 0..<g.cols {
                let t = Double(c) / Double(max(g.cols - 1, 1))
                let inZone = zone?.contains(t) ?? false
                let filled = fillToMarker && marker.map { t <= $0 } == true
                for r in (mid - 1)...(mid) {
                    if filled || inZone { lit.append((c, r)) } else if c % 2 == 0 { track.append((c, r)) }
                }
            }
            g.fill(ctx, track, Theme.textDim.opacity(0.35))
            g.fill(ctx, lit, (fillToMarker ? color : Theme.alien).opacity(fillToMarker ? 1 : 0.45))
            if let m = marker, !fillToMarker {
                let c = Int((min(max(m, 0), 1) * Double(g.cols - 1)).rounded())
                var cells: [(Int, Int)] = []
                for dc in -1...1 { for r in 0..<g.rows { cells.append((c + dc, r)) } }
                g.fill(ctx, cells, color)
            }
        }
    }
}

/// Signal strength as pixel columns.
struct PixelSignal: View {
    var level: Int   // 0…4
    var body: some View {
        Canvas { ctx, size in
            let g = PixelGrid(size: size)
            var on: [(Int, Int)] = [], off: [(Int, Int)] = []
            for bar in 0..<4 {
                let h = 2 + bar * 2
                for r in (g.rows - h)..<g.rows {
                    for dc in 0..<2 {
                        if bar < level { on.append((bar * 3 + dc, r)) } else { off.append((bar * 3 + dc, r)) }
                    }
                }
            }
            g.fill(ctx, off, Theme.textDim.opacity(0.35))
            g.fill(ctx, on, Theme.alien)
        }
        .frame(width: Theme.vfdPixel * 12, height: Theme.vfdPixel * 9)
    }
}
