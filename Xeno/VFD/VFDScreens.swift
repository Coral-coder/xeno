import Foundation

/// Immediate-mode screens for the VFD pixel matrix. Each draws into the buffer at `y` (in
/// content rows) and registers tap regions; layouts use proportional columns so they fit both
/// 3x (~241 cells wide) and 2x (~207 cells) screens.
struct VFDPainter {
    let b: VFDBuffer
    let model: AppModel
    let now: Date
    let actions: VFDActions
    var y = 0

    var left: Int { 6 }
    var right: Int { b.cols - 7 }
    var width: Int { right - left }
    var fmt: Fmt { model.fmt }

    /// Alarm blink phase: toggles twice a second (the root redraws every 0.5 s).
    var blinkOn: Bool { Int(now.timeIntervalSinceReferenceDate * 2) % 2 == 0 }
    /// Colour that blinks off and on, like an alarm lamp.
    func blink(_ c: VFDColor) -> VFDColor { blinkOn ? c : .off }

    /// Alarm banner: alternates between a solid inverted block and an outlined one.
    mutating func alarmBanner(_ title: String, _ detail: String) {
        let lines = max(1, (b.width(detail) + 6) / max(1, width - 10) + 1)
        let h = 16 + lines * 10
        if blinkOn {
            b.fill(left, y, right, y + h, .red)
            b.text(left + 5, y + 4, title, maxCols: width - 10, .small, .off)
            b.paragraph(left + 5, y + 15, detail, maxCols: width - 10, .off)
        } else {
            b.box(left, y, right, y + h, .red)
            b.text(left + 5, y + 4, title, maxCols: width - 10, .small, .red)
            b.paragraph(left + 5, y + 15, detail, maxCols: width - 10, .red)
        }
        y += h + 6
    }
    var s: XenoSettings { model.settings }

    // MARK: Building blocks

    mutating func gap(_ n: Int = 6) { y += n }

    mutating func heading(_ t: String, _ color: VFDColor = .amber) {
        b.text(left, y, t.uppercased(), .small, color)
        y += 12
    }

    mutating func panel(_ color: VFDColor = .amber, _ content: (inout VFDPainter) -> Void) {
        let y0 = y
        y += 5
        content(&self)
        y += 3
        b.box(left, y0, right, y, color)
        y += 6
    }

    /// label …… value on one row, inside panels (inset 5).
    mutating func row(_ label: String, _ value: String, _ color: VFDColor = .white, tap: (() -> Void)? = nil) {
        b.text(left + 5, y, label.uppercased(), maxCols: width / 2, .small, .dim)
        b.textRight(right - 5, y, value, .small, color)
        if let tap { b.hit(left, y - 2, right, y + 8, tap) }
        y += 10
    }

    /// Inverted button. Returns nothing; registers the tap.
    mutating func button(_ t: String, color: VFDColor = .amber, inverted: Bool = true, _ action: @escaping () -> Void) {
        let w = b.width(t) + 10
        if inverted {
            b.fill(left, y, left + w, y + 13, color)
            b.text(left + 5, y + 3, t, .small, .off)
        } else {
            b.box(left, y, left + w, y + 13, color)
            b.text(left + 5, y + 3, t, .small, color)
        }
        b.hit(left, y - 2, left + w, y + 15, action)
        y += 19
    }

    /// Option chips in a row: [A][B][C], selected inverted.
    mutating func options(_ items: [String], selected: Int, at c: Int? = nil, _ pick: @escaping (Int) -> Void) {
        var x = c ?? left
        for (i, t) in items.enumerated() {
            let w = b.width(t) + 10
            if i == selected { b.fill(x, y, x + w, y + 13, .amber); b.text(x + 5, y + 3, t, .small, .off) }
            else { b.box(x, y, x + w, y + 13, .dim); b.text(x + 5, y + 3, t, .small, .white) }
            b.hit(x, y - 2, x + w, y + 15) { pick(i) }
            x += w + 2
        }
        y += 19
    }

    /// [-] value [+]
    mutating func stepper(_ label: String, _ value: String, minus: @escaping () -> Void, plus: @escaping () -> Void, tapValue: (() -> Void)? = nil) {
        b.text(left + 5, y + 3, label.uppercased(), .small, .dim)
        let c1 = right - 5
        b.box(c1 - 12, y, c1, y + 13, .amber); b.text(c1 - 8, y + 3, "+", .small, .amber)
        b.hit(c1 - 16, y - 2, c1 + 4, y + 15, plus)
        let vEnd = c1 - 16
        b.textRight(vEnd, y + 3, value, .small, .white)
        let vStart = vEnd - b.width(value)
        b.box(vStart - 16, y, vStart - 4, y + 13, .amber); b.text(vStart - 12, y + 3, "-", .small, .amber)
        b.hit(vStart - 20, y - 2, vStart - 2, y + 15, minus)
        if let tapValue { b.hit(vStart - 2, y - 2, vEnd, y + 15, tapValue) }
        y += 17
    }

    /// Menu item with chevron.
    mutating func menu(_ title: String, _ subtitle: String = "", _ action: @escaping () -> Void) {
        b.text(left + 2, y, title.uppercased(), maxCols: width - 12, .small, .white)
        b.textRight(right - 2, y, ">", .small, .amber)
        if !subtitle.isEmpty { b.text(left + 2, y + 10, subtitle.uppercased(), maxCols: width - 12, .small, .dim) }
        let h = subtitle.isEmpty ? 10 : 20
        b.hit(left, y - 3, right, y + h, action)
        y += h + 2
        b.hline(left, right, y, .dim, step: 2)
        y += 5
    }

