import SwiftUI

/// Raw broadcast inspector and decoder editor: compare bytes with the probe's own display and
/// correct the mapping in the field.
struct ProbeLabView: View {
    @Environment(AppModel.self) private var model
    @State private var exportURL: URL?
    @State private var importText = ""
    @State private var showImport = false

    var body: some View {
        @Bindable var lab = model.lab
        List {
            Section {
                Toggle("Record every packet", isOn: $lab.recording)
                Toggle("Show non-Fieldpiece devices", isOn: $lab.showAllVendors)
                HStack {
                    Text("Adverts/sec").foregroundStyle(Theme.textDim)
                    Spacer()
                    Text(model.bluetooth.advertsPerSecond.formatted(decimals: 1)).monospacedDigit()
                }
                if !lab.log.isEmpty { Text("\(lab.log.count) packets recorded").font(Theme.font(.caption)).foregroundStyle(Theme.textDim) }
            } footer: {
                Text("Fieldpiece Job Link probes broadcast their readings; Xeno decodes them without pairing. If a reading doesn't match the probe's display, open the probe type below and adjust the field mapping.")
            }

            Section("Live packets") {
                if lab.latest.isEmpty { Text("Waiting for broadcasts…").foregroundStyle(Theme.textDim) }
                ForEach(lab.latest.sorted { $0.key < $1.key }, id: \.key) { entry in
                    let p = entry.value
                    let isFP = FieldpieceDecoder.isFieldpiece(p.bytes)
                    let type = isFP ? (String(bytes: p.bytes[2...3], encoding: .ascii) ?? "??") : ""
                    NavigationLink {
                        if isFP { LayoutEditorView(typeCode: type, sample: p.bytes) } else { RawBytesView(packet: p) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(isFP ? "\(model.lab.layout(for: type)?.model ?? "Unknown") (\(type))" : (p.name ?? "Unnamed device"))
                                    .font(Theme.font(.subheadline, weight: .semibold))
                                if isFP && model.lab.overrides[type] != nil { StatusPill(text: "CUSTOM", color: Theme.nebula) }
                                Spacer()
                                Text("\(p.rssi) dBm").font(Theme.font(.caption2)).foregroundStyle(Theme.textDim)
                            }
                            Text(p.hex).font(.system(.caption2, design: .monospaced)).foregroundStyle(Theme.alien).lineLimit(2)
                        }
                    }
                }
            }

            Section("Decoder layouts") {
                ForEach(FieldpieceLayouts.builtIn.keys.sorted(), id: \.self) { code in
                    NavigationLink {
                        LayoutEditorView(typeCode: code, sample: lab.latest.values.first { $0.bytes.count > 3 && String(bytes: $0.bytes[2...3], encoding: .ascii) == code }?.bytes ?? [])
                    } label: {
                        HStack {
                            Text(model.lab.layout(for: code)?.model ?? code)
                            Spacer()
                            Text(code).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.textDim)
                            if lab.overrides[code] != nil { StatusPill(text: "CUSTOM", color: Theme.nebula) }
                        }
                    }
                }
                Button("Import layouts (JSON)") { showImport = true }
                ShareLink("Export my layouts", item: lab.exportLayouts())
            }

            Section {
                NavigationLink { DebugCaptureView() } label: { Label("Debug capture → zip & email", systemImage: "ladybug") }
                Button("Export packet log (CSV)") { exportURL = writeCSV() }
                if let exportURL { ShareLink("Share log", item: exportURL) }
                Button("Clear", role: .destructive) { lab.clear() }
            }
        }
        .xenoScreen()
        .navigationTitle("Probe Lab")
        .alert("Import layouts", isPresented: $showImport) {
            TextField("Paste JSON", text: $importText)
            Button("Import") { _ = model.lab.importLayouts(importText) }
            Button("Cancel", role: .cancel) {}
        }
    }

    func writeCSV() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xeno-packets.csv")
        try? model.lab.csv().write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

struct RawBytesView: View {
    let packet: ProbeLab.Packet
    var body: some View {
        List {
            Section("Packet") {
                Text(packet.hex).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            }
            ByteTable(bytes: packet.bytes)
        }
        .xenoScreen()
        .navigationTitle(packet.name ?? "Device")
    }
}

