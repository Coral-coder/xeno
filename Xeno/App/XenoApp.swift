import SwiftUI

@main
struct XenoApp: App {
    @State private var model = AppModel()

    init() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white, .font: UIFont.rounded(size: 32, weight: .bold)]
        nav.titleTextAttributes = [.foregroundColor: UIColor.white, .font: UIFont.rounded(size: 17, weight: .semibold)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundColor = UIColor(red: 0.02, green: 0.03, blue: 0.07, alpha: 0.85)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.alien)
                .onAppear { model.start() }
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
    }
}