    // MARK: Values (live probe or manual entry)

    func display(_ role: ProbeRole, humidity: Bool = false) -> String {
        let v = humidity ? model.inputRH(role) : model.input(role)
        guard let v else { return "--" }
        if humidity { return v.formatted(decimals: 1) }
        switch role.kind {
        case .pressure: return fmt.pressure(v)
        case .vacuum: return fmt.vacuum(v)
        case .staticPressure: return fmt.stat(v)
        default: return fmt.temp(v)
        }
    }

    func unit(_ role: ProbeRole, humidity: Bool = false) -> String {
        if humidity { return "%RH" }
        switch role.kind {
        case .pressure: return s.pressureUnit.rawValue.uppercased()
        case .vacuum: return s.vacuumUnit.rawValue.uppercased()
        case .staticPressure: return s.staticUnit.rawValue.uppercased()
        default: return s.temperatureUnit.rawValue
        }
    }

    /// Ask for a manual value when no probe is live for the role.
    func askManual(_ role: ProbeRole, humidity: Bool = false) {
        let model = self.model
        let s = self.s
        actions.ask("\(role.title)\(humidity ? " RH" : "") (\(unit(role, humidity: humidity)))", "") { v in
            if humidity { model.manualRH[role] = v; return }
            guard let v else { model.manual[role] = nil; return }
            switch role.kind {
            case .pressure: model.manual[role] = s.pressureUnit.toPsig(v)
            case .staticPressure: model.manual[role] = s.staticUnit.toInWC(v)
            case .vacuum: model.manual[role] = v / max(s.vacuumUnit.fromMicrons(1), 1e-12)
            default: model.manual[role] = s.temperatureUnit.toF(v)
            }
        }
    }

    func manualTap(_ role: ProbeRole) -> (() -> Void)? {
        if model.isLive(role) { return nil }
        let me = self
        return { me.askManual(role) }
    }

    /// Column: dim label, mid value below. Tap enters a manual value if no probe is live.
    mutating func column(_ c: Int, _ label: String, _ role: ProbeRole, color: VFDColor = .amber, humidity: Bool = false, maxCols: Int) {
        let live = humidity ? model.humidity(role) != nil : model.isLive(role)
        b.text(c, y, (label + " " + unit(role, humidity: humidity)).uppercased(), maxCols: maxCols, .small, .dim)
        b.text(c, y + 11, display(role, humidity: humidity), maxCols: maxCols, .mid, live ? color : .white)
        if !live {
            let me = self
            b.hit(c - 2, y - 2, c + maxCols, y + 30) { me.askManual(role, humidity: humidity) }
        }
    }

    mutating func valueColumn(_ c: Int, _ label: String, _ value: String, color: VFDColor = .white, maxCols: Int) {
        b.text(c, y, label.uppercased(), maxCols: maxCols, .small, .dim)
        b.text(c, y + 11, value, maxCols: maxCols, .mid, color)
    }

    var cols3: (Int, Int, Int, Int) {
        let inner = width - 10
        let w = inner / 3
        return (left + 5, left + 5 + w, left + 5 + 2 * w, w - 4)
    }

    // MARK: Tabs

    mutating func tab(_ t: AppTab) {
        switch t {
        case .probes: probes()
        case .charge: charge()
        case .tools: tools()
        case .jobs: jobs()
        case .settings: setup()
        }
    }

    mutating func route(_ r: VFDRoute, ptTempF: Double, cfm: Double, decayStart: Date?, decay: [TimedSample]) {
        switch r {
        case .refrigerants: refrigerants()
        case .probe(let key): probeDetail(key)
        case .vacuum: vacuum(decayStart: decayStart, decay: decay)
        case .pt: ptChart(ptTempF)
        case .targetSH: targetSH()
        case .staticP: staticPressure()
        case .airflow: airflow(cfm)
        }
    }

    // MARK: Probes

    mutating func probes() {
        let bt = model.bluetooth.state
        let status: String = model.settings.demoMode ? "* DEMO PROBES" : bt == .scanning ? "* SCANNING" : bt == .poweredOff ? "! BLUETOOTH OFF" : bt == .unauthorized ? "! NO BT PERMISSION" : "* STARTING"
        let btAlarm = !model.settings.demoMode && (bt == .poweredOff || bt == .unauthorized)
        b.box(left, y, right, y + 14, btAlarm ? .red : .dim)
        b.text(left + 5, y + 4, status, .small, btAlarm ? blink(.red) : .amber)
        b.textRight(right - 5, y + 4, "\(model.probes.probes.count) FOUND", .small, .dim)
        y += 20
        if model.probes.probes.isEmpty {
            y = b.paragraph(left, y + 4, "TURN ON YOUR FIELDPIECE JOB LINK PROBES. THEY APPEAR HERE AUTOMATICALLY. NO PAIRING NEEDED.", maxCols: width, .white)
            gap(8)
            let m = model
            button("DEMO PROBES") { m.setDemo(true) }
            return
        }
        let gutter = 3
        let w = (width - gutter) / 2
        for (i, p) in model.probes.probes.enumerated() {
            let c0 = left + (i % 2) * (w + gutter)
            if i % 2 == 0 && i > 0 { y += 62 }
            tile(p, c0: c0, r0: y, c1: c0 + w)
        }
        y += 62
    }