/// Every offset interpreted a few ways, so a value seen on the probe's display can be found.
struct ByteTable: View {
    let bytes: [UInt8]
    var body: some View {
        Section("Interpretations (offset: u8 · int16 LE ÷10 · ÷100)") {
            ForEach(0..<bytes.count, id: \.self) { i in
                HStack(spacing: 10) {
                    Text(String(format: "%2d", i)).foregroundStyle(Theme.textDim).frame(width: 24, alignment: .trailing)
                    Text(String(format: "%02X", bytes[i])).foregroundStyle(Theme.alien)
                    Text("\(bytes[i])").frame(width: 34, alignment: .trailing)
                    if i + 1 < bytes.count {
                        let v = Int16(bitPattern: UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8)
                        Text((Double(v) / 10).formatted(decimals: 1)).frame(width: 70, alignment: .trailing)
                        Text((Double(v) / 100).formatted(decimals: 2)).frame(width: 70, alignment: .trailing).foregroundStyle(Theme.textDim)
                    }
                }
                .font(.system(.caption, design: .monospaced))
            }
        }
    }
}

struct LayoutEditorView: View {
    @Environment(AppModel.self) private var model
    let typeCode: String
    let sample: [UInt8]
    @State private var layout = ModelLayout(typeCode: "", model: "", category: .unknown, fields: [], batteryOffset: nil, provenance: "")
    @State private var loaded = false
    @State private var saved = false

    var body: some View {
        List {
            Section {
                TextField("Model name", text: $layout.model)
                Picker("Category", selection: $layout.category) {
                    ForEach(ProbeCategory.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text(layout.provenance).font(Theme.font(.caption)).foregroundStyle(Theme.textDim)
            } header: { Text("Type \(typeCode)") }

            Section("Fields") {
                if layout.special == .clampMeter {
                    Text("Two-channel meter: decoded from value/range/mode bytes.").font(Theme.font(.caption)).foregroundStyle(Theme.textDim)
                }
                ForEach(layout.fields.indices, id: \.self) { i in
                    FieldEditor(field: $layout.fields[i], sample: sample)
                }
                .onDelete { layout.fields.remove(atOffsets: $0) }
                Button("Add field") { layout.fields.append(FieldLayout(label: "Value", kind: .temperature, offset: 13)) }
            }
            Section {
                Button(saved ? "Saved ✓" : "Save layout") {
                    layout.provenance = "Verified in the field on \(Date().formatted(date: .abbreviated, time: .omitted))."
                    model.lab.overrides[typeCode] = layout
                    saved = true
                }
                if model.lab.overrides[typeCode] != nil {
                    Button("Revert to built-in", role: .destructive) {
                        model.lab.overrides[typeCode] = nil
                        layout = FieldpieceLayouts.builtIn[typeCode] ?? blank
                    }
                }
            }
            if !sample.isEmpty {
                Section("Latest packet") {
                    Text(sample.map { String(format: "%02X", $0) }.joined(separator: " ")).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                ByteTable(bytes: sample)
            }
        }
        .xenoScreen()
        .navigationTitle("Layout \(typeCode)")
        .onAppear {
            if !loaded { layout = model.lab.layout(for: typeCode) ?? blank; loaded = true }
        }
    }

    var blank: ModelLayout {
        ModelLayout(typeCode: typeCode, model: "FP-\(typeCode)", category: .unknown, fields: [], batteryOffset: nil, provenance: "New layout.")
    }
}

struct FieldEditor: View {
    @Binding var field: FieldLayout
    let sample: [UInt8]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Label", text: $field.label).font(Theme.font(.headline))
                Spacer()
                if let v = field.value(in: sample) {
                    Text(v.formatted(decimals: 2) + " " + field.kind.canonicalUnit).foregroundStyle(Theme.alien).monospacedDigit()
                }
            }
            Picker("Measures", selection: $field.kind) { ForEach(SensorKind.allCases) { Text($0.title).tag($0) } }
            Stepper("Byte offset: \(field.offset)", value: $field.offset, in: 0...30)
            Picker("Encoding", selection: $field.encoding) { ForEach(FieldEncoding.allCases) { Text($0.rawValue).tag($0) } }
            Picker("Divide by", selection: $field.divisor) { Text("1").tag(1.0); Text("10").tag(10.0); Text("100").tag(100.0); Text("1000").tag(1000.0) }
                .pickerStyle(.segmented)
            Picker("Convert", selection: $field.transform) { ForEach(FieldTransform.allCases) { Text($0.rawValue).tag($0) } }
        }
        .font(Theme.font(.subheadline))
    }
}

