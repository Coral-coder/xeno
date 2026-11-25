import XCTest
@testable import XenoCore

final class RefrigerantTests: XCTestCase {
    let atm = Units.seaLevelPsia

    func testR410AAt40F() throws {
        let r = try XCTUnwrap(Refrigerants.named("R-410A"))
        XCTAssertEqual(r.satPsig(tempF: 40, side: .dew, atmPsia: atm), 118.0, accuracy: 1.5)
        XCTAssertEqual(try XCTUnwrap(r.satTempF(psig: 118, side: .dew, atmPsia: atm)), 40, accuracy: 0.6)
        XCTAssertEqual(r.satPsig(tempF: 100, side: .bubble, atmPsia: atm), 317, accuracy: 3)
    }

    func testR22AndR134a() throws {
        let r22 = try XCTUnwrap(Refrigerants.named("R22"))
        XCTAssertEqual(r22.satPsig(tempF: 40, side: .dew, atmPsia: atm), 68.5, accuracy: 1)
        let r134 = try XCTUnwrap(Refrigerants.named("r-134a"))
        XCTAssertEqual(r134.satPsig(tempF: 40, side: .dew, atmPsia: atm), 35.0, accuracy: 1)
    }

    func testGlide() throws {
        let r407c = try XCTUnwrap(Refrigerants.named("R-407C"))
        let glide = try XCTUnwrap(r407c.glideF(atPsig: 70, atmPsia: atm))
        XCTAssertGreaterThan(glide, 8); XCTAssertLessThan(glide, 13)
        XCTAssertTrue(r407c.hasGlide)
        XCTAssertFalse(Refrigerants.named("R-22")!.hasGlide)
    }

    func testRoundTripAllRefrigerants() {
        for r in Refrigerants.all {
            for f in stride(from: -20.0, through: 60.0, by: 10) where f < r.maxF {
                let p = r.satPsig(tempF: f, side: .dew, atmPsia: atm)
                guard p > -14 else { continue }
                let back = r.satTempF(psig: p, side: .dew, atmPsia: atm)
                XCTAssertEqual(back ?? .nan, f, accuracy: 0.05, r.name)
            }
        }
    }

    func testSuperheatSubcool() throws {
        let r = try XCTUnwrap(Refrigerants.named("R-410A"))
        let res = HVACCalc.charge(suctionPsig: 118, suctionLineF: 50, liquidPsig: 317, liquidLineF: 90, refrigerant: r,
                                  metering: .txv, targetSuperheat: nil, targetSubcool: 10, atmPsia: atm)
        XCTAssertEqual(try XCTUnwrap(res.superheatF), 10, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(res.subcoolF), 10, accuracy: 1.2)
        XCTAssertEqual(res.diagnosis, .inRange)
    }

    func testTargetSuperheat() {
        XCTAssertEqual(HVACCalc.targetSuperheat(indoorWetBulbF: 63, outdoorDryBulbF: 85) ?? 0, 12, accuracy: 0.01)
        XCTAssertNil(HVACCalc.targetSuperheat(indoorWetBulbF: 55, outdoorDryBulbF: 100))
    }
}

final class PsychroTests: XCTestCase {
    func testStandardState() {
        let a = AirState(dryBulbF: 80, relativeHumidity: 50, pressurePsia: Units.seaLevelPsia)
        XCTAssertEqual(a.wetBulbF, 66.7, accuracy: 0.4)
        XCTAssertEqual(a.dewPointF, 59.7, accuracy: 0.4)
        XCTAssertEqual(a.enthalpy, 31.2, accuracy: 0.4)
        XCTAssertEqual(Psychrometrics.relativeHumidity(dryBulbF: 80, wetBulbF: a.wetBulbF, psia: Units.seaLevelPsia), 50, accuracy: 0.3)
    }
}

final class FieldpieceDecoderTests: XCTestCase {
    func le(_ v: Int) -> [UInt8] { let u = UInt16(bitPattern: Int16(v)); return [UInt8(u & 0xff), UInt8(u >> 8)] }

    func testPipeClamp() throws {
        var d: [UInt8] = [0x46, 0x50, 0x42, 0x46, 1, 2, 0x87, 0x91, 0, 0, 0, 0, 0]
        d += le(725) + [0, 0]
        let ad = try XCTUnwrap(FieldpieceDecoder().decode(manufacturerData: d, localName: nil))
        XCTAssertEqual(ad.model, "JL3PC")
        XCTAssertEqual(ad.serial, "8791")
        XCTAssertEqual(ad.readings.first?.value, 72.5)
        XCTAssertEqual(ad.readings.first?.kind, .temperature)
    }

    func testSmanAndNoReading() throws {
        var d: [UInt8] = [0x46, 0x50, 0x42, 0x54, 1, 0, 0x12, 0x34]
        d += le(1182) + le(3170) + le(-30000) + le(905)
        let ad = try XCTUnwrap(FieldpieceDecoder().decode(manufacturerData: d, localName: nil))
        XCTAssertEqual(ad.readings.map(\.label), ["Low side", "High side", "Liquid line"])
        XCTAssertEqual(ad.readings[0].value, 118.2)
    }

    func testOverrideAndUnknown() throws {
        var d: [UInt8] = [0x46, 0x50, 0x5A, 0x5A, 1, 0, 0, 1, 0, 0, 0, 0, 0]
        d += le(-125)
        let plain = try XCTUnwrap(FieldpieceDecoder().decode(manufacturerData: d, localName: "JL3VG"))
        XCTAssertEqual(plain.category, .unknown)
        XCTAssertEqual(plain.model, "JL3VG")
        let custom = ModelLayout(typeCode: "ZZ", model: "Mystery", category: .pressure,
                                 fields: [FieldLayout(label: "P", kind: .pressure, offset: 13)], batteryOffset: nil, provenance: "test")
        let ad = try XCTUnwrap(FieldpieceDecoder(overrides: ["ZZ": custom]).decode(manufacturerData: d, localName: nil))
        XCTAssertEqual(ad.readings.first?.value, -12.5)
    }