    mutating func tile(_ p: Probe, c0: Int, r0: Int, c1: Int) {
        let stale = p.isStale(now: now, after: s.staleSeconds)
        let roles = model.probes.roles(of: p)
        let main: VFDColor = stale ? .dim : .amber
        b.box(c0, r0, c1, r0 + 57, roles.isEmpty ? .dim : main)
        b.text(c0 + 4, r0 + 4, p.displayName.uppercased(), maxCols: c1 - c0 - 8, .small, stale ? .dim : .white)
        let pill = roles.first?.short ?? p.model
        let pw = b.width(pill) + 6
        b.fill(c0 + 4, r0 + 15, c0 + 4 + pw, r0 + 25, roles.isEmpty ? .dim : main)
        b.text(c0 + 7, r0 + 17, pill, .small, .off)
        let shown = p.readings.filter { $0.kind != .wetBulb && $0.kind != .dewPoint }
        if let r = shown.first {
            let (v, u) = fmt.reading(r)
            let e = b.text(c0 + 4, r0 + 30, v, .mid, main)
            b.text(e + 2, r0 + 37, u.uppercased(), maxCols: max(0, c1 - e - 6), .small, .dim)
        } else {
            b.text(c0 + 4, r0 + 34, p.category == .unknown ? "UNKNOWN MODEL" : "NO READING", .small, blink(.red))
        }
        var extra = ""
        if shown.count > 1 { let (v, u) = fmt.reading(shown[1]); extra = "\(v)\(u)" }
        else if let bat = p.battery { extra = "BAT \(bat)%" }
        let lowBattery = (p.battery ?? 100) < 20 && !stale
        if lowBattery { extra = "LOW BAT \(p.battery ?? 0)%" }
        if stale { extra = "OFFLINE" }
        b.text(c0 + 4, r0 + 48, extra.uppercased(), maxCols: c1 - c0 - 22, .small, stale || lowBattery ? blink(.red) : .dim)
        let level = stale ? 0 : p.rssi > -60 ? 4 : p.rssi > -70 ? 3 : p.rssi > -80 ? 2 : 1
        for bar in 0..<4 {
            let h = 2 + bar * 2
            b.fill(c1 - 13 + bar * 3, r0 + 54 - h, c1 - 12 + bar * 3, r0 + 54, bar < level ? main : .dim)
        }
        let a = actions, key = p.key
        b.hit(c0, r0, c1, r0 + 57) { a.push(.probe(key)) }
    }

    mutating func probeDetail(_ key: String) {
        guard let p = model.probes.probe(key) else { heading("PROBE NOT FOUND", .red); return }
        b.text(left, y, "\(p.vendor) \(p.model) ID \(p.serial)".uppercased(), maxCols: width, .small, .dim)
        y += 10
        b.text(left, y, "RSSI \(p.rssi)  \(p.battery.map { "BAT \($0)%" } ?? "")  \(p.packets) PKTS".uppercased(), .small, .dim)
        y += 14
        panel(.amber) { me in
            for r in p.readings {
                let (v, u) = me.fmt.reading(r)
                me.b.text(me.left + 5, me.y, r.label.uppercased(), .small, .dim)
                let e = me.b.text(me.left + 5, me.y + 10, v, .mid, .amber)
                me.b.text(e + 2, me.y + 17, u.uppercased(), .small, .dim)
                me.y += 30
            }
        }
        heading("ASSIGN TO POSITION")
        let store = model.probes
        for role in ProbeRole.allCases where p.readings.contains(where: { $0.kind == role.kind }) {
            let on = store.assignments[role]?.probeKey == p.key
            let label = p.readings.first { $0.kind == role.kind }?.label
            b.text(left + 2, y, on ? "[X]" : "[ ]", .small, on ? .amber : .dim)
            b.text(left + 26, y, role.title.uppercased(), .small, on ? .amber : .white)
            b.hit(left, y - 3, right, y + 9) { if on { store.assign(role, to: nil) } else { store.assign(role, to: p, label: label) } }
            y += 13
        }
        gap(4)
        heading("RAW BROADCAST")
        y = b.paragraph(left, y, p.raw.map { String(format: "%02X", $0) }.joined(separator: " "), maxCols: width, .dim)
        gap(6)
        let a = actions
        if p.readings.contains(where: { $0.kind == .pressure || $0.kind == .staticPressure }) {
            button("ZERO PRESSURE (OPEN TO AIR)") { store.zeroPressure(p) }
            if store.hasZero(p) { button("CLEAR ZERO", inverted: false) { store.clearZero(p) } }
        }
        button("FORGET PROBE", color: .red) { store.forget(p); a.pop() }
    }

    // MARK: Charge

