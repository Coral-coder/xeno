// swift-tools-version:5.9
// Renders the app's VFD screens to PNG on Linux/macOS from the real VFD + model code (symlinked),
// so the Amber VFD look can be checked without an iOS build:
//   swift run -c release VFDPreview /tmp/out && python3 ppm2png.py /tmp/out
import PackageDescription

let package = Package(
    name: "VFDPreview",
    targets: [.executableTarget(name: "VFDPreview", path: "Sources/VFDPreview")]
)
