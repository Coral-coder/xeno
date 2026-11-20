import AudioToolbox
import SwiftUI

/// Weigh-in charging with a refrigerant scale (or manual entry).
struct WeighInView: View {
    @Environment(AppModel.self) private var model
    @State private var targetText = "2.50"
    @State private var tare: Double?
    @State private var alerted = false
    @State private var manualWeight = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let scale = model.probes.probes.first { $0.category == .scale && !$0.isStale(now: .now, after: model.settings.staleSeconds) }
            let weight = scale?.first(.weight)?.value ?? Double(manualWeight)
            let target = Double(targetText) ?? 0
            // Tank weight drops as refrigerant goes into the system.
            let charged = (tare != nil && weight != nil) ? tare! - weight! : nil
            let progress = (charged != nil && target > 0) ? min(1, max(0, charged! / target)) : 0
            ScrollView {
                VStack(spacing: 14) {
                    XenoCard(glow: Theme.beam) {
                        VStack(spacing: 10) {
                            if Theme.isVFD {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(charged.map { lbOz($0) } ?? "––").font(Theme.vfdFontBig)
                                    Text("OF \(lbOz(target))").font(Theme.vfdFont).foregroundStyle(Theme.textDim)
                                    PixelBar(marker: progress, fillToMarker: true, color: progress >= 1 ? Theme.alien : Theme.beam)
                                        .frame(height: Theme.vfdPixel * 6)
                                }
                            } else {
                            ZStack {
                                Circle().stroke(Theme.text.opacity(0.08), lineWidth: 16)
                                Circle().trim(from: 0, to: progress).stroke(progress >= 1 ? Theme.alien : Theme.beam, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                                    .rotationEffect(.degrees(-90)).glow(color: Theme.beam.opacity(0.6), radius: 8)
                                VStack(spacing: 2) {
                                    Text(charged.map { lbOz($0) } ?? "––").font(Theme.reading(36))
                                    Text("of \(lbOz(target))").font(Theme.font(.caption)).foregroundStyle(Theme.textDim)
                                }
                            }
                            .frame(width: 210, height: 210)
                            .padding(.vertical, 6)
                            }
                            if let charged, charged >= target, target > 0 {
                                Text("TARGET REACHED: close the valve").font(Theme.font(.headline)).foregroundStyle(Theme.alien)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    XenoCard {
                        VStack(spacing: 10) {
                            LabeledField(label: "Charge to add", text: $targetText, unit: "lb")
                            if let scale {
                                KeyValueRow(key: "Scale \(scale.displayName)", value: weight.map { $0.formatted(decimals: 2) } ?? "––", unit: "lb")
                            } else {
                                LabeledField(label: "Tank weight (manual)", text: $manualWeight, unit: "lb")
                                Text("No scale connected; type the tank weight from any scale.").font(Theme.font(.caption)).foregroundStyle(Theme.textDim)
                            }
                            Button(tare == nil ? "Zero (start charging)" : "Re-zero") { tare = weight; alerted = false }
                                .buttonStyle(GlowButtonStyle(color: Theme.beam)).disabled(weight == nil)
                        }
                    }
                    LineSetCard(targetText: $targetText)
                }
                .padding(16)
            }
            .onChange(of: progress) { _, p in
                if p >= 1 && !alerted { alerted = true; Alerts.fire() }
            }
        }
        .xenoScreen()
        .navigationTitle("Weigh-in charge")
    }

    func lbOz(_ lb: Double) -> String {
        let total = max(0, lb) * 16
        return "\(Int(total / 16)) lb \(Int((total.truncatingRemainder(dividingBy: 16)).rounded())) oz"
    }
}

/// Line-set length charge adjustment.
struct LineSetCard: View {
    @Binding var targetText: String
    @State private var actualText = "35"
    @State private var includedText = "15"
    @State private var size = 0.375

    // Typical R-410A liquid-line adjustment, oz per foot. Check the manufacturer's installation manual.
    static let ozPerFt: [Double: Double] = [0.25: 0.3, 0.3125: 0.4, 0.375: 0.6, 0.5: 1.2]

