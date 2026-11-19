import SwiftUI

@main
struct XenoApp: App {
    @State private var model = AppModel()

    init() {
        Theme.applyUIKitAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .onAppear { model.start(); UIApplication.shared.isIdleTimerDisabled = model.settings.keepAwake }
                .onChange(of: model.settings.keepAwake) { _, on in UIApplication.shared.isIdleTimerDisabled = on }
        }
    }
}

extension UIFont {
    static func rounded(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let d = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: d, size: size)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            ProbesView().tabItem { Label("Probes", systemImage: "dot.radiowaves.left.and.right") }.tag(AppTab.probes)
            ChargeView().tabItem { Label("Charge", systemImage: "gauge.with.dots.needle.50percent") }.tag(AppTab.charge)
            ToolsView().tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }.tag(AppTab.tools)
            JobsView().tabItem { Label("Jobs", systemImage: "folder") }.tag(AppTab.jobs)
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }.tag(AppTab.settings)
        }
        .tint(Theme.alien)
        .foregroundStyle(Theme.text)
        .fontDesign(Theme.design)
        .font(Theme.font(.body))
        // Rebuild every screen (and UIKit bars) when the theme changes.
        .id(model.settings.theme)
        .onChange(of: model.settings.theme) { _, _ in Theme.applyUIKitAppearance() }
        .onAppear { DispatchQueue.main.async { VFDDisplay.shared.apply(Theme.isVFD) } }
    }
}
