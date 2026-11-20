// swift-tools-version:5.9
// Builds the platform-independent core (refrigerant tables, psychrometrics, HVAC math and the
// Fieldpiece decoder) so it can be unit tested with `swift test` on Linux or macOS. The iOS
// app (project.yml) compiles the same files directly.
import PackageDescription

let package = Package(
    name: "XenoCore",
    targets: [
        .target(name: "XenoCore", path: "Xeno/Core"),
        .testTarget(name: "XenoCoreTests", dependencies: ["XenoCore"], path: "Tests/XenoCoreTests"),
    ]
)