    var body: some View {
        let extra = max(0, (Double(actualText) ?? 0) - (Double(includedText) ?? 0)) * (Self.ozPerFt[size] ?? 0.6)
        XenoCard(glow: Theme.nebula) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Line-set adjustment", symbol: "ruler")
                Picker("Liquid line", selection: $size) {
                    Text("1/4\"").tag(0.25); Text("5/16\"").tag(0.3125); Text("3/8\"").tag(0.375); Text("1/2\"").tag(0.5)
                }.pickerStyle(.segmented)
                LabeledField(label: "Actual length", text: $actualText, unit: "ft")
                LabeledField(label: "Included in factory charge", text: $includedText, unit: "ft")
                KeyValueRow(key: "Additional charge", value: extra.formatted(decimals: 1), unit: "oz")
                Button("Use as charge target") { targetText = (extra / 16).formatted(decimals: 2) }.font(Theme.font(.caption, weight: .semibold))
                Text("Typical R-410A rates (\(Self.ozPerFt[size]?.formatted(decimals: 1) ?? "") oz/ft). Always confirm with the manufacturer's installation instructions.")
                    .font(Theme.font(.caption2)).foregroundStyle(Theme.textDim)
            }
        }
    }
}

/// Capacitor and motor electrical checks.
struct ElectricalView: View {
    @Environment(AppModel.self) private var model
    @State private var ratedUF = "45"
    @State private var measuredUF = ""
    @State private var tolerance = 6.0
    @State private var startAmps = ""
    @State private var capVolts = ""
    @State private var rla = ""
    @State private var measuredAmps = ""

    var body: some View {
        let meter = model.probes.probes.first { $0.category == .multimeter }
        ScrollView {
            VStack(spacing: 14) {
                XenoCard(glow: Theme.warn) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Run capacitor", symbol: "bolt.batteryblock")
                        LabeledField(label: "Rated", text: $ratedUF, unit: "µF")
                        LabeledField(label: "Measured", text: $measuredUF, unit: "µF")
                        if let c = meter?.first(.capacitance) {
                            Button("Use meter: \(c.value.formatted(decimals: 1)) µF") { measuredUF = c.value.formatted(decimals: 1) }.font(Theme.font(.caption, weight: .semibold))
                        }
                        Picker("Tolerance", selection: $tolerance) { Text("±5%").tag(5.0); Text("±6%").tag(6.0); Text("±10%").tag(10.0) }.pickerStyle(.segmented)
                        if let r = Double(ratedUF), let m = Double(measuredUF), r > 0 {
                            let dev = (m - r) / r * 100
                            let ok = abs(dev) <= tolerance
                            KeyValueRow(key: "Deviation", value: dev.formatted(decimals: 1), unit: "%")
                            KeyValueRow(key: "Acceptable range", value: "\((r * (1 - tolerance / 100)).formatted(decimals: 1))–\((r * (1 + tolerance / 100)).formatted(decimals: 1))", unit: "µF")
                            Text(ok ? "GOOD" : "REPLACE CAPACITOR").font(Theme.font(.headline)).foregroundStyle(ok ? Theme.alien : Theme.danger)
                        }
                    }
                }
                XenoCard(glow: Theme.beam) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Capacitor under load", symbol: "waveform")
                        LabeledField(label: "Start-winding amps", text: $startAmps, unit: "A")
                        LabeledField(label: "Voltage across cap", text: $capVolts, unit: "V")
                        if let a = Double(startAmps), let v = Double(capVolts), v > 0 {
                            KeyValueRow(key: "Calculated capacitance", value: (2652 * a / v).formatted(decimals: 1), unit: "µF")
                        }
                        Text("µF = 2652 × amps ÷ volts (60 Hz). Measures the capacitor in-circuit while running.").font(Theme.font(.caption2)).foregroundStyle(Theme.textDim)
                    }
                }
                XenoCard(glow: Theme.nebula) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Compressor / motor load", symbol: "gauge.with.dots.needle.bottom.50percent")
                        LabeledField(label: "Nameplate RLA / FLA", text: $rla, unit: "A")
                        LabeledField(label: "Measured", text: $measuredAmps, unit: "A")
                        if let a = meter?.first(.currentAC) {
                            Button("Use clamp: \(a.value.formatted(decimals: 2)) A") { measuredAmps = a.value.formatted(decimals: 2) }.font(Theme.font(.caption, weight: .semibold))
                        }
                        if let r = Double(rla), let m = Double(measuredAmps), r > 0 {
                            let pct = m / r * 100
                            KeyValueRow(key: "Load", value: pct.formatted(decimals: 0), unit: "% of rated")
                            Text(pct > 100 ? "Over rated amps: check voltage, capacitor, head pressure, bearings" : pct < 50 ? "Low load: check charge, airflow, valves" : "Normal range")
                                .font(Theme.font(.subheadline)).foregroundStyle(pct > 100 ? Theme.danger : pct < 50 ? Theme.warn : Theme.alien)
                        }
                    }
                }
            }
            .padding(16)
        }
        .xenoScreen()
        .navigationTitle("Electrical")
    }
}

