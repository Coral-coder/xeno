import SwiftUI

/// Shows the live value for a role, or lets the tech type one in when no probe is assigned.
struct RoleInput: View {
    @Environment(AppModel.self) private var model
    let role: ProbeRole
    var caption: String? = nil
    var humidity = false
    var size: CGFloat = 24
    var color: Color = Theme.text
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let s = model.settings
        let live = humidity ? model.humidity(role) : model.value(role)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(caption ?? (humidity ? "\(role.title) RH" : role.title)).font(Theme.label).foregroundStyle(Theme.textDim)
                if live != nil { Image(systemName: "dot.radiowaves.right").font(Theme.font(.caption2)).foregroundStyle(Theme.alien) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let live {
                    Text(format(live, s)).font(Theme.reading(size)).foregroundStyle(color).lineLimit(1).xenoScale(0.5)
                } else {
                    TextField("––", text: $text)
                        .keyboardType(.numbersAndPunctuation)
                        .font(Theme.reading(size))
                        .foregroundStyle(Theme.warn)
                        .focused($focused)
                        .onChange(of: text) { _, v in store(v, s) }
                        .frame(minWidth: 50)
                }
                Text(unit(s)).font(Theme.font(.footnote)).foregroundStyle(Theme.textDim)
            }
        }
        .onAppear { text = initialText(s) }
    }

    private func unit(_ s: XenoSettings) -> String {
        if humidity { return "%RH" }
        switch role.kind {
        case .pressure: return s.pressureUnit.rawValue
        case .vacuum: return s.vacuumUnit.rawValue
        case .staticPressure: return s.staticUnit.rawValue
        default: return s.temperatureUnit.rawValue
        }
    }

    private func format(_ v: Double, _ s: XenoSettings) -> String {
        let f = Fmt(s: s)
        if humidity { return v.formatted(decimals: 1) }
        switch role.kind {
        case .pressure: return f.pressure(v)
        case .vacuum: return f.vacuum(v)
        case .staticPressure: return f.stat(v)
        default: return f.temp(v)
        }
    }

    private func initialText(_ s: XenoSettings) -> String {
        let v = humidity ? model.manualRH[role] : model.manual[role]
        guard let v else { return "" }
        if humidity { return v.formatted(decimals: 1) }
        switch role.kind {
        case .pressure: return s.pressureUnit.fromPsig(v).formatted(decimals: s.pressureUnit.decimals)
        case .staticPressure: return s.staticUnit.fromInWC(v).formatted(decimals: 2)
        default: return s.temperatureUnit.fromF(v).formatted(decimals: 1)
        }
    }

    private func store(_ text: String, _ s: XenoSettings) {
        let v = Double(text.replacingOccurrences(of: ",", with: "."))
        if humidity { model.manualRH[role] = v; return }
        guard let v else { model.manual[role] = nil; return }
        switch role.kind {
        case .pressure: model.manual[role] = s.pressureUnit.toPsig(v)
        case .staticPressure: model.manual[role] = s.staticUnit.toInWC(v)
        case .vacuum: model.manual[role] = v
        default: model.manual[role] = s.temperatureUnit.toF(v)
        }
    }
}

/// A computed result with a target and a deviation gauge.
struct TargetGauge: View {
    var title: String
    var value: Double?
    var target: Double?
    var tolerance: Double
    var unit: String
    var display: (Double) -> String

    var body: some View {
        let status = statusColor
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title.uppercased()).font(Theme.label).tracking(1.2).foregroundStyle(Theme.textDim)
                Spacer()
                if let target { Text("target \(display(target))\(unit)").font(Theme.font(.caption2)).foregroundStyle(Theme.textDim) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.map(display) ?? "––").font(Theme.reading(44)).foregroundStyle(status)
                    .glow(color: status.opacity(0.6), radius: 10)
                Text(unit).font(Theme.font(.callout)).foregroundStyle(Theme.textDim)
            }
            if Theme.isVFD {
                let span = max(tolerance * 5, 10)
                PixelBar(marker: (value != nil && target != nil) ? (value! - target!) / span * 0.5 + 0.5 : nil,
                         zone: 0.35...0.65, color: status)
                    .frame(height: Theme.vfdPixel * 5)
            } else {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.text.opacity(0.08))
                    Capsule().fill(Theme.alien.opacity(0.25)).frame(width: w * 0.3).offset(x: w * 0.35)
                    if let value, let target {
                        let span = max(tolerance * 5, 10)
                        let x = min(max((value - target) / span * 0.5 + 0.5, 0.02), 0.98)
                        Circle().fill(status).frame(width: 12, height: 12).glow(color: status, radius: 6)
                            .offset(x: w * x - 6)
                    }
                }
            }
            .frame(height: 12)
            }
        }
    }

    var statusColor: Color {
        guard let value else { return Theme.textDim }
        guard let target else { return Theme.text }
        let d = abs(value - target)
        return d <= tolerance ? Theme.alien : d <= tolerance * 2 ? Theme.warn : Theme.danger
    }
}

struct KeyValueRow: View {
    var key: String
    var value: String
    var unit: String = ""
    var body: some View {
        HStack {
            Text(key).foregroundStyle(Theme.textDim)
            Spacer()
            Text(value).font(Theme.font(.body).monospacedDigit().weight(.semibold))
            if !unit.isEmpty { Text(unit).font(Theme.font(.caption)).foregroundStyle(Theme.textDim) }
        }
        .font(Theme.font(.subheadline))
    }
}

/// Sheet for saving a measurement record to a job.
struct SaveToJobSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let record: JobRecord
    @State private var newCustomer = ""

    var body: some View {
        NavigationStack {
            List {
                Section("New job") {
                    HStack {
                        TextField("Customer name", text: $newCustomer)
                        Button("Create & save") {
                            var job = Job(); job.customer = newCustomer
                            job.equipment.refrigerant = model.settings.refrigerant
                            job.equipment.metering = model.settings.metering
                            let j = model.jobs.create(job)
                            model.jobs.add(record, to: j.id); dismiss()
                        }.disabled(newCustomer.isEmpty)
                    }
                }
                if !model.jobs.jobs.isEmpty {
                    Section("Existing jobs") {
                        ForEach(model.jobs.jobs) { job in
                            Button {
                                model.jobs.add(record, to: job.id); model.jobs.activeJobID = job.id; dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(job.title).foregroundStyle(Theme.text)
                                        Text(job.address.isEmpty ? job.created.formatted(date: .abbreviated, time: .omitted) : job.address)
                                            .font(Theme.font(.caption)).foregroundStyle(Theme.textDim)
                                    }
                                    Spacer()
                                    if job.id == model.jobs.activeJobID { StatusPill(text: "ACTIVE", color: Theme.alien) }
                                }
                            }
                        }
                    }
                }
                Section("Record") {
                    Text(record.title).font(Theme.font(.headline))
                    ForEach(record.values) { KeyValueRow(key: $0.label, value: $0.value) }
                }
            }
            .xenoScreen()
            .navigationTitle("Save to job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
