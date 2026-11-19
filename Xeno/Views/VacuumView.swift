import SwiftUI

struct VacuumView: View {
    @Environment(AppModel.self) private var model
    @State private var decayStart: Date?
    @State private var decaySamples: [TimedSample] = []
    @State private var saving: JobRecord?
    @State private var reachedTarget = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let s = model.settings, fmt = model.fmt
            let microns = model.input(.vacuum)
            let history = model.probes.history(.vacuum).filter { $0.t > ctx.date.addingTimeInterval(-1800) }
            ScrollView {
                VStack(spacing: 14) {
                    XenoCard(glow: color(microns)) {
                        VStack(spacing: 6) {
                            Text("VACUUM").font(Theme.label).tracking(2).foregroundStyle(Theme.textDim)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(fmt.vacuum(microns)).font(Theme.reading(72)).foregroundStyle(color(microns))
                                    .shadow(color: color(microns).opacity(0.7), radius: 16)
                                Text(s.vacuumUnit.rawValue).font(.system(.title3, design: .rounded)).foregroundStyle(Theme.textDim)
                            }
                            MicronScale(microns: microns, target: s.vacuumTarget)
                                .frame(height: 26)
                            HStack {
                                Text("Target \(fmt.vacuum(s.vacuumTarget)) \(s.vacuumUnit.rawValue)")
                                Spacer()
                                Text("Rate \(VacuumAnalysis.rate(Array(history.suffix(60))).formatted(decimals: 0)) µ/min")
                            }
                            .font(.caption).foregroundStyle(Theme.textDim)
                            if model.value(.vacuum) == nil {
                                Text("Assign a vacuum gauge in Probes, or type a reading.").font(.caption).foregroundStyle(Theme.warn)
                                RoleInput(role: .vacuum, caption: "Manual reading")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    SectionHeader(title: "Pulldown", symbol: "chart.xyaxis.line")
                    XenoCard(glow: Theme.warn) {
                        SeriesChart(samples: history, kind: .vacuum, color: Theme.warn, threshold: s.vacuumTarget, logScale: true)
                            .frame(height: 200)
                    }

                    SectionHeader(title: "Decay test", symbol: "timer")
                    XenoCard(glow: Theme.beam) {
                        VStack(alignment: .leading, spacing: 10) {
                            if let start = decayStart {
                                let elapsed = ctx.date.timeIntervalSince(start)
                                let verdict = VacuumAnalysis.verdict(samples: decaySamples, limit: s.vacuumDecayLimit, holdSeconds: s.vacuumHoldMinutes * 60)
                                HStack {
                                    ReadingView(caption: "Elapsed", value: Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond)), unit: "")
                                    Spacer()
                                    ReadingView(caption: "Rise", value: ((decaySamples.last?.value ?? 0) - (decaySamples.first?.value ?? 0)).formatted(decimals: 0), unit: "µ")
                                }
                                Text(verdict.rawValue).font(.system(.headline, design: .rounded))
                                    .foregroundStyle(verdict == .pass ? Theme.alien : verdict == .running ? Theme.beam : Theme.danger)
                                SeriesChart(samples: decaySamples, kind: .vacuum, color: Theme.beam, threshold: s.vacuumDecayLimit).frame(height: 140)
                                HStack {
                                    Button("Stop") { decayStart = nil }.buttonStyle(GlowButtonStyle(color: Theme.danger))
                                    Button("Save") { saving = record(verdict) }.buttonStyle(GlowButtonStyle())
                                }
                            } else {
                                Text("Isolate the pump with the core tool valves, then start. Passes if the system holds under \(fmt.vacuum(s.vacuumDecayLimit)) \(s.vacuumUnit.rawValue) for \(Int(s.vacuumHoldMinutes)) minutes.")
                                    .font(.caption).foregroundStyle(Theme.textDim)
                                Button { decayStart = .now; decaySamples = [] } label: { Label("Start decay test", systemImage: "play.fill") }
                                    .buttonStyle(GlowButtonStyle(color: Theme.beam))
                                    .disabled(microns == nil)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .onChange(of: ctx.date) { _, now in
                if decayStart != nil, let m = model.input(.vacuum) { decaySamples.append(TimedSample(t: now, value: m)) }
                if let m = model.input(.vacuum) {
                    if m <= model.settings.vacuumTarget && !reachedTarget { reachedTarget = true; Alerts.fire() }
                    if m > model.settings.vacuumTarget * 1.5 { reachedTarget = false }
                }
            }
        }
        .xenoScreen()
        .navigationTitle("Evacuation")
        .sheet(item: $saving) { SaveToJobSheet(record: $0) }
    }

    func color(_ m: Double?) -> Color {
        guard let m else { return Theme.textDim }
        return m <= model.settings.vacuumTarget ? Theme.alien : m <= 1500 ? Theme.warn : Theme.danger
    }

    func record(_ v: VacuumAnalysis.Verdict) -> JobRecord {
        let f = model.fmt, u = model.settings.vacuumUnit.rawValue
        return JobRecord(title: "Evacuation decay test", values: [
            .init(label: "Start", value: "\(f.vacuum(decaySamples.first?.value)) \(u)"),
            .init(label: "End", value: "\(f.vacuum(decaySamples.last?.value)) \(u)"),
            .init(label: "Duration", value: Duration.seconds((decaySamples.last?.t ?? .now).timeIntervalSince(decaySamples.first?.t ?? .now)).formatted(.time(pattern: .minuteSecond))),
            .init(label: "Limit", value: "\(f.vacuum(model.settings.vacuumDecayLimit)) \(u)"),
        ], verdict: v.rawValue, verdictGood: v == .pass, series: decaySamples, seriesLabel: "microns")
    }
}

/// Log-scale bar from 50 to 25,000 microns.
struct MicronScale: View {
    var microns: Double?
    var target: Double
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let x: (Double) -> CGFloat = { m in CGFloat((log10(max(50, min(25000, m))) - log10(50)) / (log10(25000) - log10(50))) * w }
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: [Theme.alien, Theme.warn, Theme.danger], startPoint: .leading, endPoint: .trailing)).opacity(0.35).frame(height: 8)
                Rectangle().fill(.white.opacity(0.7)).frame(width: 1.5, height: 16).offset(x: x(target))
                if let microns {
                    Circle().fill(.white).frame(width: 14, height: 14).shadow(color: Theme.alien, radius: 6).offset(x: x(microns) - 7)
                }
                ForEach([100.0, 500, 1000, 5000, 20000], id: \.self) { m in
                    Text(m >= 1000 ? "\(Int(m / 1000))k" : "\(Int(m))").font(.system(size: 9, design: .rounded)).foregroundStyle(Theme.textDim)
                        .offset(x: x(m) - 8, y: 14)
                }
            }
        }
    }
}
