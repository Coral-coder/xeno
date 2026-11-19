import Charts
import PhotosUI
import SwiftUI

struct JobsView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                if model.jobs.jobs.isEmpty {
                    VStack(spacing: 12) {
                        AlienGlyph(color: Theme.alien.opacity(0.6)).frame(width: 50)
                        Text("No jobs yet").font(.headline)
                        Text("Create a job to keep customer, equipment and measurements together and send a PDF report.")
                            .font(.caption).foregroundStyle(Theme.textDim).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
                    .listRowBackground(Color.clear)
                }
                ForEach(filtered) { job in
                    NavigationLink(value: job.id) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(job.title).font(.system(.headline, design: .rounded))
                                if job.id == model.jobs.activeJobID { StatusPill(text: "ACTIVE", color: Theme.alien) }
                            }
                            Text([job.address, job.equipment.refrigerant].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(Theme.textDim)
                            Text("\(job.records.count) records · \(job.created.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2).foregroundStyle(Theme.textDim)
                        }
                    }
                    .listRowBackground(Theme.spaceRaised.opacity(0.7))
                }
                .onDelete { idx in model.jobs.delete(idx.map { filtered[$0].id }) }
            }
            .searchable(text: $search)
            .xenoScreen()
            .navigationTitle("Jobs")
            .navigationDestination(for: UUID.self) { JobDetailView(jobID: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { _ = model.jobs.create(Job(equipment: Equipment(refrigerant: model.settings.refrigerant, metering: model.settings.metering))) } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
        }
    }

    var filtered: [Job] {
        search.isEmpty ? model.jobs.jobs : model.jobs.jobs.filter {
            $0.customer.localizedCaseInsensitiveContains(search) || $0.address.localizedCaseInsensitiveContains(search) || $0.workOrder.localizedCaseInsensitiveContains(search)
        }
    }
}

struct JobDetailView: View {
    @Environment(AppModel.self) private var model
    let jobID: UUID
    @State private var job = Job()
    @State private var loaded = false
    @State private var reportURL: URL?
    @State private var pickedPhotos: [PhotosPickerItem] = []

