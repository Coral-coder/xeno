import Foundation

/// Simulated probes for demos, training and screenshots. Fieldpiece probes are simulated as
/// raw advertisement bytes and pushed through the real decoder, so demo mode also exercises
/// the decoding path.
final class DemoSource {
    private weak var model: AppModel?
    private var timer: Timer?
    private var t0 = Date()
    private var tick = 0

    init(model: AppModel) { self.model = model }

    func start() {
        guard timer == nil else { return }
        t0 = Date().addingTimeInterval(-600)
        // Seed some history so graphs aren't empty.
        for i in stride(from: 600, to: 0, by: -2) { emit(at: Date().addingTimeInterval(-Double(i))) }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.emit(at: Date()) }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func le(_ v: Double, _ scale: Double = 10) -> [UInt8] {
        let u = UInt16(bitPattern: Int16(clamping: Int((v * scale).rounded())))
        return [UInt8(u & 0xff), UInt8(u >> 8)]
    }

    /// Unsigned hundredths, little-endian (JL3PR absolute pressure).
    private func leU(_ v: Double) -> [UInt8] {
        let u = UInt16(clamping: Int((v * 100).rounded()))
        return [UInt8(u & 0xff), UInt8(u >> 8)]
    }

    private func packet(_ type: String, serial: UInt16, body: [UInt8]) -> [UInt8] {
        let t = Array(type.utf8)
        return [0x46, 0x50, t[0], t[1], 1, 4, UInt8(serial >> 8), UInt8(serial & 0xff)] + body
    }

    private func emit(at now: Date) {
        guard let model else { return }
        let s = now.timeIntervalSince(t0)
        func wob(_ amp: Double, _ period: Double, _ phase: Double = 0) -> Double { amp * sin(2 * .pi * (s + phase) / period) }
        let decoder = model.decoder
        func send(_ bytes: [UInt8], _ rssi: Int) {
            if let ad = decoder.decode(manufacturerData: bytes, localName: nil) { model.probes.ingest(ad, rssi: rssi, at: now) }
        }
        let pad5: [UInt8] = [0, 0, 0, 0, 0]
        // JL3PR suction / liquid (kPa gauge at 15–16)
        let suction = 118.5 + wob(1.6, 23), liquid = 338 + wob(3, 31, 4)
        send(packet("BG", serial: 0x4A21, body: pad5 + [0, 0] + leU(model.settings.atmPsia) + leU(suction + model.settings.atmPsia) + [0, 0, 0, 87]), -58)
        send(packet("BG", serial: 0x4A22, body: pad5 + [0, 0] + leU(model.settings.atmPsia) + leU(liquid + model.settings.atmPsia) + [0, 0, 0, 74]), -61)
        // JL3PC suction / liquid line
        send(packet("BF", serial: 0x8791, body: pad5 + le(50.6 + wob(0.6, 19)) + [0, 0]), -55)
        send(packet("BF", serial: 0x8792, body: pad5 + le(93.4 + wob(0.5, 27)) + [0, 0]), -63)
        // JL3RH return / supply / outdoor
        func rh(_ serial: UInt16, db: Double, rh: Double, battery: UInt8, rssi: Int) {
            let a = AirState(dryBulbF: db, relativeHumidity: rh, pressurePsia: Units.seaLevelPsia)
            send(packet("BH", serial: serial, body: pad5 + le(db) + le(a.wetBulbF) + le(a.dewPointF) + le(rh) + [0, 0, 0, battery]), rssi)
        }
        rh(0x2210, db: 75.4 + wob(0.3, 41), rh: 49 + wob(0.6, 37), battery: 92, rssi: -66)
        rh(0x2211, db: 56.2 + wob(0.4, 29), rh: 88 + wob(0.8, 33), battery: 81, rssi: -70)
        rh(0x2212, db: 91.8 + wob(0.4, 53), rh: 41 + wob(1, 47), battery: 64, rssi: -77)
        // Two JL3KM manometers: supply and return static
        send(packet("BX", serial: 0x1217, body: pad5 + le(0.41 + wob(0.01, 13), 100)), -72)
        send(packet("BX", serial: 0x1218, body: pad5 + le(-0.37 + wob(0.01, 17), 100)), -74)
        // Vacuum gauge (layout not public yet — injected directly)
        let micronsCurve = 250 + 9000 * exp(-s / 40)
        let vac = ProbeAdvert(vendor: "Demo", model: "Vacuum", typeCode: "VG", serial: "5150", firmware: nil, category: .vacuum,
                              battery: 95, readings: [SensorReading(kind: .vacuum, label: "Vacuum", value: max(212, micronsCurve + wob(6, 9)))], raw: [])
        model.probes.ingest(vac, rssi: -60, at: now)
        tick += 1
    }
}
