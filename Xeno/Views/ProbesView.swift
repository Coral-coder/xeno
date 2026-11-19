import SwiftUI

enum ProbesRoute: Hashable { case debug, lab, explorer }

struct ProbesView: View {
    @Environment(AppModel.self) private var model
    @State private var route: ProbesRoute?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ScanBanner()
                    if model.probes.probes.isEmpty {
                        EmptyProbes()
                    } else {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
                                ForEach(model.probes.probes) { p in
                                    NavigationLink(value: p.key) {
                                        ProbeCard(probe: p, now: ctx.date)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .xenoScreen()
            .navigationTitle("Probes")
            .navigationDestination(for: String.self) { key in
                if let p = model.probes.probe(key) { ProbeDetailView(probe: p) }
            }
            .navigationDestination(item: $route) { r in
                switch r {
                case .debug: DebugCaptureView()
                case .lab: ProbeLabView()
                case .explorer: ExplorerView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AlienGlyph().frame(width: 22)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { route = .debug } label: { Label("Debug capture (zip & email)", systemImage: "ladybug") }
                        Button { route = .lab } label: { Label("Probe Lab", systemImage: "waveform.badge.magnifyingglass") }
                        Button { route = .explorer } label: { Label("BLE explorer", systemImage: "antenna.radiowaves.left.and.right") }
                    } label: { Image(systemName: "waveform.badge.magnifyingglass") }
                }
            }
        }
    }
}

struct ScanBanner: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let bt = model.bluetooth.state
        let demo = model.settings.demoMode
        let (text, color): (String, Color) = {
            if demo && bt != .scanning { return ("Demo probes broadcasting", Theme.nebula) }
            switch bt {
            case .scanning: return ("Scanning for probes", Theme.alien)
            case .poweredOff: return ("Bluetooth is off", Theme.warn)
            case .unauthorized: return ("Bluetooth permission denied — enable in Settings", Theme.danger)
            case .unsupported: return ("Bluetooth not available on this device", Theme.danger)
            case .idle: return ("Scanning paused", Theme.warn)
            case .unknown: return ("Starting Bluetooth…", Theme.textDim)
            }
        }()
        HStack(spacing: 10) {
            PulseDot(color: color, active: bt == .scanning)
            Text(text).font(.system(.subheadline, design: .rounded).weight(.medium))
            Spacer()
            if model.settings.demoMode { StatusPill(text: "DEMO", color: Theme.nebula) }
            Text("\(model.probes.probes.count) found").font(Theme.label).foregroundStyle(Theme.textDim)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Capsule().fill(Theme.spaceRaised.opacity(0.8)))
        .overlay(Capsule().strokeBorder(color.opacity(0.35)))
    }
}

struct PulseDot: View {
    var color: Color
    var active: Bool
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.3)).frame(width: 18, height: 18).scaleEffect(pulse ? 1.3 : 0.6).opacity(active ? (pulse ? 0 : 1) : 0)
            Circle().fill(color).frame(width: 8, height: 8)
        }
        .onAppear { withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true } }
    }
}

struct EmptyProbes: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: 16) {
            AlienGlyph(color: Theme.alien.opacity(0.8)).frame(width: 80)
                .shadow(color: Theme.alien.opacity(0.6), radius: 20)
            Text("Searching the airwaves…").font(.system(.title3, design: .rounded).weight(.semibold))
            Text("Turn on your Fieldpiece Job Link probes. They appear here automatically. No pairing needed.")
                .font(.system(.subheadline, design: .rounded)).foregroundStyle(Theme.textDim).multilineTextAlignment(.center)
            Button("Try demo probes") { model.setDemo(true) }.buttonStyle(GlowButtonStyle(color: Theme.nebula)).frame(maxWidth: 240)
        }
        .padding(.vertical, 60)
    }
}

struct ProbeCard: View {
    @Environment(AppModel.self) private var model
    let probe: Probe
    let now: Date

    var body: some View {
        let stale = probe.isStale(now: now, after: model.settings.staleSeconds)
        let roles = model.probes.roles(of: probe)
        let fmt = model.fmt
        XenoCard(glow: stale ? Theme.textDim : color) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: probe.category.symbol).foregroundStyle(color)
                    Text(probe.displayName).font(.system(.subheadline, design: .rounded).weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 4) {
                    ForEach(roles) { StatusPill(text: $0.short, color: Theme.beam) }
                    if roles.isEmpty { StatusPill(text: probe.model, color: Theme.textDim) }
                }
                ForEach(probe.readings.filter { $0.kind != .wetBulb && $0.kind != .dewPoint }.prefix(4)) { r in
                    let (v, u) = fmt.reading(r)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if probe.readings.count > 1 { Text(r.label).font(.caption2).foregroundStyle(Theme.textDim).frame(width: 52, alignment: .leading).lineLimit(1) }
                        Text(v).font(Theme.reading(probe.readings.count > 1 ? 20 : 30)).foregroundStyle(stale ? Theme.textDim : .white)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(u).font(.caption2).foregroundStyle(Theme.textDim)
                    }
                }
                if probe.readings.isEmpty {
                    Text(probe.category == .unknown ? "Unknown model: open Probe Lab" : "No reading")
                        .font(.caption).foregroundStyle(Theme.warn)
                }
                HStack(spacing: 8) {
                    SignalBars(rssi: probe.rssi, stale: stale)
                    if let b = probe.battery { BatteryIcon(level: b) }
                    Spacer()
                    if stale { Text("offline").font(.caption2).foregroundStyle(Theme.danger) }
                }
            }
        }
    }

    var color: Color {
        switch probe.category {
        case .pressure, .manifold: return Theme.beam
        case .pipeClamp: return Theme.alien
        case .psychrometer: return Theme.nebula
        case .vacuum: return Theme.warn
        default: return Theme.alien
        }
    }
}

struct SignalBars: View {
    var rssi: Int
    var stale: Bool
    var body: some View {
        let level = rssi > -60 ? 4 : rssi > -70 ? 3 : rssi > -80 ? 2 : 1
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1).fill(i <= level && !stale ? Theme.alien : Color.white.opacity(0.2)).frame(width: 3, height: CGFloat(3 + i * 3))
            }
        }
    }
}

struct BatteryIcon: View {
    var level: Int
    var body: some View {
        let sym = level > 75 ? "battery.100" : level > 50 ? "battery.75" : level > 25 ? "battery.50" : level > 10 ? "battery.25" : "battery.0"
        HStack(spacing: 2) {
            Image(systemName: sym).foregroundStyle(level > 20 ? Theme.textDim : Theme.danger)
            Text("\(level)%").font(.caption2).foregroundStyle(Theme.textDim)
        }
        .font(.caption)
    }
}