    mutating func charge() {
        let res = model.chargeResult
        let m = model
        let a = actions
        // Refrigerant chip + metering.
        let chip = model.refrigerant.name + " v"
        let cw = b.width(chip) + 10
        b.box(left, y, left + cw, y + 13, .amber)
        b.text(left + 5, y + 3, chip, .small, .amber)
        b.hit(left, y - 2, left + cw, y + 15) { a.push(.refrigerants) }
        options(["TXV", "FIXED"], selected: s.metering == .txv ? 0 : 1, at: left + cw + 8) { i in m.settings.metering = i == 0 ? .txv : .fixed }
        gap(2)
        let (c1, c2, c3, cw3) = cols3
        let glide = model.refrigerant.hasGlide
        let tol = max(s.chargeTolerance, s.metering == .fixed ? 5 : s.chargeTolerance)
        // Low side
        panel(.amber) { me in
            me.b.text(me.left + 5, me.y, "* LOW SIDE - VAPOR", .small, .amber); me.y += 13
            me.column(c1, "SUCT", .suctionPressure, maxCols: cw3)
            me.valueColumn(c2, (glide ? "DEW " : "SAT ") + me.s.temperatureUnit.rawValue, me.fmt.temp(res.suctionSatF), maxCols: cw3)
            me.column(c3, "LINE", .suctionLine, color: .white, maxCols: cw3)
            me.y += 34
            me.hero("SUPERHEAT", res.superheatF, target: me.s.metering == .fixed ? res.targetSuperheatF : nil, tolerance: tol)
        }
        // High side
        panel(.amber) { me in
            me.b.text(me.left + 5, me.y, "^ HIGH SIDE - LIQUID", .small, .amber); me.y += 13
            me.column(c1, "LIQ", .liquidPressure, maxCols: cw3)
            me.valueColumn(c2, (glide ? "BUB " : "SAT ") + me.s.temperatureUnit.rawValue, me.fmt.temp(res.liquidSatF), maxCols: cw3)
            me.column(c3, "LINE", .liquidLine, color: .white, maxCols: cw3)
            me.y += 34
            me.hero("SUBCOOLING", res.subcoolF, target: me.s.metering == .txv ? res.targetSubcoolF : nil, tolerance: me.s.chargeTolerance)
            if me.s.metering == .txv {
                me.stepper("TARGET SC", me.fmt.delta(me.s.targetSubcool) + me.fmt.dUnit,
                           minus: { m.settings.targetSubcool = max(2, m.settings.targetSubcool - 0.5) },
                           plus: { m.settings.targetSubcool = min(25, m.settings.targetSubcool + 0.5) })
            }
        }
        // Diagnosis banner.
        let d = res.diagnosis
        let detail = d == .needsData ? "TAP -- TO ENTER A VALUE BY HAND" : d.detail.uppercased()
        if d != .needsData && !d.isGood {
            alarmBanner("! " + d.rawValue.uppercased(), detail)
        } else {
            let lines = max(1, (b.width(detail) + 6) / max(1, width - 10) + 1)
            let h = 16 + lines * 10
            if d == .needsData {
                b.box(left, y, right, y + h, .dim)
                b.text(left + 5, y + 4, d.rawValue.uppercased(), maxCols: width - 10, .small, .white)
                b.paragraph(left + 5, y + 15, detail, maxCols: width - 10, .dim)
            } else {
                b.fill(left, y, right, y + h, .amber)
                b.text(left + 5, y + 4, d.rawValue.uppercased(), maxCols: width - 10, .small, .off)
                b.paragraph(left + 5, y + 15, detail, maxCols: width - 10, .off)
            }
            y += h + 6
        }
        // Air side.
        let ret = model.air(.returnAir), sup = model.air(.supplyAir)
        panel(.dim) { me in
            me.b.text(me.left + 5, me.y, "~ AIR SIDE", .small, .amber); me.y += 13
            me.airRow("RETURN", .returnAir)
            me.airRow("SUPPLY", .supplyAir)
            me.row("OUTDOOR " + me.unit(.outdoorAir), me.display(.outdoorAir), m.isLive(.outdoorAir) ? .amber : .white,
                   tap: me.manualTap(.outdoorAir))
            me.row("RETURN WET BULB", me.fmt.temp(ret?.wetBulbF) + me.fmt.tUnit)
            if let r = m.input(.returnAir), let su = m.input(.supplyAir) { me.row("DELTA T", me.fmt.delta(r - su) + me.fmt.dUnit, .amber) }
            if let ret, let rdb = m.input(.returnAir) {
                me.row("TARGET DELTA T", me.fmt.delta(HVACCalc.targetCoolingDeltaT(returnDryBulbF: rdb, returnRH: ret.relativeHumidity)) + me.fmt.dUnit)
            }
            if let ret, let sup { me.row("ENTHALPY DROP", (ret.enthalpy - sup.enthalpy).formatted(decimals: 2) + " BTU/LB") }
            if me.s.metering == .fixed { me.row("TARGET SUPERHEAT", me.fmt.delta(res.targetSuperheatF) + me.fmt.dUnit) }
            if let cr = res.compressionRatio { me.row("COMPRESSION RATIO", cr.formatted(decimals: 2) + ":1") }
        }
        // Save.
        let saved = model.jobs.activeJob?.records.last.map { now.timeIntervalSince($0.date) < 4 } ?? false
        if saved {
            button("SAVED TO \(model.jobs.activeJob?.title.uppercased() ?? "JOB")", inverted: false) {}
        } else {
            let record = chargeRecord(res)
            button("SAVE TO JOB") { VFDPainter.save(record, model: m) }
        }
    }

    mutating func airRow(_ label: String, _ role: ProbeRole) {
        let m = model, me = self
        let db = display(role), rh = display(role, humidity: true)
        b.text(left + 5, y, label, .small, .dim)
        b.textRight(right - 5, y, "\(db)\(s.temperatureUnit.rawValue)  \(rh)%RH", .small, m.isLive(role) ? .amber : .white)
        if !m.isLive(role) {
            b.hit(left, y - 2, (left + right) / 2 + 20, y + 8) { me.askManual(role) }
            b.hit((left + right) / 2 + 21, y - 2, right, y + 8) { me.askManual(role, humidity: true) }
        }
        y += 10
    }

