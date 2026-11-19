import SwiftUI

struct ChargeView: View {
    @Environment(AppModel.self) private var model
    @State private var saving: JobRecord?
    @State private var pickingRefrigerant = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let res = model.chargeResult
                let fmt = model.fmt
                let s = model.settings
                ScrollView {
                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            Button { pickingRefrigerant = true } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "drop.fill")
                                    Text(model.refrigerant.name).font(Theme.font(.headline))
                                    Image(systemName: "chevron.down").font(Theme.font(.caption))
                                }
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(Capsule().fill(Theme.beam.opacity(0.15)))
                                .overlay(Capsule().strokeBorder(Theme.beam.opacity(0.6)))
                                .foregroundStyle(Theme.beam)
                            }
                            Picker("Metering", selection: $model.settings.metering) {
                                Text("TXV").tag(MeteringDevice.txv)
                                Text("Fixed").tag(MeteringDevice.fixed)
                            }
                            .pickerStyle(.segmented)
                        }

                        // Low side
                        XenoCard(glow: Theme.beam) {
                            VStack(alignment: .leading, spacing: 12) {
                                SideHeader(title: "Low side · Vapor", color: Theme.beam, symbol: "snowflake")
                                HStack(alignment: .top) {
                                    RoleInput(role: .suctionPressure, caption: "Suction", color: Theme.beam)
                                    Spacer()
                                    ReadingViewSmall(caption: model.refrigerant.hasGlide ? "Dew sat" : "Sat temp", value: fmt.temp(res.suctionSatF), unit: fmt.tUnit)
                                    Spacer()
                                    RoleInput(role: .suctionLine, caption: "Line temp")
                                }
                                TargetGauge(title: "Superheat", value: res.superheatF.map { s.temperatureUnit.deltaFromF($0) },
                                            target: (s.metering == .fixed ? res.targetSuperheatF : nil).map { s.temperatureUnit.deltaFromF($0) },
                                            tolerance: s.temperatureUnit.deltaFromF(max(s.chargeTolerance, 5)), unit: fmt.dUnit) { $0.formatted(decimals: 1) }
                            }
                        }

                        // High side
                        XenoCard(glow: Theme.warn) {
                            VStack(alignment: .leading, spacing: 12) {
                                SideHeader(title: "High side · Liquid", color: Theme.warn, symbol: "flame")
                                HStack(alignment: .top) {
                                    RoleInput(role: .liquidPressure, caption: "Liquid", color: Theme.warn)
                                    Spacer()
                                    ReadingViewSmall(caption: model.refrigerant.hasGlide ? "Bubble sat" : "Sat temp", value: fmt.temp(res.liquidSatF), unit: fmt.tUnit)
                                    Spacer()
                                    RoleInput(role: .liquidLine, caption: "Line temp")
                                }
                                TargetGauge(title: "Subcooling", value: res.subcoolF.map { s.temperatureUnit.deltaFromF($0) },
                                            target: (s.metering == .txv ? res.targetSubcoolF : nil).map { s.temperatureUnit.deltaFromF($0) },
                                            tolerance: s.temperatureUnit.deltaFromF(s.chargeTolerance), unit: fmt.dUnit) { $0.formatted(decimals: 1) }
                                if s.metering == .txv {
                                    Stepper(value: $model.settings.targetSubcool, in: 2...25, step: 0.5) {
                                        Text("Target subcool (nameplate): \(s.targetSubcool.formatted(decimals: 1))°F").font(Theme.font(.caption)).foregroundStyle(Theme.textDim)
                                    }
                                }
                            }
                        }

                        DiagnosisCard(diagnosis: res.diagnosis)

                        // Air side
                        XenoCard(glow: Theme.nebula) {
                            VStack(alignment: .leading, spacing: 12) {
                                SideHeader(title: "Air side", color: Theme.nebula, symbol: "wind")
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        RoleInput(role: .returnAir, caption: "Return DB", size: 20)
                                        RoleInput(role: .returnAir, caption: "Return RH", humidity: true, size: 20)
                                    }
                                    Spacer()
                                    VStack(alignment: .leading, spacing: 8) {
                                        RoleInput(role: .supplyAir, caption: "Supply DB", size: 20)
                                        RoleInput(role: .supplyAir, caption: "Supply RH", humidity: true, size: 20)
                                    }
                                    Spacer()
                                    RoleInput(role: .outdoorAir, caption: "Outdoor DB", size: 20)
                                }
                                Divider().opacity(0.3)
                                let ret = model.air(.returnAir), sup = model.air(.supplyAir)
                                KeyValueRow(key: "Return wet bulb", value: fmt.temp(ret?.wetBulbF), unit: fmt.tUnit)
                                if let r = model.input(.returnAir), let su = model.input(.supplyAir) {
                                    KeyValueRow(key: "Temperature split (ΔT)", value: fmt.delta(r - su), unit: fmt.dUnit)
                                }
                                if let ret, let rDB = model.input(.returnAir) {
                                    KeyValueRow(key: "Target ΔT", value: fmt.delta(HVACCalc.targetCoolingDeltaT(returnDryBulbF: rDB, returnRH: ret.relativeHumidity)), unit: fmt.dUnit)
                                }
                                if let ret, let sup { KeyValueRow(key: "Enthalpy drop", value: (ret.enthalpy - sup.enthalpy).formatted(decimals: 2), unit: "BTU/lb") }
                                if s.metering == .fixed { KeyValueRow(key: "Target superheat", value: fmt.delta(res.targetSuperheatF), unit: fmt.dUnit) }
                                if let cr = res.compressionRatio { KeyValueRow(key: "Compression ratio", value: cr.formatted(decimals: 2), unit: ": 1") }
                                if let sat = res.suctionSatF, let r = model.input(.returnAir) {
                                    KeyValueRow(key: "Evap approach (RA − sat)", value: fmt.delta(r - sat), unit: fmt.dUnit)
                                }
                                if let sat = res.liquidSatF, let od = model.input(.outdoorAir) {
                                    KeyValueRow(key: "Condenser approach (sat − OD)", value: fmt.delta(sat - od), unit: fmt.dUnit)
                                }
                            }
                        }

                        Button { saving = record(res) } label: { Label("Save charge check to job", systemImage: "square.and.arrow.down") }
                            .buttonStyle(GlowButtonStyle())
                    }
                    .padding(16)
                }
            }
            .xenoScreen()
            .navigationTitle("Charge")
            .sheet(item: $saving) { SaveToJobSheet(record: $0) }
            .sheet(isPresented: $pickingRefrigerant) {
                RefrigerantPicker(selection: $model.settings.refrigerant)
            }
        }
    }

    func record(_ res: ChargeResult) -> JobRecord {
        let f = model.fmt, s = model.settings
        var v: [RecordValue] = [
            .init(label: "Refrigerant", value: model.refrigerant.name),
            .init(label: "Metering", value: s.metering.rawValue),
            .init(label: "Suction pressure", value: "\(f.pressure(model.input(.suctionPressure))) \(f.pUnit)"),
            .init(label: "Suction sat (dew)", value: "\(f.temp(res.suctionSatF)) \(f.tUnit)"),
            .init(label: "Suction line", value: "\(f.temp(model.input(.suctionLine))) \(f.tUnit)"),
            .init(label: "Superheat", value: "\(f.delta(res.superheatF)) \(f.dUnit)"),
            .init(label: "Liquid pressure", value: "\(f.pressure(model.input(.liquidPressure))) \(f.pUnit)"),
            .init(label: "Liquid sat (bubble)", value: "\(f.temp(res.liquidSatF)) \(f.tUnit)"),
            .init(label: "Liquid line", value: "\(f.temp(model.input(.liquidLine))) \(f.tUnit)"),
            .init(label: "Subcooling", value: "\(f.delta(res.subcoolF)) \(f.dUnit)"),
        ]
        if let t = res.targetSuperheatF { v.append(.init(label: "Target superheat", value: "\(f.delta(t)) \(f.dUnit)")) }
        if s.metering == .txv { v.append(.init(label: "Target subcool", value: "\(f.delta(s.targetSubcool)) \(f.dUnit)")) }
        if let r = model.input(.returnAir) { v.append(.init(label: "Return air", value: "\(f.temp(r)) \(f.tUnit)")) }
        if let r = model.input(.supplyAir) { v.append(.init(label: "Supply air", value: "\(f.temp(r)) \(f.tUnit)")) }
        if let r = model.input(.outdoorAir) { v.append(.init(label: "Outdoor air", value: "\(f.temp(r)) \(f.tUnit)")) }
        return JobRecord(title: "Charge check", values: v, verdict: res.diagnosis.rawValue, verdictGood: res.diagnosis.isGood)
    }
}

