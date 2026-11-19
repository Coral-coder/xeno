import SwiftUI

struct ToolsView: View {
    struct Tool: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let color: Color
    }

    let tools: [Tool] = [
        Tool(id: "vacuum", title: "Evacuation", subtitle: "Micron gauge · decay test", symbol: "arrow.down.to.line.compact", color: Theme.warn),
        Tool(id: "pressure", title: "Pressure test", subtitle: "Nitrogen standing test", symbol: "gauge.with.dots.needle.100percent", color: Theme.beam),
        Tool(id: "airflow", title: "Airflow & capacity", subtitle: "ΔT · enthalpy · BTU/h", symbol: "wind", color: Theme.nebula),
        Tool(id: "static", title: "Static pressure", subtitle: "TESP · fan laws", symbol: "rectangle.compress.vertical", color: Theme.alien),
        Tool(id: "targetsh", title: "Target superheat", subtitle: "Fixed orifice charging", symbol: "target", color: Theme.beam),
        Tool(id: "pt", title: "P/T chart", subtitle: "\(Refrigerants.all.count) refrigerants", symbol: "tablecells", color: Theme.alien),
        Tool(id: "psychro", title: "Psychrometrics", subtitle: "WB · DP · grains · enthalpy", symbol: "humidity", color: Theme.nebula),
        Tool(id: "furnace", title: "Furnace airflow", subtitle: "Temperature rise method", symbol: "flame", color: Theme.danger),
        Tool(id: "weighin", title: "Weigh-in charge", subtitle: "Scale · line-set adjust", symbol: "scalemass", color: Theme.beam),
        Tool(id: "electrical", title: "Electrical", subtitle: "Capacitors · motor amps", symbol: "bolt", color: Theme.warn),
        Tool(id: "convert", title: "Converter", subtitle: "Pressure · vacuum · capacity", symbol: "arrow.left.arrow.right", color: Theme.alien),
        Tool(id: "duct", title: "Duct airflow", subtitle: "Velocity × area · equiv. round", symbol: "square.split.diagonal", color: Theme.nebula),
        Tool(id: "leak", title: "Leak rate", subtitle: "EPA 608 annualized", symbol: "drop.triangle", color: Theme.danger),
        Tool(id: "logger", title: "Data logger", subtitle: "Graph every probe", symbol: "chart.xyaxis.line", color: Theme.warn),
        Tool(id: "explorer", title: "BLE explorer", subtitle: "Any probe, any brand", symbol: "antenna.radiowaves.left.and.right", color: Theme.textDim),
    ]

    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(tools) { t in
                        NavigationLink(value: t.id) {
                            XenoCard(glow: t.color) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Image(systemName: t.symbol).font(Theme.font(.title2)).foregroundStyle(t.color)
                                        .shadow(color: t.color.opacity(0.7), radius: 8)
                                    Text(t.title).font(Theme.font(.headline)).foregroundStyle(Theme.text)
                                    Text(t.subtitle).font(Theme.font(.caption)).foregroundStyle(Theme.textDim).lineLimit(2, reservesSpace: true)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .xenoScreen()
            .navigationTitle("Tools")
            .navigationDestination(for: String.self) { id in destination(id) }
            .onAppear {
                if path.isEmpty, let t = UserDefaults.standard.string(forKey: "XenoTool") { path = [t] }
            }
        }
    }

    @ViewBuilder func destination(_ id: String) -> some View {
        switch id {
        case "vacuum": VacuumView()
        case "pressure": PressureTestView()
        case "airflow": AirflowView()
        case "static": StaticPressureView()
        case "targetsh": TargetSuperheatView()
        case "pt": PTChartView()
        case "psychro": PsychroView()
        case "furnace": FurnaceView()
        case "logger": LoggerView()
        case "debug": DebugCaptureView()
        case "weighin": WeighInView()
        case "electrical": ElectricalView()
        case "convert": ConverterView()
        case "duct": DuctAirflowView()
        case "leak": LeakRateView()
        case "lab": ProbeLabView()
        default: ExplorerView()
        }
    }
}