    /// Big readout with target and LED bar.
    mutating func hero(_ title: String, _ valueF: Double?, target: Double?, tolerance: Double) {
        let tu = s.temperatureUnit
        b.text(left + 5, y, title, .small, .dim)
        b.textRight(right - 5, y, target.map { "TARGET " + fmt.delta($0) } ?? "TARGET --", .small, .dim)
        y += 11
        var color: VFDColor = .amber
        var alarm = false
        if let v = valueF, let t = target, abs(v - t) > tolerance * 2 { color = .red; alarm = true }
        let e = b.text(left + 5, y, valueF.map { tu.deltaFromF($0).formatted(decimals: 1) } ?? "--", .big,
                       valueF == nil ? .dim : (alarm ? blink(color) : color))
        b.text(e + 2, y + 15, fmt.dUnit, .small, .dim)
        let span = max(tolerance * 5, 10)
        let marker = (valueF != nil && target != nil) ? (valueF! - target!) / span * 0.5 + 0.5 : nil
        b.bar(max(e + 14, left + width / 2 - 10), right - 6, y + 14, marker: marker, zone: 0.35...0.65, color: color)
        y += 30
    }

    func chargeRecord(_ res: ChargeResult) -> JobRecord {
        let f = fmt
        return JobRecord(title: "Charge check", values: [
            .init(label: "Refrigerant", value: model.refrigerant.name),
            .init(label: "Metering", value: s.metering.rawValue),
            .init(label: "Suction pressure", value: "\(f.pressure(model.input(.suctionPressure))) \(f.pUnit)"),
            .init(label: "Suction sat (dew)", value: "\(f.temp(res.suctionSatF)) \(f.tUnit)"),
            .init(label: "Suction line", value: "\(f.temp(model.input(.suctionLine))) \(f.tUnit)"),
            .init(label: "Superheat", value: "\(f.delta(res.superheatF)) \(f.dUnit)"),
            .init(label: "Liquid pressure", value: "\(f.pressure(model.input(.liquidPressure))) \(f.pUnit)"),
            .init(label: "Liquid sat (bubble)", value: "\(f.temp(res.liquidSatF)) \(f.tUnit)"),
            .init(label: "Liquid line", value: "\(f.temp(model.input(.liquidLine))) \(f.tUnit)"),
            .init(label: "Subcooling", value: "\(f.delta(res.subcoolF)) \(f.dUnit)"),
        ], verdict: res.diagnosis.rawValue, verdictGood: res.diagnosis.isGood)
    }

    static func save(_ record: JobRecord, model: AppModel) {
        if let job = model.jobs.activeJob {
            model.jobs.add(record, to: job.id)
        } else {
            var job = Job()
            job.equipment.refrigerant = model.settings.refrigerant
            job.equipment.metering = model.settings.metering
            let j = model.jobs.create(job)
            model.jobs.add(record, to: j.id)
        }
    }

    // MARK: Tools

    mutating func tools() {
        let a = actions
        menu("Evacuation", "Micron gauge, decay test") { a.push(.vacuum) }
        menu("P/T chart", "\(Refrigerants.all.count) refrigerants") { a.push(.pt) }
        menu("Target superheat", "Fixed orifice charging") { a.push(.targetSH) }
        menu("Static pressure", "TESP, rated max") { a.push(.staticP) }
        menu("Airflow & capacity", "Delta T, enthalpy, BTU/h") { a.push(.airflow) }
        menu("Pressure test", "Nitrogen standing test") { a.fallback(.pressure) }
        menu("Psychrometrics", "WB, DP, grains, enthalpy") { a.fallback(.psychro) }
        menu("Furnace airflow", "Temperature rise") { a.fallback(.furnace) }
        menu("Weigh-in charge", "Scale, line-set adjust") { a.fallback(.weighin) }
        menu("Electrical", "Capacitors, motor amps") { a.fallback(.electrical) }
        menu("Converter", "Pressure, vacuum, capacity") { a.fallback(.convert) }
        menu("Duct airflow", "Velocity x area") { a.fallback(.duct) }
        menu("Leak rate", "EPA 608 annualized") { a.fallback(.leak) }
        menu("Data logger", "Graph every probe") { a.fallback(.logger) }
        menu("Debug capture", "Zip & email probe data") { a.fallback(.debug) }
        menu("Probe lab", "Raw broadcasts, layouts") { a.fallback(.lab) }
        menu("BLE explorer", "Any probe, any brand") { a.fallback(.explorer) }
    }

    mutating func refrigerants() {
        let m = model, a = actions
        for r in Refrigerants.all {
            let sel = r.name == s.refrigerant
            if sel { b.fill(left, y - 2, right, y + 8, .amber) }
            b.text(left + 3, y, r.name, .small, sel ? .off : .white)
            b.text(left + 3 + 13 * 6, y, (r.safetyClass + (r.hasGlide ? " GLIDE" : "")), .small, sel ? .off : .dim)
            let name = r.name
            b.hit(left, y - 3, right, y + 9) { m.settings.refrigerant = name; a.pop() }
            y += 12
        }
    }

