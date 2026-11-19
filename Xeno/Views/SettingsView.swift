import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image("AppIconImage").resizable().frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading) {
                            Text("Xeno").font(Theme.font(.title2, weight: .bold))
                            Text("Wireless HVAC probes. No subscription, ever.").font(Theme.font(.caption)).foregroundStyle(Theme.textDim)
                            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))")
                                .font(Theme.font(.caption2)).foregroundStyle(Theme.textDim)
                        }
                    }
                }
                Section("Appearance") {
                    ForEach(ThemeKind.allCases) { k in
                        Button { model.settings.theme = k } label: {
                            HStack(spacing: 12) {
                                ThemeSwatch(kind: k)
                                VStack(alignment: .leading) {
                                    Text(k.title).font(Theme.font(.headline))
                                    Text(k.subtitle).font(Theme.font(.caption)).foregroundStyle(Theme.textDim)
                                }
                                Spacer()
                                if model.settings.theme == k { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.alien) }
                            }
                        }
                    }
                }
                Section("Units") {
                    Picker("Temperature", selection: $model.settings.temperatureUnit) { ForEach(TemperatureUnit.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("Pressure", selection: $model.settings.pressureUnit) { ForEach(PressureUnit.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("Vacuum", selection: $model.settings.vacuumUnit) { ForEach(VacuumUnit.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("Static pressure", selection: $model.settings.staticUnit) { ForEach(StaticPressureUnit.allCases) { Text($0.rawValue).tag($0) } }
                }
                Section {
                    HStack {
                        Text("Altitude")
                        TextField("0", value: $model.settings.altitudeFt, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        Text("ft").foregroundStyle(Theme.textDim)
                    }
                    Text("Barometric pressure: \(model.settings.atmPsia.formatted(decimals: 2)) psia").font(Theme.font(.caption)).foregroundStyle(Theme.textDim)
                } header: { Text("Location") } footer: { Text("Gauge pressures are converted to absolute with this barometric pressure before saturation lookups, and air calculations are density-corrected.") }
                Section("Charging") {
                    Picker("Default refrigerant", selection: $model.settings.refrigerant) { ForEach(Refrigerants.all) { Text($0.name).tag($0.name) } }
                    Stepper("Tolerance ±\(model.settings.chargeTolerance.formatted(decimals: 0))°F", value: $model.settings.chargeTolerance, in: 1...8)
                }
                Section("Evacuation") {
                    Stepper("Target \(Int(model.settings.vacuumTarget)) microns", value: $model.settings.vacuumTarget, in: 100...1000, step: 50)
                    Stepper("Decay limit \(Int(model.settings.vacuumDecayLimit)) microns", value: $model.settings.vacuumDecayLimit, in: 300...2500, step: 100)
                    Stepper("Hold \(Int(model.settings.vacuumHoldMinutes)) min", value: $model.settings.vacuumHoldMinutes, in: 1...60)
                }
                Section("Probes") {
                    Toggle("Auto-assign new probes", isOn: $model.settings.autoAssign)
                    Toggle("Keep screen on", isOn: $model.settings.keepAwake)
                    Stepper("Offline after \(Int(model.settings.staleSeconds)) s", value: $model.settings.staleSeconds, in: 5...120, step: 5)
                    Toggle("Demo probes", isOn: Binding(get: { model.settings.demoMode }, set: { model.setDemo($0) }))
                    NavigationLink { DebugCaptureView() } label: { Label("Debug capture → zip & email", systemImage: "ladybug") }
                    NavigationLink("Probe Lab") { ProbeLabView() }
                    NavigationLink("BLE explorer") { ExplorerView() }
                    Button("Clear probe assignments", role: .destructive) { model.probes.assignments = [:] }
                }
                Section("Report header") {
                    TextField("Company", text: $model.settings.companyName)
                    TextField("Technician", text: $model.settings.technician)
                    TextField("License #", text: $model.settings.license)
                    TextField("Phone", text: $model.settings.companyPhone)
                }
                Section {
                    Text("Supported now: Fieldpiece Job Link JL3 probes (JL3PC pipe clamp, JL3PR pressure, JL3RH psychrometer), SMAN SM480V manifold, JL3KM manometer, SRS3 scale, SC680 clamp meter. NAVAC and other brands: coming next. Use Debug capture to record their data; decoders are pluggable.")
                        .font(Theme.font(.caption)).foregroundStyle(Theme.textDim)
                    Text("Xeno is an independent app and is not affiliated with or endorsed by Fieldpiece Instruments. Fieldpiece and Job Link are trademarks of their owner.")
                        .font(Theme.font(.caption2)).foregroundStyle(Theme.textDim)
                } header: { Text("About") }
            }
            .xenoScreen()
            .navigationTitle("Settings")
        }
    }
}

struct ThemeSwatch: View {
    let kind: ThemeKind
    var body: some View {
        let p = kind == .vfd ? Palette.vfd : Palette.biolume
        ZStack {
            RoundedRectangle(cornerRadius: kind == .vfd ? 3 : 12).fill(p.space)
            Text(kind == .vfd ? "88.8" : "40°").font(kind == .vfd ? Font.custom(Theme.dotFont, size: 16) : .system(size: 15, weight: .bold, design: p.design)).foregroundStyle(p.alien)
                .shadow(color: kind == .vfd ? .clear : p.alien, radius: kind == .vfd ? 0 : 4)
        }
        .frame(width: 54, height: 40)
        .overlay(RoundedRectangle(cornerRadius: kind == .vfd ? 3 : 12).stroke(p.alien.opacity(0.6)))
    }
}