/// HVAC unit converter.
struct ConverterView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case temperature = "Temp", pressure = "Pressure", vacuum = "Vacuum", air = "Static", capacity = "Capacity", weight = "Weight"
        var id: String { rawValue }
        var units: [String] {
            switch self {
            case .temperature: return ["°F", "°C", "K"]
            case .pressure: return ["psi", "kPa", "bar", "MPa", "inHg", "kg/cm²"]
            case .vacuum: return ["microns", "Pa", "mbar", "Torr", "inHg"]
            case .air: return ["inWC", "Pa", "mmWC", "mbar"]
            case .capacity: return ["BTU/h", "tons", "kW", "W"]
            case .weight: return ["lb", "oz", "kg", "g"]
            }
        }
        /// Factor to the first unit (temperature handled separately).
        func toBase(_ v: Double, _ u: String) -> Double {
            switch (self, u) {
            case (.temperature, "°C"): return v * 9 / 5 + 32
            case (.temperature, "K"): return (v - 273.15) * 9 / 5 + 32
            case (.pressure, "kPa"): return v / 6.894757
            case (.pressure, "bar"): return v * 14.50377
            case (.pressure, "MPa"): return v * 145.0377
            case (.pressure, "inHg"): return v * 0.491154
            case (.pressure, "kg/cm²"): return v * 14.22334
            case (.vacuum, "Pa"): return v / 0.133322
            case (.vacuum, "mbar"): return v / 0.00133322
            case (.vacuum, "Torr"): return v * 1000
            case (.vacuum, "inHg"): return v * 25400
            case (.air, "Pa"): return v / 249.0889
            case (.air, "mmWC"): return v / 25.4
            case (.air, "mbar"): return v / 2.490889
            case (.capacity, "tons"): return v * 12000
            case (.capacity, "kW"): return v * 3412.142
            case (.capacity, "W"): return v * 3.412142
            case (.weight, "oz"): return v / 16
            case (.weight, "kg"): return v * 2.204623
            case (.weight, "g"): return v * 0.002204623
            default: return v
            }
        }
        func fromBase(_ b: Double, _ u: String) -> Double {
            if self == .temperature {
                return u == "°C" ? (b - 32) * 5 / 9 : u == "K" ? (b - 32) * 5 / 9 + 273.15 : b
            }
            return b / toBase(1, u)
        }
    }

    @State private var kind: Kind = .pressure
    @State private var input = "100"
    @State private var unit = "psi"

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("Kind", selection: $kind) { ForEach(Kind.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                    .onChange(of: kind) { _, k in unit = k.units[0] }
                XenoCard {
                    HStack {
                        TextField("Value", text: $input).keyboardType(.numbersAndPunctuation).font(Theme.reading(30))
                        Picker("Unit", selection: $unit) { ForEach(kind.units, id: \.self) { Text($0).tag($0) } }
                    }
                }
                if let v = Double(input) {
                    let base = kind.toBase(v, unit)
                    XenoCard(glow: Theme.beam) {
                        VStack(spacing: 10) {
                            ForEach(kind.units.filter { $0 != unit }, id: \.self) { u in
                                let out = kind.fromBase(base, u)
                                KeyValueRow(key: u, value: abs(out) >= 1000 || abs(out) < 0.01 && out != 0 ? String(format: "%.4g", out) : out.formatted(decimals: 2))
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .xenoScreen()
        .navigationTitle("Converter")
    }
}

/// Haptic + sound alerts for finished tests.
enum Alerts {
    static func fire() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AudioServicesPlaySystemSound(1005)
    }
}

/// EPA Section 608 annualized leak rate (appliances ≥ 15 lb).
struct LeakRateView: View {
    @State private var added = "4"
    @State private var fullCharge = "40"
    @State private var daysSince = "120"
    @State private var type = 0  // 0 comfort cooling, 1 commercial refrigeration, 2 industrial process

    var body: some View {
        let limits = [10.0, 20.0, 30.0]
        let rate: Double? = {
            guard let a = Double(added), let c = Double(fullCharge), let d = Double(daysSince), c > 0, d > 0 else { return nil }
            return a / c * (365 / d) * 100
        }()
        ScrollView {
            VStack(spacing: 14) {
                XenoCard(glow: Theme.warn) {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledField(label: "Refrigerant added", text: $added, unit: "lb")
                        LabeledField(label: "Full charge", text: $fullCharge, unit: "lb")
                        LabeledField(label: "Days since last addition", text: $daysSince, unit: "days")
                        Picker("Appliance", selection: $type) {
                            Text("Comfort").tag(0); Text("Commercial").tag(1); Text("Industrial").tag(2)
                        }.pickerStyle(.segmented)
                    }
                }
                XenoCard(glow: (rate ?? 0) > limits[type] ? Theme.danger : Theme.alien) {
                    VStack(alignment: .leading, spacing: 8) {
                        ReadingView(caption: "Annualized leak rate", value: rate.map { $0.formatted(decimals: 1) } ?? "––", unit: "%",
                                    color: (rate ?? 0) > limits[type] ? Theme.danger : Theme.alien, size: 44)
                        Text("Threshold for this appliance type: \(Int(limits[type]))%/yr").font(Theme.font(.caption)).foregroundStyle(Theme.textDim)
                        if let rate, rate > limits[type] {
                            Text("Over the threshold: repair within 30 days and do a verification test. Keep records.")
                                .font(Theme.font(.subheadline)).foregroundStyle(Theme.danger)
                        }
                        Text("Annualizing method: (lb added ÷ full charge) × (365 ÷ days since last addition) × 100. Applies to appliances with 15 lb or more of refrigerant; check current EPA 608 rules for your refrigerant.")
                            .font(Theme.font(.caption2)).foregroundStyle(Theme.textDim)
                    }
                }
            }
            .padding(16)
        }
        .xenoScreen()
        .navigationTitle("Leak rate (EPA 608)")
    }
}

/// Duct airflow from velocity and duct size.
struct DuctAirflowView: View {
    @State private var round = true
    @State private var diameter = "12"
    @State private var width = "20"
    @State private var height = "10"
    @State private var fpm = "700"

    var body: some View {
        let area: Double? = round
            ? Double(diameter).map { .pi * pow($0 / 2, 2) / 144 }
            : (Double(width) != nil && Double(height) != nil ? Double(width)! * Double(height)! / 144 : nil)
        ScrollView {
            VStack(spacing: 14) {
                XenoCard(glow: Theme.nebula) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Shape", selection: $round) { Text("Round").tag(true); Text("Rectangular").tag(false) }.pickerStyle(.segmented)
                        if round {
                            LabeledField(label: "Diameter", text: $diameter, unit: "in")
                        } else {
                            LabeledField(label: "Width", text: $width, unit: "in")
                            LabeledField(label: "Height", text: $height, unit: "in")
                        }
                        LabeledField(label: "Average velocity", text: $fpm, unit: "FPM")
                    }
                }
                XenoCard(glow: Theme.beam) {
                    VStack(alignment: .leading, spacing: 8) {
                        ReadingView(caption: "Airflow", value: (area != nil && Double(fpm) != nil) ? (area! * Double(fpm)!).formatted(decimals: 0) : "––", unit: "CFM", color: Theme.beam, size: 44)
                        KeyValueRow(key: "Free area", value: area.map { $0.formatted(decimals: 3) } ?? "––", unit: "ft²")
                        if !round, let w = Double(width), let h = Double(height), w + h > 0 {
                            KeyValueRow(key: "Equivalent round", value: (1.30 * pow(w * h, 0.625) / pow(w + h, 0.25)).formatted(decimals: 1), unit: "in")
                        }
                        Text("Use the average of a duct traverse (anemometer readings across the duct) for velocity. Typical residential: supply trunks 700–900 FPM, branches 500–600, returns ≤ 700.")
                            .font(Theme.font(.caption2)).foregroundStyle(Theme.textDim)
                    }
                }
            }
            .padding(16)
        }
        .xenoScreen()
        .navigationTitle("Duct airflow")
    }
}
