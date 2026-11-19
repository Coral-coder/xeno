import Foundation
import Observation

struct RecordValue: Codable, Hashable, Identifiable {
    var id = UUID()
    var label: String
    var value: String
}

struct JobRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var title: String
    var values: [RecordValue]
    var verdict: String?
    var verdictGood: Bool?
    /// Optional graph (e.g. vacuum decay) stored with the record.
    var series: [TimedSample]?
    var seriesLabel: String?
}

struct Equipment: Codable, Hashable {
    var outdoorMake = "", outdoorModel = "", outdoorSerial = ""
    var indoorMake = "", indoorModel = "", indoorSerial = ""
    var refrigerant = "R-410A"
    var metering: MeteringDevice = .txv
    var tons = ""
    var seer = ""
    var factoryCharge = ""
}

struct Job: Identifiable, Hashable {
    var id = UUID()
    var created = Date()
    var customer = ""
    var address = ""
    var phone = ""
    var email = ""
    var workOrder = ""
    var equipment = Equipment()
    var notes = ""
    var records: [JobRecord] = []
    /// Photo file names in Documents/photos.
    var photos: [String] = []
    var title: String { customer.isEmpty ? "Job \(created.formatted(date: .abbreviated, time: .shortened))" : customer }
}

/// Tolerant decoding: fields added in later builds never make old jobs unreadable.
extension Job: Codable {
    enum CodingKeys: String, CodingKey { case id, created, customer, address, phone, email, workOrder, equipment, notes, records, photos }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? id
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? created
        customer = try c.decodeIfPresent(String.self, forKey: .customer) ?? ""
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        workOrder = try c.decodeIfPresent(String.self, forKey: .workOrder) ?? ""
        equipment = (try? c.decodeIfPresent(Equipment.self, forKey: .equipment)) ?? Equipment()
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        records = (try? c.decodeIfPresent([JobRecord].self, forKey: .records)) ?? []
        photos = (try? c.decodeIfPresent([String].self, forKey: .photos)) ?? []
    }
}

enum PhotoStore {
    static var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("photos")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func save(_ data: Data) -> String? {
        let name = UUID().uuidString + ".jpg"
        do { try data.write(to: dir.appendingPathComponent(name)); return name } catch { return nil }
    }
    static func url(_ name: String) -> URL { dir.appendingPathComponent(name) }
    static func delete(_ name: String) { try? FileManager.default.removeItem(at: url(name)) }
}

@Observable
final class JobStore {
    private(set) var jobs: [Job] = []
    var activeJobID: UUID? { didSet { UserDefaults.standard.set(activeJobID?.uuidString, forKey: "xeno.activeJob") } }

    private var url: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("jobs.json")
    }

    init() {
        if let data = try? Data(contentsOf: url), let j = try? JSONDecoder().decode([Job].self, from: data) { jobs = j }
        if let s = UserDefaults.standard.string(forKey: "xeno.activeJob") { activeJobID = UUID(uuidString: s) }
    }

    var activeJob: Job? { jobs.first { $0.id == activeJobID } }

    private func save() {
        do {
            let data = try JSONEncoder().encode(jobs)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Xeno: couldn't save jobs: \(error)")
        }
    }

    @discardableResult
    func create(_ job: Job = Job()) -> Job {
        jobs.insert(job, at: 0); activeJobID = job.id; save(); return job
    }

    func update(_ job: Job) {
        guard let i = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs[i] = job; save()
    }

    func delete(_ ids: [UUID]) {
        jobs.removeAll { ids.contains($0.id) }
        if let a = activeJobID, ids.contains(a) { activeJobID = nil }
        save()
    }

    func add(_ record: JobRecord, to jobID: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[i].records.append(record); save()
    }

    func deleteRecord(_ recordID: UUID, from jobID: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[i].records.removeAll { $0.id == recordID }; save()
    }
}
