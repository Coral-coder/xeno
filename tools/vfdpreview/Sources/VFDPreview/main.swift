import Foundation

// iPhone 17 Pro: 402 x 874 pt, 3x, cell = 5 px -> 241 x 524 cells; safe areas 62 / 34 pt.
let cols = 241, rows = 524, topInset = 38, bottomInset = 21, px = 5
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

UserDefaults.standard.removePersistentDomain(forName: "xeno")
let model = AppModel()
model.settings.theme = .vfd
model.settings.demoMode = true
model.demo.start()
var job = Job(); job.customer = "Sample Customer"; job.address = "123 Example St"
let j = model.jobs.create(job)
model.jobs.add(JobRecord(title: "Charge check", values: [], verdict: "ok", verdictGood: true), to: j.id)

let unlit: (UInt8, UInt8, UInt8) = (9, 9, 9)

func render(_ name: String, tab: AppTab, stack: [VFDRoute] = [], scroll: Int = 0, blinkOff: Bool = false) {
    let palette = model.settings.vfdTint.palette.mapValues { (UInt8($0.0 * 255), UInt8($0.1 * 255), UInt8($0.2 * 255)) }
    model.selectedTab = tab
    var st = VFDState(); st.stack = stack; st.scroll = scroll
    let b = VFDFrame.compose(model: model, state: st, cols: cols, rows: rows, topInset: topInset, bottomInset: bottomInset,
                             now: Date(timeIntervalSinceReferenceDate: blinkOff ? 0.5 : 0), actions: .none, select: { _ in })
    let w = cols * px, h = rows * px
    var data = [UInt8](repeating: 0, count: w * h * 3)
    for r in 0..<rows {
        for c in 0..<cols {
            let v = b.cells[r * cols + c]
            let rgb = v == 0 ? unlit : (palette[v] ?? unlit)
            for y in 0..<(px - 1) { for x in 0..<(px - 1) {
                let i = ((r * px + y) * w + c * px + x) * 3
                data[i] = rgb.0; data[i + 1] = rgb.1; data[i + 2] = rgb.2
            } }
        }
    }
    var file = Data("P6\n\(w) \(h)\n255\n".utf8)
    file.append(contentsOf: data)
    try! file.write(to: URL(fileURLWithPath: "\(out)/\(name).ppm"))
    print(name, "max scroll", b.maxScroll)
}

render("01-probes", tab: .probes)
render("02-charge", tab: .charge)
render("11-setup", tab: .settings)
// Alarm: subcooling far below target -> flashing banner and blinking hero value.
model.settings.targetSubcool = 20
render("20-alarm-on", tab: .charge)
render("21-alarm-off", tab: .charge, blinkOff: true)
model.settings.targetSubcool = 10
for t in VFDTint.allCases {
    model.settings.vfdTint = t
    render("3\(VFDTint.allCases.firstIndex(of: t)!)-tint-\(t.rawValue)", tab: .charge)
}
model.settings.vfdTint = .green
render("40-setup-green", tab: .settings)