    func testJL3PRAbsoluteHundredths() throws {
        // Field capture at atmosphere: raw 1470 = 14.70 psia -> ~0 psig.
        var d: [UInt8] = [0x46, 0x50, 0x42, 0x47, 1, 0, 0x14, 0x87, 0, 0, 0, 0, 0, 0, 0]
        d += [UInt8(1470 & 0xff), UInt8(1470 >> 8)] + [0, 0, 0, 0, 0, 87]
        let ad = try XCTUnwrap(FieldpieceDecoder().decode(manufacturerData: d, localName: nil))
        XCTAssertEqual(try XCTUnwrap(ad.readings.first?.value), 0, accuracy: 0.05)
        // 132.70 psia at sea level = 118.0 psig
        d[15] = UInt8(13270 & 0xff); d[16] = UInt8(13270 >> 8)
        XCTAssertEqual(try XCTUnwrap(FieldpieceDecoder().decode(manufacturerData: d, localName: nil)?.readings.first?.value), 118.0, accuracy: 0.05)
    }

    func testJL3KMSinglePort() throws {
        var d: [UInt8] = [0x46, 0x50, 0x42, 0x58, 1, 0, 0x12, 0x17, 0x14, 0x20, 0x20, 0x06, 0]
        d += [0xFC, 0xFF]   // -0.04 inWC
        let ad = try XCTUnwrap(FieldpieceDecoder().decode(manufacturerData: d, localName: nil))
        XCTAssertEqual(ad.readings.count, 1)
        XCTAssertEqual(ad.readings[0].value, -0.04, accuracy: 0.001)
    }

    func testSingleManifoldCapture() throws {
        // Real broadcast from a single-port manifold at atmosphere, no clamp connected.
        let hex = "46 50 43 50 25 02 32 92 88 01 0F 00 01 03 EF 02 92 20 A1 07 00 00 D0 8A 58 02 31 01 66"
        let d = hex.split(separator: " ").map { UInt8($0, radix: 16)! }
        let ad = try XCTUnwrap(FieldpieceDecoder().decode(manufacturerData: d, localName: nil))
        XCTAssertEqual(ad.serial, "3292")
        // Manifold screen at capture: low 39.1 psig, T1 76.8 F, T2 75.1 F.
        XCTAssertEqual(ad.readings.map(\.label), ["Low side", "High side", "Suction line", "Liquid line"])
        XCTAssertEqual(ad.readings[0].value, 39.2, accuracy: 0.001)
        XCTAssertEqual(ad.readings[2].value, 76.9, accuracy: 0.001)
        XCTAssertEqual(ad.readings[3].value, 75.1, accuracy: 0.001)
    }

    func testClampMeter() throws {
        var d: [UInt8] = [0x46, 0x50, 0x43, 0x42, 1, 0, 0, 9, 0, 0, 0, 0, 0]
        d += le(2405) + [1, 0x02] + [0, 0]
        d += le(1234) + [2, 0x03]
        let ad = try XCTUnwrap(FieldpieceDecoder().decode(manufacturerData: d, localName: nil))
        XCTAssertEqual(ad.readings.count, 2)
        XCTAssertEqual(ad.readings[0].value, 240.5, accuracy: 0.001)
        XCTAssertEqual(ad.readings[1].kind, .currentAC)
        XCTAssertEqual(ad.readings[1].value, 12.34, accuracy: 0.001)
    }

    func testRejectsOtherVendors() {
        XCTAssertNil(FieldpieceDecoder().decode(manufacturerData: [0x4C, 0, 2, 0x15, 0, 0, 0, 0], localName: nil))
    }
}

final class FormatTests: XCTestCase {
    func testNoNegativeZero() {
        XCTAssertEqual((-0.04).formatted(decimals: 1), "0.0")
        XCTAssertEqual((-0.0).formatted(decimals: 2), "0.00")
        XCTAssertEqual((-0.06).formatted(decimals: 1), "-0.1")
        XCTAssertEqual((-0.04).formatted(decimals: 2), "-0.04")
    }
}

final class TestMathTests: XCTestCase {
    func testPressureCompensation() {
        let p = PressureTest.expectedPsig(startPsig: 300, startTempF: 70, nowTempF: 60, atmPsia: Units.seaLevelPsia)
        XCTAssertEqual(p, 293.9, accuracy: 0.3)
    }

    func testVacuumVerdict() {
        let t0 = Date()
        let tight = (0...10).map { TimedSample(t: t0.addingTimeInterval(Double($0) * 60), value: 300 + Double($0) * 5) }
        XCTAssertEqual(VacuumAnalysis.verdict(samples: tight, limit: 500, holdSeconds: 600), .pass)
        let leak = (0...10).map { TimedSample(t: t0.addingTimeInterval(Double($0) * 60), value: 300 + Double($0) * 100) }
        XCTAssertEqual(VacuumAnalysis.verdict(samples: leak, limit: 500, holdSeconds: 600), .leak)
        let wet = (0...10).map { TimedSample(t: t0.addingTimeInterval(Double($0) * 60), value: 300 + 900 * (1 - exp(-Double($0) / 1.5))) }
        XCTAssertEqual(VacuumAnalysis.verdict(samples: wet, limit: 500, holdSeconds: 600), .moisture)
    }
}
