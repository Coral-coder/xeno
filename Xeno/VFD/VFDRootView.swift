import SwiftUI

struct VFDPrompt: Identifiable {
    let id = UUID()
    var title: String
    var onSubmit: (Double?) -> Void
}

/// The whole Amber VFD interface: one full-screen pixel matrix painted from a `VFDBuffer`.
struct VFDRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    @State private var state = VFDState()
    @State private var dragStart: Int?
    @State private var fallback: VFDFallback?
    @State private var fallbackJob: UUID?
    @State private var prompt: VFDPrompt?
    @State private var promptText = ""

    /// Device pixels per cell: 5 on 3x screens, 4 on 2x.
    var pitch: CGFloat { (displayScale >= 3 ? 5 : 4) / displayScale }

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let size = CGSize(width: geo.size.width + insets.leading + insets.trailing, height: geo.size.height + insets.top + insets.bottom)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let buf = VFDFrame.compose(model: model, state: state,
                                           cols: Int(size.width / pitch), rows: Int(size.height / pitch),
                                           topInset: Int((insets.top / pitch).rounded(.up)),
                                           bottomInset: Int((insets.bottom / pitch).rounded(.up)),
                                           now: ctx.date, actions: actions, select: select)
                ZStack(alignment: .topLeading) {
                    Color.black
                    Image(uiImage: VFDRootView.tile(pitch: pitch, scale: displayScale))
                        .resizable(resizingMode: .tile)
                    Canvas { g, _ in paint(buf, into: g) }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            guard abs(v.translation.height) > 6 else { return }
                            if dragStart == nil { dragStart = state.scroll }
                            state.scroll = min(buf.maxScroll, max(0, (dragStart ?? 0) - Int(v.translation.height / pitch)))
                        }
                        .onEnded { v in
                            if dragStart == nil { _ = buf.tap(col: Int(v.location.x / pitch), row: Int(v.location.y / pitch)) }
                            dragStart = nil
                        }
                )
                .onChange(of: ctx.date) { _, now in
                    if state.decayStart != nil, let m = model.input(.vacuum) { state.decay.append(TimedSample(t: now, value: m)) }
                }
            }
        }
        .ignoresSafeArea()
        .sheet(item: $fallback) { f in
            NavigationStack {
                fallbackView(f)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { fallback = nil } } }
            }
        }
        .alert(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })) {
            TextField("Value", text: $promptText).keyboardType(.numbersAndPunctuation)
            Button("OK") { prompt?.onSubmit(Double(promptText.replacingOccurrences(of: ",", with: "."))); prompt = nil }
            Button("Clear", role: .destructive) { prompt?.onSubmit(nil); prompt = nil }
            Button("Cancel", role: .cancel) { prompt = nil }
        }
    }

    private var actions: VFDActions {
        VFDActions(
            push: { r in state.stack.append(r); state.scroll = 0 },
            pop: { if !state.stack.isEmpty { state.stack.removeLast(); state.scroll = 0 } },
            fallback: { f in fallback = f },
            openJob: { id in fallbackJob = id; fallback = .job },
            ask: { title, initial, done in promptText = initial; prompt = VFDPrompt(title: title, onSubmit: done) },
            setPT: { state.ptTempF = min(150, max(-40, $0)) },
            setCFM: { state.cfm = min(5000, max(100, $0)) },
            startDecay: { state.decayStart = .now; state.decay = [] },
            stopDecay: { state.decayStart = nil },
            recordDecay: { s in state.decay.append(s) }
        )
    }

    private func select(_ t: AppTab) { model.selectedTab = t; state.stack = []; state.scroll = 0 }

    private func paint(_ b: VFDBuffer, into g: GraphicsContext) {
        let lit = pitch - 1 / displayScale
        var paths: [UInt8: Path] = [:]
        for r in 0..<b.rows {
            for c in 0..<b.cols {
                let v = b.cells[r * b.cols + c]
                guard v != 0 else { continue }
                paths[v, default: Path()].addRect(CGRect(x: CGFloat(c) * pitch, y: CGFloat(r) * pitch, width: lit, height: lit))
            }
        }
        for (v, path) in paths { g.fill(path, with: .color(VFDColor(rawValue: v)?.color ?? .clear)) }
    }

    private static var tileCache: [String: UIImage] = [:]
    static func tile(pitch: CGFloat, scale: CGFloat) -> UIImage {
        let key = "\(pitch)-\(scale)"
        if let t = tileCache[key] { return t }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let img = UIGraphicsImageRenderer(size: CGSize(width: pitch, height: pitch), format: format).image { ctx in
            UIColor.black.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: pitch, height: pitch))
            UIColor(white: 9 / 255, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: pitch - 1 / scale, height: pitch - 1 / scale))
        }
        tileCache[key] = img
        return img
    }

    @ViewBuilder
    private func fallbackView(_ f: VFDFallback) -> some View {
        switch f {
        case .pressure: PressureTestView()
        case .psychro: PsychroView()
        case .furnace: FurnaceView()
        case .weighin: WeighInView()
        case .electrical: ElectricalView()
        case .convert: ConverterView()
        case .duct: DuctAirflowView()
        case .leak: LeakRateView()
        case .logger: LoggerView()
        case .explorer: ExplorerView()
        case .debug: DebugCaptureView()
        case .lab: ProbeLabView()
        case .settingsFull: SettingsView()
        case .job:
            if let id = fallbackJob { JobDetailView(jobID: id) } else { JobsView() }
        }
    }
}

extension VFDColor {
    var color: Color {
        switch self {
        case .off: return .clear
        case .amber: return Color(red: 1.0, green: 0.69, blue: 0.08)
        case .white: return Color(red: 1.0, green: 0.91, blue: 0.77)
        case .dim: return Color(red: 0.59, green: 0.39, blue: 0.16)
        case .red: return Color(red: 1.0, green: 0.31, blue: 0.16)
        case .green: return Color(red: 0.75, green: 1.0, blue: 0.45)
        }
    }
}