    mutating func vacuum(decayStart: Date?, decay: [TimedSample]) {
        let microns = model.input(.vacuum)
        let color: VFDColor = microns.map { $0 <= s.vacuumTarget ? .amber : $0 <= 1500 ? .white : .red } ?? .dim
        panel(color == .dim ? .dim : .amber) { me in
            me.b.text(me.left + 5, me.y, "VACUUM " + me.s.vacuumUnit.rawValue.uppercased(), .small, .dim); me.y += 11
            me.b.text(me.left + 5, me.y, me.fmt.vacuum(microns), .big, color)
            if !me.model.isLive(.vacuum) { let x = me; me.b.hit(me.left, me.y - 2, me.right, me.y + 28) { x.askManual(.vacuum) } }
            me.y += 30
            let pos = microns.map { (log10(max(50, min(25000, $0))) - log10(50)) / (log10(25000) - log10(50)) }
            let zone = 0.0...((log10(max(50, me.s.vacuumTarget)) - log10(50)) / (log10(25000) - log10(50)))
            me.b.bar(me.left + 5, me.right - 5, me.y + 2, marker: pos, zone: zone, color: color == .dim ? .amber : color)
            me.y += 9
            me.b.text(me.left + 5, me.y, "50", .small, .dim)
            me.b.textRight(me.right - 5, me.y, "25K", .small, .dim)
            me.y += 12
            let hist = me.model.probes.history(.vacuum).filter { $0.t > me.now.addingTimeInterval(-60) }
            me.row("TARGET", me.fmt.vacuum(me.s.vacuumTarget) + " " + me.s.vacuumUnit.rawValue.uppercased())
            me.row("RISE RATE", max(0, VacuumAnalysis.rate(hist)).formatted(decimals: 0) + " µ/MIN")
        }
        heading("PULLDOWN 30 MIN")
        let hist = model.probes.history(.vacuum).filter { $0.t > now.addingTimeInterval(-1800) }.map { s.vacuumUnit.fromMicrons($0.value) }
        b.chart(left, y, right - 2, y + 60, values: hist, threshold: s.vacuumUnit.fromMicrons(s.vacuumTarget), log: true)
        y += 68
        heading("DECAY TEST")
        let a = actions
        if let start = decayStart {
            let verdict = VacuumAnalysis.verdict(samples: decay, limit: s.vacuumDecayLimit, holdSeconds: s.vacuumHoldMinutes * 60)
            let el = Int(now.timeIntervalSince(start))
            let failed = verdict == .leak || verdict == .moisture
            panel(verdict == .pass ? .amber : verdict == .running ? .dim : (failed ? blink(.red) : .red)) { me in
                me.row("ELAPSED", String(format: "%d:%02d", el / 60, el % 60), .amber)
                me.row("RISE", ((decay.last?.value ?? 0) - (decay.first?.value ?? 0)).formatted(decimals: 0) + " µ")
                me.y = me.b.paragraph(me.left + 5, me.y + 2, verdict.rawValue.uppercased(), maxCols: me.width - 10,
                                      verdict == .pass ? .amber : verdict == .running ? .white : me.blink(.red))
                me.b.chart(me.left + 5, me.y + 2, me.right - 5, me.y + 40, values: decay.map(\.value), threshold: me.s.vacuumDecayLimit)
                me.y += 46
            }
            let m = model, d = decay
            button("STOP", color: .red) { a.stopDecay() }
            button("SAVE TO JOB") {
                VFDPainter.save(JobRecord(title: "Evacuation decay test", values: [
                    .init(label: "Start", value: "\(Int(d.first?.value ?? 0)) microns"),
                    .init(label: "End", value: "\(Int(d.last?.value ?? 0)) microns"),
                    .init(label: "Duration", value: String(format: "%d:%02d", el / 60, el % 60)),
                ], verdict: verdict.rawValue, verdictGood: verdict == .pass, series: d, seriesLabel: "microns"), model: m)
            }
        } else {
            y = b.paragraph(left, y, "ISOLATE THE PUMP, THEN START. PASSES IF IT HOLDS UNDER \(Int(s.vacuumDecayLimit)) MICRONS FOR \(Int(s.vacuumHoldMinutes)) MIN.", maxCols: width, .dim)
            gap(4)
            if microns != nil { button("START DECAY TEST") { a.startDecay() } }
        }
    }

    mutating func ptChart(_ tempF: Double) {
        let r = model.refrigerant, a = actions, atm = s.atmPsia
        let chip = r.name + " v"
        let cw = b.width(chip) + 10
        b.box(left, y, left + cw, y + 13, .amber); b.text(left + 5, y + 3, chip, .small, .amber)
        b.hit(left, y - 2, left + cw, y + 15) { a.push(.refrigerants) }
        b.text(left + cw + 8, y + 3, r.safetyClass + (r.hasGlide ? " GLIDE" : ""), .small, .dim)
        y += 20
        let t = min(max(tempF, r.minF), r.maxF)
        panel(.amber) { me in
            me.stepper("SAT TEMP", me.fmt.temp(t) + me.fmt.tUnit, minus: { a.setPT(t - 1) }, plus: { a.setPT(t + 1) },
                       tapValue: { a.ask("Temperature (°F)", "", { v in if let v { a.setPT(v) } }) })
            me.b.text(me.left + 5, me.y, (r.hasGlide ? "DEW " : "") + me.fmt.pUnit.uppercased(), .small, .dim)
            if r.hasGlide { me.b.text(me.left + 5 + me.width / 2, me.y, "BUBBLE " + me.fmt.pUnit.uppercased(), .small, .dim) }
            me.y += 11
            me.b.text(me.left + 5, me.y, me.fmt.pressure(r.satPsig(tempF: t, side: .dew, atmPsia: atm)), .mid, .amber)
            if r.hasGlide { me.b.text(me.left + 5 + me.width / 2, me.y, me.fmt.pressure(r.satPsig(tempF: t, side: .bubble, atmPsia: atm)), .mid, .white) }
            me.y += 24
        }
        heading("TABLE")
        let start = Int((max(-40, r.minF) / 5).rounded(.up)) * 5
        for tt in stride(from: start, through: Int(min(150, r.maxF)), by: 5) {
            let hl = abs(Double(tt) - t) < 2.5
            if hl { b.fill(left, y - 2, right, y + 8, .amber) }
            let fg: VFDColor = hl ? .off : .white
            b.text(left + 3, y, fmt.temp(Double(tt)), .small, fg)
            b.textRight(left + width / 2 + 20, y, fmt.pressure(r.satPsig(tempF: Double(tt), side: .dew, atmPsia: atm)), .small, hl ? .off : .amber)
            if r.hasGlide { b.textRight(right - 3, y, fmt.pressure(r.satPsig(tempF: Double(tt), side: .bubble, atmPsia: atm)), .small, fg) }
            let v = Double(tt)
            b.hit(left, y - 3, right, y + 9) { a.setPT(v) }
            y += 12
        }
    }

