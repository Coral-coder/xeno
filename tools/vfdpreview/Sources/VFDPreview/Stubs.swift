import Foundation

/// Stand-ins for the iOS-only pieces AppModel touches.
final class BluetoothService {
    enum State: Equatable { case unknown, poweredOff, unauthorized, unsupported, scanning, idle }
    var state: State = .unknown
    var advertsPerSecond: Double = 0
    init(model: AppModel) {}
    func start() {}
}

enum Theme { static var kind: ThemeKind = .biolume; static var tint: VFDTint = .amber }
