import Foundation

/// Routes inside the VFD interface.
enum VFDRoute: Hashable {
    case refrigerants, probe(String), vacuum, pt, targetSH, staticP, airflow
}

/// Screens not yet drawn on the pixel matrix open in a sheet with the regular UI.
enum VFDFallback: String, Identifiable {
    case pressure, psychro, furnace, weighin, electrical, convert, duct, leak, logger, explorer, debug, lab, settingsFull, job
    var id: String { rawValue }
}

struct VFDActions {
    var push: (VFDRoute) -> Void
    var pop: () -> Void
    var fallback: (VFDFallback) -> Void
    var openJob: (UUID) -> Void
    var ask: (String, String, @escaping (Double?) -> Void) -> Void
    var setPT: (Double) -> Void
    var setCFM: (Double) -> Void
    var startDecay: () -> Void
    var stopDecay: () -> Void
    var recordDecay: (TimedSample) -> Void

    static let none = VFDActions(push: { _ in }, pop: {}, fallback: { _ in }, openJob: { _ in }, ask: { _, _, _ in },
                                 setPT: { _ in }, setCFM: { _ in }, startDecay: {}, stopDecay: {}, recordDecay: { _ in })
}

/// Everything that varies between frames besides the app model.
struct VFDState {
    var stack: [VFDRoute] = []
    var scroll = 0
    var ptTempF: Double = 40
    var cfm: Double = 1200
    var decayStart: Date?
    var decay: [TimedSample] = []
}

enum VFDFrame {
    /// Composes one full screen: header, scrolling content, tab bar. `topInset`/`bottomInset`
    /// are the safe-area insets in cells.
    static func compose(model: AppModel, state: VFDState, cols: Int, rows: Int, topInset: Int, bottomInset: Int,
                        now: Date, actions: VFDActions, select: @escaping (AppTab) -> Void) -> VFDBuffer {
        let b = VFDBuffer(cols: cols, rows: rows)
        let topRow = topInset + 4
        let tabTop = rows - bottomInset - 22
        let contentTop = topRow + 22
        var p = VFDPainter(b: b, model: model, now: now, actions: actions)

        let title = self.title(model: model, stack: state.stack)
        if state.stack.isEmpty {
            b.text(p.left, topRow, title, .mid, .white)
        } else {
            b.text(p.left, topRow + 3, "<", .mid, .amber)
            b.hit(0, topRow - 2, 30, topRow + 20) { actions.pop() }
            b.text(p.left + 18, topRow, title, maxCols: p.right - p.left - 18, .mid, .white)
        }

        b.clipTop = contentTop
        b.clipBottom = tabTop - 2
        b.scroll = state.scroll
        b.resetContentBottom()
        p.y = contentTop
        if let route = state.stack.last {
            p.route(route, ptTempF: state.ptTempF, cfm: state.cfm, decayStart: state.decayStart, decay: state.decay)
        } else {
            p.tab(model.selectedTab)
        }
        b.maxScroll = max(0, b.contentBottom - (tabTop - 4))

        b.clipTop = 0; b.clipBottom = rows - 1; b.scroll = 0
        b.hline(0, cols - 1, tabTop, .dim)
        let tabs: [(AppTab, String)] = [(.probes, "PROBES"), (.charge, "CHARGE"), (.tools, "TOOLS"), (.jobs, "JOBS"), (.settings, "SETUP")]
        let w = cols / tabs.count
        for (i, t) in tabs.enumerated() {
            let c0 = i * w, label = t.1
            let tc = c0 + (w - b.width(label)) / 2
            if t.0 == model.selectedTab && state.stack.isEmpty {
                b.fill(c0 + 2, tabTop + 5, c0 + w - 3, tabTop + 17, .amber)
                b.text(tc, tabTop + 8, label, .small, .off)
            } else {
                b.text(tc, tabTop + 8, label, .small, t.0 == model.selectedTab ? .amber : .white)
            }
            let tab = t.0
            b.hit(c0, tabTop + 1, c0 + w - 1, rows - 1) { select(tab) }
        }
        return b
    }

    static func title(model: AppModel, stack: [VFDRoute]) -> String {
        switch stack.last {
        case .refrigerants: return "REFRIGERANT"
        case .probe(let k): return model.probes.probe(k)?.displayName.uppercased() ?? "PROBE"
        case .vacuum: return "EVACUATION"
        case .pt: return "P/T CHART"
        case .targetSH: return "TARGET SH"
        case .staticP: return "STATIC"
        case .airflow: return "AIRFLOW"
        case nil:
            switch model.selectedTab {
            case .probes: return "PROBES"
            case .charge: return "CHARGE"
            case .tools: return "TOOLS"
            case .jobs: return "JOBS"
            case .settings: return "SETUP"
            }
        }
    }
}
