import MessageUI
import SwiftUI

/// Guided capture for a tech in the field: record packets, note what each probe's display
/// shows, then zip and email/share everything to the developer.
struct DebugCaptureView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("xeno.debugEmail") private var email = ""
    @State private var note = ""
    @State private var bundle: URL?
    @State private var error: String?
    @State private var mailing = false
    @State private var noting: Probe?
    @State private var displayText = ""

    var body: some View {
        @Bindable var lab = model.lab
        List {
            Section {
                Toggle("Recording packets", isOn: $lab.recording)
                Toggle("Include non-Fieldpiece devices", isOn: $lab.showAllVendors)
                Text("\(lab.log.count) packets · \(model.bluetooth.devices.count) devices · \(lab.notes.count) display notes")
                    .font(Theme.font(.caption)).foregroundStyle(Theme.textDim)
            } header: { Text("1 · Record") } footer: {
                Text("Turn recording on, switch the probes on and keep them near the phone. Change what they measure (warm a clamp in your hand, pressurise a probe) while recording.")
            }

            Section {
                if model.probes.probes.isEmpty { Text("No probes decoded yet. Raw packets are still being recorded.").font(Theme.font(.caption)).foregroundStyle(Theme.textDim) }
                ForEach(model.probes.probes) { p in
                    Button { noting = p; displayText = "" } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(p.displayName).foregroundStyle(Theme.text)
                                Text(p.readings.map { r in let (v, u) = model.fmt.reading(r); return "\(r.label) \(v) \(u)" }.joined(separator: " · "))
                                    .font(Theme.font(.caption2)).foregroundStyle(Theme.textDim)
                            }
                            Spacer()
                            Image(systemName: "square.and.pencil").foregroundStyle(Theme.alien)
                        }
                    }
                }
                ForEach(lab.notes.reversed()) { n in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(n.model) \(n.probe): display shows \"\(n.displayShows)\"").font(Theme.font(.caption))
                        Text(n.hex).font(Theme.mono(.caption2)).foregroundStyle(Theme.alien).lineLimit(2)
                    }
                }
            } header: { Text("2 · Note what the probe screen shows") } footer: {
                Text("Tap a probe and type exactly what its own display (or the Fieldpiece app) shows at that moment. A few notes at different readings let the developer verify the decoding.")
            }

            Section {
                TextField("What's wrong / what were you doing?", text: $note, axis: .vertical).lineLimit(3...6)
                TextField("Send to (email)", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                Button { build() } label: { Label("Build debug zip", systemImage: "doc.zipper") }
                if let bundle {
                    Text(bundle.lastPathComponent).font(Theme.font(.caption)).foregroundStyle(Theme.textDim)
                    if MFMailComposeViewController.canSendMail() {
                        Button { mailing = true } label: { Label("Email zip", systemImage: "envelope") }
                    }
                    ShareLink(item: bundle) { Label("Share zip (Mail, Messages, Files, AirDrop…)", systemImage: "square.and.arrow.up") }
                }
                if let error { Text(error).font(Theme.font(.caption)).foregroundStyle(Theme.danger) }
            } header: { Text("3 · Send") }

            Section {
                Button("Clear capture", role: .destructive) { lab.clear(); bundle = nil }
            }
        }
        .xenoScreen()
        .navigationTitle("Debug capture")
        .onAppear { model.lab.recording = true }
        .alert("What does \(noting?.displayName ?? "the probe") show?", isPresented: Binding(get: { noting != nil }, set: { if !$0 { noting = nil } })) {
            TextField("e.g. 118.4 psig, 72.1 °F", text: $displayText)
            Button("Save") {
                if let p = noting {
                    let decoded = p.readings.map { "\($0.label)=\($0.value.formatted(decimals: 2))\($0.kind.canonicalUnit)" }.joined(separator: " ")
                    model.lab.addNote(probe: p.serial, model: p.model, displayShows: displayText, bytes: p.raw, decoded: decoded)
                }
                noting = nil
            }
            Button("Cancel", role: .cancel) { noting = nil }
        }
        .sheet(isPresented: $mailing) {
            if let bundle {
                MailView(to: email, subject: "Xeno debug capture", body: note, attachment: bundle).ignoresSafeArea()
            }
        }
    }

    func build() {
        do { bundle = try DebugExport.makeBundle(model: model, technicianNote: note); error = nil }
        catch { self.error = "Couldn't build the zip: \(error.localizedDescription)" }
    }
}

struct MailView: UIViewControllerRepresentable {
    var to: String
    var subject: String
    var body: String
    var attachment: URL
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        if !to.isEmpty { vc.setToRecipients([to]) }
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        if let data = try? Data(contentsOf: attachment) {
            vc.addAttachmentData(data, mimeType: "application/zip", fileName: attachment.lastPathComponent)
        }
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            dismiss()
        }
    }
}
