import Charts
import SwiftUI

struct ProbeDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let probe: Probe
    @State private var name = ""
    @State private var selected: String?
    @State private var window: Double = 600

    var body: some View {
        let fmt = model.fmt
        ScrollView {
            VStack(spacing: 14) {
                XenoCard {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Nickname (e.g. Suction)", text: $name)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .onSubmit { model.probes.rename(probe, to: name) }
                        Text("\(probe.vendor) \(probe.model) · ID \(probe.serial)\(probe.firmware.map { " · fw \($0)" } ?? "")")
                            .font(.caption).foregroundStyle(Theme.textDim)
                        HStack {
                            SignalBars(rssi: probe.rssi, stale: false)
                            Text("\(probe.rssi) dBm").font(.caption).foregroundStyle(Theme.textDim)
                            if let b = probe.battery { BatteryIcon(level: b) }
                            Spacer()
                            Text("\(probe.packets) packets").font(.caption2).foregroundStyle(Theme.textDim)
                        }
                    }
                }

                SectionHeader(title: "Live readings", symbol: "waveform.path.ecg")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(probe.readings) { r in
                        let (v, u) = fmt.reading(r)
                        Button { selected = r.id } label: {
                            XenoCard(glow: selected == r.id ? Theme.beam : Theme.alien) {
                                ReadingView(caption: r.label, value: v, unit: u, size: 26)
                            }
                        }.buttonStyle(.plain)
                    }
                }

                if let id = selected ?? probe.readings.first?.id, let series = probe.history[id], let r = probe.readings.first(where: { $0.id == id }) {
                    SectionHeader(title: "Graph · \(r.label)", symbol: "chart.xyaxis.line")
                    XenoCard(glow: Theme.beam) {
                        VStack(alignment: .leading) {
                            Picker("Window", selection: $window) {
                                Text("1 min").tag(60.0); Text("5 min").tag(300.0); Text("10 min").tag(600.0); Text("1 hr").tag(3600.0)
                            }.pickerStyle(.segmented)
                            SeriesChart(samples: series.filter { $0.t > Date().addingTimeInterval(-window) }, kind: r.kind, color: Theme.beam)
                                .frame(height: 180)
                        }
                    }
                }

                SectionHeader(title: "Assign to system position", symbol: "point.3.connected.trianglepath.dotted")
                XenoCard {
                    VStack(spacing: 0) {
                        ForEach(ProbeRole.allCases.filter { role in probe.readings.contains { compatible($0.kind, role) } }) { role in
                            let assigned = model.probes.assignments[role]?.probeKey == probe.key
                            Button {
                                if assigned { model.probes.assign(role, to: nil) }
                                else { model.probes.assign(role, to: probe, label: probe.readings.first { compatible($0.kind, role) }?.label) }
                            } label: {
                                HStack {
                                    Text(role.title)
                                    Spacer()
                                    if let ref = model.probes.assignments[role], assigned {
                                        Text(ref.label).font(.caption).foregroundStyle(Theme.textDim)
                                    }
                                    Image(systemName: assigned ? "checkmark.circle.fill" : "circle").foregroundStyle(assigned ? Theme.alien : Theme.textDim)
                                }
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().opacity(0.3)
                        }
                    }
                }

                SectionHeader(title: "Raw broadcast", symbol: "chevron.left.forwardslash.chevron.right")
                XenoCard(glow: Theme.nebula) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(probe.raw.map { String(format: "%02X", $0) }.joined(separator: " "))
                            .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        if let layout = model.lab.layout(for: probe.typeCode) {
                            Text(layout.provenance).font(.caption2).foregroundStyle(Theme.textDim)
                        }
                        NavigationLink("Open in Probe Lab") { LayoutEditorView(typeCode: probe.typeCode, sample: probe.raw) }
                            .font(.caption.weight(.semibold))
                    }
                }

                Button("Forget probe", role: .destructive) { model.probes.forget(probe); dismiss() }
                    .buttonStyle(GlowButtonStyle(color: Theme.danger))
            }
            .padding(16)
        }
        .xenoScreen()
        .navigationTitle(probe.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { name = probe.nickname }
        .onDisappear { if name != probe.nickname { model.probes.rename(probe, to: name) } }
    }

    func compatible(_ kind: SensorKind, _ role: ProbeRole) -> Bool {
        kind == role.kind
    }
}

struct SeriesChart: View {
    @Environment(AppModel.self) private var model
    var samples: [TimedSample]
    var kind: SensorKind
    var color: Color
    var threshold: Double? = nil
    var logScale = false

    var body: some View {
        let s = model.settings
        Chart {
            ForEach(Array(samples.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("Time", p.t), y: .value("Value", convert(p.value, s)))
                    .foregroundStyle(color)
                    .interpolationMethod(.monotone)
                AreaMark(x: .value("Time", p.t), y: .value("Value", convert(p.value, s)))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
            }
            if let threshold {
                RuleMark(y: .value("Limit", convert(threshold, s)))
                    .foregroundStyle(Theme.warn)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false), type: logScale ? ScaleType.log : ScaleType.linear)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisGridLine().foregroundStyle(.white.opacity(0.08)); AxisValueLabel(format: .dateTime.hour().minute()) } }
        .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(.white.opacity(0.08)); AxisValueLabel() } }
    }

    func convert(_ v: Double, _ s: XenoSettings) -> Double {
        switch kind {
        case .temperature, .wetBulb, .dewPoint: return s.temperatureUnit.fromF(v)
        case .pressure: return s.pressureUnit.fromPsig(v)
        case .vacuum: return s.vacuumUnit.fromMicrons(v)
        case .staticPressure: return s.staticUnit.fromInWC(v)
        default: return v
        }
    }
}