struct SideHeader: View {
    var title: String
    var color: Color
    var symbol: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(title.uppercased()).tracking(1.3)
        }
        .font(Theme.label)
        .foregroundStyle(color)
    }
}

struct ReadingViewSmall: View {
    var caption: String
    var value: String
    var unit: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption).font(Theme.label).foregroundStyle(Theme.textDim)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(Theme.reading(24)).foregroundStyle(Theme.text.opacity(0.85))
                Text(unit).font(Theme.font(.footnote)).foregroundStyle(Theme.textDim)
            }
        }
    }
}

struct DiagnosisCard: View {
    var diagnosis: ChargeDiagnosis
    var body: some View {
        let color: Color = diagnosis == .needsData ? Theme.textDim : diagnosis.isGood ? Theme.alien : Theme.danger
        XenoCard(glow: color) {
            HStack(spacing: 12) {
                Image(systemName: diagnosis == .needsData ? "antenna.radiowaves.left.and.right" : diagnosis.isGood ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(Theme.font(.title2)).foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(diagnosis.rawValue).font(Theme.font(.headline)).foregroundStyle(color)
                    Text(diagnosis.detail).font(Theme.font(.caption)).foregroundStyle(Theme.textDim)
                }
            }
        }
    }
}

struct RefrigerantPicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(Refrigerants.all.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.use.localizedCaseInsensitiveContains(search) }) { r in
                    Button {
                        selection = r.name; dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(r.name).font(Theme.font(.headline)).foregroundStyle(Theme.text)
                                    StatusPill(text: r.safetyClass, color: r.safetyClass.hasPrefix("A1") ? Theme.alien : r.safetyClass.contains("2L") ? Theme.warn : Theme.danger)
                                    if r.hasGlide { StatusPill(text: "GLIDE", color: Theme.nebula) }
                                }
                                Text(r.use).font(Theme.font(.caption)).foregroundStyle(Theme.textDim)
                            }
                            Spacer()
                            if r.name == selection { Image(systemName: "checkmark").foregroundStyle(Theme.alien) }
                        }
                    }
                }
            }
            .searchable(text: $search)
            .xenoScreen()
            .navigationTitle("Refrigerant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