    mutating func targetSH() {
        let ret = model.air(.returnAir), od = model.input(.outdoorAir)
        let target = (ret != nil && od != nil) ? HVACCalc.targetSuperheat(indoorWetBulbF: ret!.wetBulbF, outdoorDryBulbF: od!) : nil
        let actual = model.chargeResult.superheatF
        panel(.dim) { me in
            me.airRow("INDOOR", .returnAir)
            me.row("INDOOR WET BULB", me.fmt.temp(ret?.wetBulbF) + me.fmt.tUnit)
            me.row("OUTDOOR " + me.unit(.outdoorAir), me.display(.outdoorAir), me.model.isLive(.outdoorAir) ? .amber : .white,
                   tap: me.manualTap(.outdoorAir))
        }
        panel(.amber) { me in
            me.hero("SUPERHEAT", actual, target: target, tolerance: 5)
            if ret != nil && od != nil && target == nil {
                me.y = me.b.paragraph(me.left + 5, me.y, "OUTSIDE THE CHART: CHARGE BY WEIGHT.", maxCols: me.width - 10, .red)
            } else if let target, let actual {
                let msg = actual > target + 5 ? "HIGH: ADD REFRIGERANT" : actual < target - 5 ? "LOW: RECOVER REFRIGERANT" : "ON TARGET"
                me.b.text(me.left + 5, me.y, msg, .small, abs(actual - target) <= 5 ? .amber : me.blink(.red)); me.y += 12
            }
        }
        y = b.paragraph(left, y, "FIXED ORIFICE ONLY. (3 X INDOOR WB - 80 - OUTDOOR DB) / 2.", maxCols: width, .dim)
    }

    mutating func staticPressure() {
        let sup = model.input(.staticSupply), ret = model.input(.staticReturn)
        let tesp = (sup != nil && ret != nil) ? HVACCalc.tesp(supplyInWC: sup!, returnInWC: ret!) : nil
        let rated = 0.5
        let (c1, c2, _, cw3) = cols3
        panel(.amber) { me in
            me.column(c1, "SUPPLY", .staticSupply, maxCols: cw3 + 20)
            me.column(c2 + 20, "RETURN", .staticReturn, color: .white, maxCols: cw3 + 20)
            me.y += 34
            me.b.text(me.left + 5, me.y, "TOTAL EXTERNAL STATIC " + me.s.staticUnit.rawValue.uppercased(), .small, .dim); me.y += 11
            let color: VFDColor = tesp.map { $0 <= rated ? .amber : .red } ?? .dim
            me.b.text(me.left + 5, me.y, me.fmt.stat(tesp), .big, color == .red ? me.blink(.red) : color)
            me.y += 30
            me.b.bar(me.left + 5, me.right - 5, me.y, marker: tesp.map { min(1, $0 / (rated * 2)) }, zone: 0...0.5, color: color == .dim ? .amber : color)
            me.y += 8
            me.row("RATED MAX", me.fmt.stat(rated) + " " + me.s.staticUnit.rawValue.uppercased())
            if let tesp {
                me.b.text(me.left + 5, me.y, tesp <= rated ? "WITHIN RATING" : "! OVER RATED: CHECK FILTER, COIL, DUCTS", maxCols: me.width - 10, .small, tesp <= rated ? .amber : me.blink(.red))
                me.y += 12
            }
        }
    }

    mutating func airflow(_ cfm: Double) {
        let ret = model.air(.returnAir), sup = model.air(.supplyAir), a = actions
        panel(.dim) { me in
            me.airRow("RETURN", .returnAir)
            me.airRow("SUPPLY", .supplyAir)
        }
        panel(.amber) { me in
            me.stepper("AIRFLOW CFM", String(Int(cfm)), minus: { a.setCFM(cfm - 50) }, plus: { a.setCFM(cfm + 50) },
                       tapValue: { a.ask("Airflow (CFM)", "", { v in if let v { a.setCFM(v) } }) })
            guard let ret, let sup else {
                me.b.text(me.left + 5, me.y, "NEED RETURN & SUPPLY DB + RH", .small, .dim); me.y += 12; return
            }
            let dT = ret.dryBulbF - sup.dryBulbF
            let total = HVACCalc.totalBTUh(cfm: cfm, deltaEnthalpy: ret.enthalpy - sup.enthalpy, psia: me.s.atmPsia)
            let sens = HVACCalc.sensibleBTUh(cfm: cfm, deltaTF: dT, psia: me.s.atmPsia)
            me.b.text(me.left + 5, me.y, "TOTAL CAPACITY KBTU/H", .small, .dim); me.y += 11
            me.b.text(me.left + 5, me.y, (total / 1000).formatted(decimals: 1), .big, .amber); me.y += 30
            me.row("TONS DELIVERED", (total / 12000).formatted(decimals: 2), .amber)
            me.row("DELTA T", me.fmt.delta(dT) + me.fmt.dUnit)
            me.row("TARGET DELTA T", me.fmt.delta(HVACCalc.targetCoolingDeltaT(returnDryBulbF: ret.dryBulbF, returnRH: ret.relativeHumidity)) + me.fmt.dUnit)
            me.row("SENSIBLE", (sens / 1000).formatted(decimals: 1) + " KBTU/H")
            me.row("LATENT", ((total - sens) / 1000).formatted(decimals: 1) + " KBTU/H")
            me.row("SENSIBLE HEAT RATIO", total > 0 ? (sens / total).formatted(decimals: 2) : "--")
            me.row("MOISTURE REMOVED", (ret.grainsPerLb - sup.grainsPerLb).formatted(decimals: 1) + " GR/LB")
        }
    }

