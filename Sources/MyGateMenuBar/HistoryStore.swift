import Foundation

enum MGHistoryFormat {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    static func formattedEpoch(_ raw: String) -> String? {
        guard let value = Double(raw), value > 1_000_000_000 else { return nil }
        let seconds = value > 1_000_000_000_000 ? value / 1000 : value
        return timeFormatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    static func cleanText(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "<([A-Za-z][^>]*)>.*?</[A-Za-z][^>]*>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "house(s)", with: "houses")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MGHistoryEntry: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case gate, visitor, pass
    }

    var id: String
    var kind: Kind
    var title: String
    var subtitle: String
    var status: String
    var timeText: String
    var timestamp: Date
    var photoURL: String?
    var passcode: String?
    var note: String? = nil
    var cancelId: String? = nil
    var cancelNtype: String? = nil

    var timeLabel: String {
        if let formatted = MGHistoryFormat.formattedEpoch(timeText) { return formatted }
        if !timeText.isEmpty { return timeText }
        return MGHistoryFormat.timeFormatter.string(from: timestamp)
    }

    func normalized() -> MGHistoryEntry {
        var copy = self
        copy.title = MGHistoryFormat.cleanText(title)
        copy.subtitle = MGHistoryFormat.cleanText(subtitle)
        copy.note = note.map(MGHistoryFormat.cleanText).flatMap { $0.isEmpty ? nil : $0 }
        if let formatted = MGHistoryFormat.formattedEpoch(timeText) {
            copy.timeText = formatted
        }
        if copy.title == "Delivery Executive" {
            if let parsed = MGModel.parseGateBody(copy.subtitle) {
                copy.title = "Delivery Executive · \(parsed.company.capitalized)"
                copy.subtitle = "\(parsed.name) · Approval required at gate"
                copy.note = "Entry to \(parsed.place)"
            }
        }
        if ["Delivery", "Cab"].contains(copy.title) {
            let parts = copy.subtitle.components(separatedBy: " · ").map(MGHistoryFormat.cleanText).filter { !$0.isEmpty }
            let tokens = (parts.first ?? "").components(separatedBy: "  ").map(MGHistoryFormat.cleanText).filter { !$0.isEmpty }
            if tokens.count >= 2 {
                copy.title = "\(tokens[0]) (\(tokens[1].capitalized))"
                copy.subtitle = parts.dropFirst().first ?? ""
                copy.note = parts.dropFirst(2).joined(separator: " · ")
            }
        }
        return copy
    }
}

@MainActor
final class MGHistoryStore: ObservableObject {
    static let shared = MGHistoryStore()

    @Published private(set) var entries: [MGHistoryEntry] = []

    private let fileURL: URL
    private let retention: TimeInterval = 72 * 3600

    init(fileURL: URL? = nil) {
        if fileURL == nil { MGConfig.migrateLegacySupportDirectoryIfNeeded() }
        self.fileURL = fileURL ?? MGConfig.supportDir.appendingPathComponent("history.json")
        load()
    }

    var recent: [MGHistoryEntry] {
        entries.sorted { $0.timestamp > $1.timestamp }
    }

    var last24Hours: [MGHistoryEntry] {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        return recent.filter { $0.timestamp > cutoff }
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([MGHistoryEntry].self, from: data) else { return }
        let cutoff = Date().addingTimeInterval(-retention)
        entries = list.filter { $0.timestamp > cutoff }.map { $0.normalized() }.sorted { $0.timestamp > $1.timestamp }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        }
    }

    private func upsert(_ entry: MGHistoryEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            var existing = entries[index]
            existing.title = entry.title.isEmpty ? existing.title : entry.title
            existing.subtitle = entry.subtitle.isEmpty ? existing.subtitle : entry.subtitle
            existing.status = entry.status.isEmpty ? existing.status : entry.status
            existing.timeText = entry.timeText.isEmpty ? existing.timeText : entry.timeText
            existing.note = entry.note ?? existing.note
            existing.photoURL = entry.photoURL ?? existing.photoURL
            existing.passcode = entry.passcode ?? existing.passcode
            existing.cancelId = entry.cancelId ?? existing.cancelId
            existing.cancelNtype = entry.cancelNtype ?? existing.cancelNtype
            entries[index] = existing
        } else {
            entries.append(entry)
        }
        let cutoff = Date().addingTimeInterval(-retention)
        entries.removeAll { $0.timestamp < cutoff }
        save()
    }

    func recordGate(_ pending: MGPending, status: String = "At gate") {
        var title = MGHistoryFormat.cleanText(pending.title)
        var subtitle = MGHistoryFormat.cleanText(pending.body.isEmpty ? pending.subtitle : pending.body)
        var note: String?
        if let parsed = MGModel.parseGateBody(subtitle) {
            if title.lowercased().contains("delivery executive") || title.lowercased() == "visitor at gate" {
                title = "\(title) · \(parsed.company.capitalized)"
                subtitle = "\(parsed.name) · Approval required at gate"
                note = "Entry to \(parsed.place)"
            }
        }
        let entry = MGHistoryEntry(
            id: "g:\(pending.validationId)",
            kind: .gate,
            title: title,
            subtitle: subtitle,
            status: status,
            timeText: pending.time,
            timestamp: Date(),
            photoURL: pending.photoURL?.absoluteString,
            passcode: nil,
            note: note
        )
        upsert(entry)
    }

    func updateGate(validationId: String, status: String) {
        guard let index = entries.firstIndex(where: { $0.id == "g:\(validationId)" }) else { return }
        entries[index].status = status
        save()
    }

    static func dayKey(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func recordVisitor(name: String, type: String, passcode: String, photoURL: String?) {
        let key = "v:\(name.lowercased())|\(type.lowercased())|\(Self.dayKey())"
        if entries.contains(where: { $0.id == key }) { return }
        let entry = MGHistoryEntry(
            id: key,
            kind: .visitor,
            title: name,
            subtitle: type.replacingOccurrences(of: "_", with: " ").capitalized,
            status: "Inside",
            timeText: MGHistoryFormat.timeFormatter.string(from: Date()),
            timestamp: Date(),
            photoURL: photoURL,
            passcode: passcode.isEmpty ? nil : passcode
        )
        upsert(entry)
    }

    func markVisitorsLeft(except keys: Set<String>) {
        var changed = false
        for index in entries.indices where entries[index].kind == .visitor
            && entries[index].status == "Inside"
            && !keys.contains(entries[index].id) {
            entries[index].status = "Left"
            changed = true
        }
        if changed { save() }
    }

    func updateStatus(id: String, status: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].status = status
        save()
    }

    func recordFeedCard(id: String, title: String, subtitle: String, note: String?,
                        status: String, timestamp: Date, cancelId: String?, cancelNtype: String?) {
        upsert(MGHistoryEntry(id: "f:\(id)", kind: .pass, title: title, subtitle: subtitle,
                              status: status, timeText: MGHistoryFormat.timeFormatter.string(from: timestamp),
                              timestamp: timestamp, photoURL: nil, passcode: nil, note: note,
                              cancelId: cancelId, cancelNtype: cancelNtype))
    }

    func recordPass(id: String, title: String, status: String, timeText: String, detail: String,
                    passcode: String? = nil) {
        let entry = MGHistoryEntry(
            id: "p:\(id)",
            kind: .pass,
            title: title,
            subtitle: detail,
            status: status,
            timeText: timeText,
            timestamp: Date(),
            photoURL: nil,
            passcode: passcode
        )
        upsert(entry)
    }

    func clear() {
        entries = []
        save()
    }
}