    var body: some View {
        Form {
            Section("Customer") {
                TextField("Name", text: $job.customer)
                TextField("Address", text: $job.address)
                TextField("Phone", text: $job.phone).keyboardType(.phonePad)
                TextField("Email", text: $job.email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                TextField("Work order #", text: $job.workOrder)
            }
            Section("Outdoor unit") {
                TextField("Make", text: $job.equipment.outdoorMake)
                TextField("Model", text: $job.equipment.outdoorModel)
                TextField("Serial", text: $job.equipment.outdoorSerial)
            }
            Section("Indoor unit") {
                TextField("Make", text: $job.equipment.indoorMake)
                TextField("Model", text: $job.equipment.indoorModel)
                TextField("Serial", text: $job.equipment.indoorSerial)
            }
            Section("System") {
                Picker("Refrigerant", selection: $job.equipment.refrigerant) {
                    ForEach(Refrigerants.all) { Text($0.name).tag($0.name) }
                }
                Picker("Metering", selection: $job.equipment.metering) {
                    ForEach(MeteringDevice.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("Tons", text: $job.equipment.tons).keyboardType(.decimalPad)
                TextField("SEER2", text: $job.equipment.seer).keyboardType(.decimalPad)
                TextField("Factory charge (lb/oz)", text: $job.equipment.factoryCharge)
            }
            Section("Notes") {
                TextEditor(text: $job.notes).frame(minHeight: 90)
            }
            Section("Photos") {
                if !job.photos.isEmpty {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(job.photos, id: \.self) { name in
                                if let img = UIImage(contentsOfFile: PhotoStore.url(name).path) {
                                    Image(uiImage: img).resizable().scaledToFill().frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 10))
                                        .contextMenu {
                                            Button("Delete photo", role: .destructive) { job.photos.removeAll { $0 == name }; PhotoStore.delete(name) }
                                        }
                                }
                            }
                        }
                    }
                }
                PhotosPicker(selection: $pickedPhotos, maxSelectionCount: 10, matching: .images) {
                    Label("Add nameplate / site photos", systemImage: "camera")
                }
                .onChange(of: pickedPhotos) { _, items in
                    Task {
                        for item in items {
                            if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data),
                               let jpg = img.jpegData(compressionQuality: 0.7), let name = PhotoStore.save(jpg) {
                                job.photos.append(name)
                            }
                        }
                        pickedPhotos = []
                    }
                }
            }
            Section("Measurements") {
                if job.records.isEmpty { Text("Use \"Save to job\" on the Charge screen and in Tools.").font(.caption).foregroundStyle(Theme.textDim) }
                ForEach(job.records) { r in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(r.title).font(.headline)
                            Spacer()
                            Text(r.date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(Theme.textDim)
                        }
                        if let v = r.verdict {
                            Text(v).font(.subheadline.weight(.semibold)).foregroundStyle(r.verdictGood == true ? Theme.alien : r.verdictGood == false ? Theme.danger : Theme.beam)
                        }
                        ForEach(r.values) { KeyValueRow(key: $0.label, value: $0.value) }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { idx in job.records.remove(atOffsets: idx) }
            }
            Section {
                Button(job.id == model.jobs.activeJobID ? "Active job ✓" : "Make active job") { model.jobs.activeJobID = job.id }
                Button { reportURL = ReportPDF.render(job: job, settings: model.settings) } label: { Label("Build PDF report", systemImage: "doc.richtext") }
                if let reportURL {
                    ShareLink(item: reportURL) { Label("Share report", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .xenoScreen()
        .navigationTitle(job.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !loaded, let j = model.jobs.jobs.first(where: { $0.id == jobID }) { job = j; loaded = true }
        }
        .onChange(of: job) { _, new in if loaded { model.jobs.update(new); reportURL = nil } }
        .onChange(of: model.jobs.jobs) { _, jobs in
            // Records saved from other screens while this one is open.
            if let j = jobs.first(where: { $0.id == jobID }), j.records.count != job.records.count { job.records = j.records }
        }
    }
}

/// Draws a customer report PDF with UIKit text layout.
enum ReportPDF {
    static func render(job: Job, settings: XenoSettings) -> URL? {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 40
        let safe = job.customer.isEmpty ? "Job" : job.customer.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Xeno-\(safe)-\(Int(Date().timeIntervalSince1970)).pdf")
        let green = UIColor(red: 0.05, green: 0.55, blue: 0.3, alpha: 1)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        do {
            try renderer.writePDF(to: url) { ctx in
                var y: CGFloat = 0
                func newPage() {
                    ctx.beginPage()
                    y = margin
                    UIColor(red: 0.02, green: 0.03, blue: 0.07, alpha: 1).setFill()
                    UIRectFill(CGRect(x: 0, y: 0, width: page.width, height: 6))
                }
                func ensure(_ h: CGFloat) { if y + h > page.height - margin { newPage() } }
                func text(_ s: String, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor = .black, x: CGFloat = margin, width: CGFloat? = nil, advance: Bool = true) {
                    let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
                    let w = width ?? page.width - margin - x
                    let rect = (s as NSString).boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
                    ensure(rect.height)
                    (s as NSString).draw(with: CGRect(x: x, y: y, width: w, height: rect.height), options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
                    if advance { y += rect.height + 2 }
                }
                func rule() {
                    ensure(10)
                    UIColor.lightGray.setFill(); UIRectFill(CGRect(x: margin, y: y + 4, width: page.width - 2 * margin, height: 0.5)); y += 10
                }
                func pair(_ k: String, _ v: String) {
                    guard !v.isEmpty else { return }
                    text(k, size: 10, color: .darkGray, x: margin, width: 180, advance: false)
                    text(v, size: 10, weight: .medium, x: margin + 190)
                }

                newPage()
                text(settings.companyName.isEmpty ? "HVAC Service Report" : settings.companyName, size: 22, weight: .bold)
                let sub = [settings.technician, settings.license.isEmpty ? "" : "Lic. \(settings.license)", settings.companyPhone].filter { !$0.isEmpty }.joined(separator: " · ")
                if !sub.isEmpty { text(sub, size: 10, color: .darkGray) }
                text("Generated \(Date().formatted(date: .long, time: .shortened)) with Xeno", size: 9, color: .gray)
                rule()
                text("Customer", size: 13, weight: .semibold, color: green)
                pair("Name", job.customer); pair("Address", job.address); pair("Phone", job.phone); pair("Email", job.email); pair("Work order", job.workOrder)
                y += 6
                text("Equipment", size: 13, weight: .semibold, color: green)
                let e = job.equipment
                pair("Outdoor", [e.outdoorMake, e.outdoorModel].filter { !$0.isEmpty }.joined(separator: " "))
                pair("Outdoor serial", e.outdoorSerial)
                pair("Indoor", [e.indoorMake, e.indoorModel].filter { !$0.isEmpty }.joined(separator: " "))
                pair("Indoor serial", e.indoorSerial)
                pair("Refrigerant", e.refrigerant); pair("Metering", e.metering.rawValue)
                pair("Size", e.tons.isEmpty ? "" : "\(e.tons) tons"); pair("SEER2", e.seer); pair("Factory charge", e.factoryCharge)
                rule()
                for r in job.records {
                    ensure(60)
                    text("\(r.title) · \(r.date.formatted(date: .abbreviated, time: .shortened))", size: 13, weight: .semibold, color: green)
                    if let v = r.verdict {
                        text(v, size: 11, weight: .bold, color: r.verdictGood == false ? .systemRed : r.verdictGood == true ? green : .black)
                    }
                    for v in r.values { pair(v.label, v.value) }
                    if let series = r.series, series.count > 2 {
                        ensure(110)
                        drawSeries(series, in: CGRect(x: margin, y: y + 4, width: page.width - 2 * margin, height: 90), label: r.seriesLabel ?? "")
                        y += 104
                    }
                    y += 8
                }
                if !job.photos.isEmpty {
                    rule()
                    text("Photos", size: 13, weight: .semibold, color: green)
                    var x = margin
                    for name in job.photos {
                        guard let img = UIImage(contentsOfFile: PhotoStore.url(name).path) else { continue }
                        let h: CGFloat = 160
                        let w = min(h * img.size.width / max(img.size.height, 1), page.width - 2 * margin)
                        if x + w > page.width - margin { x = margin; y += h + 8 }
                        ensure(h + 8)
                        img.draw(in: CGRect(x: x, y: y, width: w, height: h))
                        x += w + 8
                    }
                    y += 168
                }
                if !job.notes.isEmpty {
                    rule()
                    text("Notes", size: 13, weight: .semibold, color: green)
                    text(job.notes, size: 10)
                }
            }
            return url
        } catch {
            return nil
        }
    }

    private static func drawSeries(_ s: [TimedSample], in rect: CGRect, label: String) {
        guard let t0 = s.first?.t, let t1 = s.last?.t, t1 > t0 else { return }
        let lo = s.map(\.value).min() ?? 0, hi = s.map(\.value).max() ?? 1
        let span = max(hi - lo, 1)
        UIColor(white: 0.96, alpha: 1).setFill(); UIRectFill(rect)
        let path = UIBezierPath()
        for (i, p) in s.enumerated() {
            let x = rect.minX + CGFloat(p.t.timeIntervalSince(t0) / t1.timeIntervalSince(t0)) * rect.width
            let y = rect.maxY - CGFloat((p.value - lo) / span) * rect.height
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        UIColor(red: 0.05, green: 0.55, blue: 0.3, alpha: 1).setStroke()
        path.lineWidth = 1.5; path.stroke()
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.darkGray]
        ("\(Int(hi)) \(label)" as NSString).draw(at: CGPoint(x: rect.minX + 4, y: rect.minY + 2), withAttributes: attrs)
        ("\(Int(lo)) \(label)" as NSString).draw(at: CGPoint(x: rect.minX + 4, y: rect.maxY - 12), withAttributes: attrs)
    }
}