    // MARK: Jobs

    mutating func jobs() {
        let m = model, a = actions
        button("+ NEW JOB") {
            var job = Job()
            job.equipment.refrigerant = m.settings.refrigerant
            job.equipment.metering = m.settings.metering
            let j = m.jobs.create(job)
            a.openJob(j.id)
        }
        if model.jobs.jobs.isEmpty {
            y = b.paragraph(left, y + 4, "NO JOBS YET. CREATE ONE TO KEEP CUSTOMER, EQUIPMENT AND MEASUREMENTS TOGETHER AND SEND A PDF REPORT.", maxCols: width, .dim)
        }
        for job in model.jobs.jobs {
            let active = job.id == model.jobs.activeJobID
            b.text(left + 2, y, job.title.uppercased(), maxCols: width - 60, .small, active ? .amber : .white)
            if active { b.textRight(right - 12, y, "ACTIVE", .small, .amber) }
            b.textRight(right - 2, y, ">", .small, .amber)
            b.text(left + 2, y + 10, "\(job.records.count) RECORDS  \(job.equipment.refrigerant)".uppercased(), maxCols: width - 12, .small, .dim)
            let id = job.id
            b.hit(left, y - 3, right, y + 19) { a.openJob(id) }
            y += 22
            b.hline(left, right, y, .dim, step: 2)
            y += 5
        }
    }

    // MARK: Setup

    mutating func setup() {
        let m = model, a = actions
        heading("APPEARANCE")
        options(["BIOLUMINESCENT", "VFD"], selected: s.theme == .vfd ? 1 : 0) { i in m.settings.theme = i == 0 ? .biolume : .vfd }
        gap(2)
        heading("DISPLAY COLOR")
        let tints = VFDTint.allCases
        let sw = (width - (tints.count - 1) * 3) / tints.count
        for (i, t) in tints.enumerated() {
            let c0 = left + i * (sw + 3)
            if t == s.vfdTint {
                b.box(c0, y, c0 + sw, y + 15, .white)
                b.fill(c0 + 2, y + 2, c0 + sw - 2, y + 13, .tint(i))
            } else {
                b.fill(c0, y, c0 + sw, y + 15, .tint(i))
            }
            b.hit(c0 - 1, y - 2, c0 + sw + 1, y + 17) { m.settings.vfdTint = t }
        }
        y += 20
        b.text(left, y, s.vfdTint.title + " - " + s.vfdTint.subtitle, maxCols: width, .small, .amber)
        y += 14
        heading("UNITS")
        panel(.dim) { me in
            func cycle<T: CaseIterable & Equatable>(_ v: T) -> T {
                let all = Array(T.allCases); let i = all.firstIndex(of: v) ?? 0; return all[(i + 1) % all.count]
            }
            me.row("TEMPERATURE", me.s.temperatureUnit.rawValue, .amber) { m.settings.temperatureUnit = cycle(m.settings.temperatureUnit) }
            me.row("PRESSURE", me.s.pressureUnit.rawValue.uppercased(), .amber) { m.settings.pressureUnit = cycle(m.settings.pressureUnit) }
            me.row("VACUUM", me.s.vacuumUnit.rawValue.uppercased(), .amber) { m.settings.vacuumUnit = cycle(m.settings.vacuumUnit) }
            me.row("STATIC", me.s.staticUnit.rawValue.uppercased(), .amber) { m.settings.staticUnit = cycle(m.settings.staticUnit) }
        }
        heading("SITE")
        panel(.dim) { me in
            me.stepper("ALTITUDE FT", String(Int(me.s.altitudeFt)),
                       minus: { m.settings.altitudeFt = max(0, m.settings.altitudeFt - 500) },
                       plus: { m.settings.altitudeFt = min(14000, m.settings.altitudeFt + 500) })
            me.row("BAROMETRIC", me.s.atmPsia.formatted(decimals: 2) + " PSIA")
        }
        heading("PROBES")
        panel(.dim) { me in
            me.row("DEMO PROBES", me.s.demoMode ? "ON" : "OFF", me.s.demoMode ? .amber : .white) { m.setDemo(!m.settings.demoMode) }
            me.row("AUTO-ASSIGN", me.s.autoAssign ? "ON" : "OFF", me.s.autoAssign ? .amber : .white) { m.settings.autoAssign.toggle() }
            me.row("KEEP SCREEN ON", me.s.keepAwake ? "ON" : "OFF", me.s.keepAwake ? .amber : .white) { m.settings.keepAwake.toggle() }
            me.row("CLEAR ASSIGNMENTS", ">", .red) { m.probes.assignments = [:] }
        }
        menu("Debug capture", "Zip & email probe data") { a.fallback(.debug) }
        menu("Probe lab") { a.fallback(.lab) }
        menu("All settings", "Report header, evacuation, more") { a.fallback(.settingsFull) }
        gap(4)
        y = b.paragraph(left, y, "XENO \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "")). NO SUBSCRIPTION, EVER. NOT AFFILIATED WITH FIELDPIECE.", maxCols: width, .dim)
    }
}
