import SwiftUI

struct PTChartView: View {
    @Environment(AppModel.self) private var model
    @State private var refrigerant: String = ""
    @State private var picking = false
    @State private var sliderF: Double = 40
    @State private var pressureText = ""

    var body: some View {
        let r = Refrigerants.named(refrigerant) ?? model.refrigerant
        let s = model.settings, fmt = model.fmt
        let atm = s.atmPsia
        ScrollView {
            VStack(spacing: 14) {
                Button { picking = true } label: {
                    HStack {
                        Text(r.name).font(.system(.title2, design: .rounded).weight(.bold))
                        StatusPill(text: r.safetyClass, color: Theme.beam)
                        if r.hasGlide { StatusPill(text: "GLIDE", color: Theme.nebula) }
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .foregroundStyle(.white)
                }
                XenoCard(glow: Theme.beam) {
                    VStack(spacing: 12) {
                        HStack {
                            ReadingView(caption: "Saturation temp", value: fmt.temp(sliderF), unit: fmt.tUnit, color: Theme.alien, size: 36)
                            Spacer()
                        }
                        HStack {
                            ReadingView(caption: r.hasGlide ? "Dew (vapor)" : "Pressure", value: fmt.pressure(r.satPsig(tempF: sliderF, side: .dew, atmPsia: atm)), unit: fmt.pUnit, color: Theme.beam)
                            Spacer()
                            if r.hasGlide {
                                ReadingView(caption: "Bubble (liquid)", value: fmt.pressure(r.satPsig(tempF: sliderF, side: .bubble, atmPsia: atm)), unit: fmt.pUnit, color: Theme.warn)
                            }
                        }
                        Slider(value: $sliderF, in: max(-40, r.minF)...min(150, r.maxF), step: 1)
                        HStack {
                            Text("Pressure → temp").foregroundStyle(Theme.textDim)
                            TextField(fmt.pUnit, text: $pressureText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            Text(fmt.pUnit).font(.caption).foregroundStyle(Theme.textDim)
                        }
                        if let p = Double(pressureText).map({ s.pressureUnit.toPsig($0) }) {
                            KeyValueRow(key: "Dew point", value: fmt.temp(r.satTempF(psig: p, side: .dew, atmPsia: atm)), unit: fmt.tUnit)
                            if r.hasGlide { KeyValueRow(key: "Bubble point", value: fmt.temp(r.satTempF(psig: p, side: .bubble, atmPsia: atm)), unit: fmt.tUnit) }
                        }
                    }
                }
                XenoCard {
                    VStack(spacing: 0) {
                        HStack {
                            Text(fmt.tUnit).frame(width: 60, alignment: .leading)
                            Spacer()
                            Text(r.hasGlide ? "Dew" : fmt.pUnit)
                            if r.hasGlide { Text("Bubble").frame(width: 80, alignment: .trailing) }
                        }
                        .font(Theme.label).foregroundStyle(Theme.alien).padding(.bottom, 6)
                        ForEach(Array(stride(from: Int(max(-40, r.minF.rounded(.up)) / 5) * 5, through: Int(min(150, r.maxF)), by: 5)), id: \.self) { t in
                            HStack {
                                Text(fmt.temp(Double(t))).frame(width: 60, alignment: .leading)
                                Spacer()
                                Text(fmt.pressure(r.satPsig(tempF: Double(t), side: .dew, atmPsia: atm)))
                                if r.hasGlide { Text(fmt.pressure(r.satPsig(tempF: Double(t), side: .bubble, atmPsia: atm))).frame(width: 80, alignment: .trailing).foregroundStyle(Theme.warn) }
                            }
                            .font(.system(.subheadline, design: .rounded).monospacedDigit())
                            .padding(.vertical, 5)
                            .background(t == Int(sliderF.rounded()) ? Theme.alien.opacity(0.15) : .clear)
                            Divider().opacity(0.15)
                        }
                    }
                }
                Text("Saturation data computed with CoolProp (NIST-grade equations of state). Oil: \(r.oil). \(r.use).")
                    .font(.caption2).foregroundStyle(Theme.textDim)
            }
            .padding(16)
        }
        .xenoScreen()
        .navigationTitle("P/T chart")
        .onAppear { if refrigerant.isEmpty { refrigerant = model.refrigerant.name } }
        .sheet(isPresented: $picking) { RefrigerantPicker(selection: $refrigerant) }
    }
}

struct LoggerView: View {
    @Environment(AppModel.self) private var model
    @State private var window: Double = 600
    @State private var exportURL: URL?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("Window", selection: $window) {
                    Text("5 min").tag(300.0); Text("15 min").tag(900.0); Text("1 hr").tag(3600.0); Text("2 hr").tag(7200.0)
                }.pickerStyle(.segmented)
                if model.probes.probes.isEmpty { Text("No probes yet.").foregroundStyle(Theme.textDim) }
                ForEach(model.probes.probes) { p in
                    ForEach(p.readings.filter { $0.kind != .wetBulb && $0.kind != .dewPoint }) { r in
                        XenoCard(glow: Theme.beam) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("\(p.displayName) · \(r.label)").font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    Spacer()
                                    let (v, u) = model.fmt.reading(r)
                                    Text("\(v) \(u)").font(.system(.subheadline, design: .rounded).monospacedDigit()).foregroundStyle(Theme.alien)
                                }
                                SeriesChart(samples: (p.history[r.id] ?? []).filter { $0.t > Date().addingTimeInterval(-window) }, kind: r.kind, color: Theme.beam)
                                    .frame(height: 110)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .xenoScreen()
        .navigationTitle("Data logger")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let exportURL {
                    ShareLink(item: exportURL) { Image(systemName: "square.and.arrow.up") }
                } else {
                    Button { exportURL = exportCSV() } label: { Image(systemName: "tablecells.badge.ellipsis") }
                }
            }
        }
    }

    func exportCSV() -> URL? {
        var csv = "time,probe,channel,value,unit\n"
        let f = ISO8601DateFormatter()
        for p in model.probes.probes {
            for r in p.readings {
                for s in p.history[r.id] ?? [] {
                    csv += "\(f.string(from: s.t)),\(p.displayName),\(r.label),\(s.value),\(r.kind.canonicalUnit)\n"
                }
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Xeno-log-\(Int(Date().timeIntervalSince1970)).csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