struct ExplorerView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""

    var body: some View {
        List {
            if let g = model.bluetooth.gatt {
                Section("Connected: \(g.name)") {
                    NavigationLink("Open session log") { GATTView(session: g) }
                    Button("Disconnect", role: .destructive) { model.bluetooth.disconnectGATT() }
                }
            }
            Section("Nearby devices") {
                let devices = model.bluetooth.devices.values
                    .filter { filter.isEmpty || ($0.name ?? "").localizedCaseInsensitiveContains(filter) }
                    .sorted { $0.rssi > $1.rssi }
                ForEach(devices) { d in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(d.name ?? "Unnamed").font(Theme.font(.subheadline, weight: .semibold))
                            if FieldpieceDecoder.isFieldpiece(d.manufacturer) { StatusPill(text: "FIELDPIECE", color: Theme.alien) }
                            if (d.name ?? "").localizedCaseInsensitiveContains("NAVAC") { StatusPill(text: "NAVAC", color: Theme.beam) }
                            Spacer()
                            Text("\(d.rssi)").font(Theme.font(.caption)).foregroundStyle(Theme.textDim)
                        }
                        if !d.manufacturer.isEmpty {
                            Text(d.manufacturer.map { String(format: "%02X", $0) }.joined(separator: " ")).font(.system(.caption2, design: .monospaced)).foregroundStyle(Theme.alien).lineLimit(2)
                        }
                        if !d.services.isEmpty { Text(d.services.joined(separator: ", ")).font(Theme.font(.caption2)).foregroundStyle(Theme.textDim) }
                        if d.connectable {
                            Button("Connect & inspect GATT") { model.bluetooth.connect(d.id) }.font(Theme.font(.caption, weight: .semibold))
                        }
                    }
                }
            }
        }
        .searchable(text: $filter, prompt: "Filter by name")
        .xenoScreen()
        .navigationTitle("BLE explorer")
    }
}

struct GATTView: View {
    let session: GATTSession
    @State private var writeHex = ""
    @State private var target = ""

    var body: some View {
        List {
            Section("Characteristics") {
                ForEach(session.characteristics.values.sorted { $0.id < $1.id }) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.id).font(.system(.caption, design: .monospaced))
                        Text("\(c.properties) · service \(c.service)").font(Theme.font(.caption2)).foregroundStyle(Theme.textDim)
                        if !c.lastValue.isEmpty {
                            Text(c.lastValue.map { String(format: "%02X", $0) }.joined(separator: " ")).font(.system(.caption2, design: .monospaced)).foregroundStyle(Theme.alien)
                        }
                        HStack {
                            if c.properties.contains("read") { Button("Read") { session.read(c.id) } }
                            if c.properties.contains("write") { Button("Write…") { target = c.id } }
                        }
                        .font(Theme.font(.caption, weight: .semibold))
                        .buttonStyle(.borderless)
                    }
                }
            }
            if !target.isEmpty {
                Section("Write to \(target)") {
                    TextField("Hex bytes, e.g. 01 02", text: $writeHex).font(.system(.body, design: .monospaced))
                    Button("Send") { session.write(target, hex: writeHex) }
                }
            }
            Section("Log") {
                ForEach(session.lines.suffix(300).reversed()) { l in
                    Text(l.text).font(.system(.caption2, design: .monospaced))
                }
            }
        }
        .xenoScreen()
        .navigationTitle(session.connected ? "Connected" : "Connecting…")
    }
}
