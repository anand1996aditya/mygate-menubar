import Foundation

enum MGDiagnostics {
    static var logURL: URL { MGConfig.supportDir.appendingPathComponent("diagnostics.log") }

    /// Self-tests that exercise deliberate failures set this to keep the real
    /// diagnostics log clean.
    static var suppressWrites = false

    private static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: MGConfig.supportDir, withIntermediateDirectories: true)
    }

    /// Creates the file when missing and forces owner-only permissions.
    /// Log files must never be readable by other users.
    static func ensurePrivatePermissions(at url: URL) {
        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil,
                               attributes: [.posixPermissions: 0o600])
        }
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func saveRaw(_ object: [String: Any], name: String, directory: URL = MGConfig.supportDir) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            ensurePrivatePermissions(at: url)
        } catch {
            return
        }
    }

    static func append(_ message: String, to url: URL? = nil) {
        guard !suppressWrites else { return }
        ensureDirectory()
        let target = url ?? logURL
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date())) \(message)\n"
        ensurePrivatePermissions(at: target)
        if let handle = try? FileHandle(forWritingTo: target) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8) ?? Data())
            try? handle.close()
        } else {
            try? line.write(to: target, atomically: true, encoding: .utf8)
            ensurePrivatePermissions(at: target)
        }
    }

    /// Repairs permissions on log files written by older builds (mode 0644).
    static func hardenExistingLogs() {
        ensureDirectory()
        for name in ["diagnostics.log", "pending-raw.json", "pending-last.json"] {
            let url = MGConfig.supportDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                ensurePrivatePermissions(at: url)
            }
        }
    }
}

enum MGError: LocalizedError {
    case transport(String)
    case api(String)
    case http(Int)
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .transport(let m): return m
        case .api(let m): return m
        case .http(let c): return "HTTP \(c)"
        case .parse(let m): return m
        }
    }
}

struct MGPending: Identifiable, Equatable {
    let validationId: String
    var requestId: String = ""
    var visitId: String = ""
    var title: String = "Visitor at gate"
    var subtitle: String = ""
    var body: String = ""
    var category: String = ""
    var time: String = ""
    var flat: String = ""
    var gate: String = ""
    var photoURL: URL?
    var valstatus: String = ""
    var replyto: String = ""
    var notificationId: String = ""
    var id: String { validationId }
}

struct MGVisitor: Identifiable, Equatable {
    let id: String
    var name: String
    var type: String
    var photoURL: URL?
    var passcode: String
}

struct MGFeedCard: Identifiable {
    let id: String
    let cardType: String
    let name: String
    let status: String
    let detail: String
    let timestamp: Date
    let cancelId: String?
    let ntype: String?
}

struct MGPass: Identifiable, Equatable {
    let id: String
    var title: String
    var status: String
    var statusColor: String
    var passcode: String
    var timeText: String
    var detail: String
    var isToday: Bool
    var seekId: String? = nil
}

struct MGPreApproveInfo {
    var companies: [String] = []
    var categories: [(name: String, typeId: String)] = []
}

struct MGAPI {
    let config: MGConfig

    private func request(_ urlString: String, body: [String: Any], method: String = "POST") async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw MGError.parse("Bad URL") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        for (k, v) in MGBodies.headers(config) { request.setValue(v, forHTTPHeaderField: k) }
        if method != "GET" { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw MGError.transport(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw MGError.parse("No HTTP response") }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MGError.parse("Response was not JSON")
        }
        if http.statusCode == 401 || http.statusCode == 403 { throw MGError.api("Session expired. Log in again.") }
        guard http.statusCode == 200 else {
            throw MGError.api((object["message"] as? String) ?? "HTTP \(http.statusCode)")
        }
        let es = (object["es"] as? String) ?? String(describing: object["es"] ?? "")
        if es == "1" { throw MGError.api((object["message"] as? String) ?? "MyGate returned an error") }
        return object
    }

    static func validate(_ base: MGConfig, phone: String) async throws -> [String: Any] {
        try await MGAPI(config: base).request("https://app.mygate.in/auth/v2/user/validate",
                                              body: MGBodies.validateOTP(phone: phone))
    }

    static func login(_ base: MGConfig, phone: String, otp: String) async throws -> (apiKey: String, userId: String) {
        let object = try await MGAPI(config: base).request("https://app.mygate.in/auth/v2/login",
                                                           body: MGBodies.login(base, phone: phone, otp: otp))
        guard let apiKey = object["api_key"] as? String,
              let userId = object["userid"] as? String else {
            throw MGError.api((object["message"] as? String) ?? "Login failed")
        }
        return (apiKey, userId)
    }

    static func profile(_ config: MGConfig) async throws -> [String: Any] {
        try await MGAPI(config: config).request("https://app.mygate.in/user/v3/info",
                                                body: MGBodies.userInfo(config))
    }

    func pending() async throws -> MGPending? {
        let query = "?userid=\(config.userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? config.userId)&flatid=\(config.flatId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? config.flatId)&type=N"
        let object = try await request("https://app.mygate.in/notif/v2/validation/active" + query, body: [:], method: "GET")
        let es = (object["es"] as? String) ?? ""
        if es == "2" { return nil }
        guard let data = object["data"] as? [String: Any] else {
            MGDiagnostics.saveRaw(object, name: "pending-raw.json")
            return nil
        }
        MGDiagnostics.saveRaw(data, name: "pending-last.json")
        let parsed = MGAPI.parsePending(data)
        if parsed == nil { MGDiagnostics.saveRaw(data, name: "pending-raw.json") }
        return parsed
    }

    func approve(_ pending: MGPending) async throws {
        if !pending.replyto.isEmpty {
            _ = try await request(pending.replyto,
                                  body: MGBodies.validationResponse(config, pending, status: "A"))
            return
        }
        _ = try await request("https://ack.mygate.in/ecom/v3/approvalrequest/allowonce",
                              body: MGBodies.allowOnce(config, validationId: pending.validationId))
    }

    func reject(_ pending: MGPending, reason: String) async throws {
        if !pending.replyto.isEmpty {
            _ = try await request(pending.replyto,
                                  body: MGBodies.validationResponse(config, pending, status: "D"))
            return
        }
        _ = try await request("https://ack.mygate.in/ecom/v3/approvalrequest/userreject",
                              body: MGBodies.reject(config, validationId: pending.validationId, reason: reason))
    }

    func currentVisitors() async throws -> [MGVisitor] {
        let query = "?userid=\(config.userId)&flatid=\(config.flatId)"
        let object = try await request("https://app.mygate.in/flat/v2/visitors" + query, body: [:], method: "GET")
        guard let list = object["visitors"] as? [[String: Any]] else { return [] }
        return list.compactMap { item in
            guard let person = item["person"] as? [String: Any] else { return nil }
            let id = (person["id"] as? String) ?? UUID().uuidString
            let name = (person["name"] as? String) ?? "Visitor"
            let type = (person["visitor_type"] as? String) ?? ""
            let photo = (person["photo"] as? String).flatMap(URL.init(string:))
            let passcode = (person["passcode"] as? String) ?? ""
            return MGVisitor(id: id, name: name, type: type, photoURL: photo, passcode: passcode)
        }
    }

    func activityFeed(date: Date? = nil) async throws -> [MGFeedCard] {
        var body: [String: Any] = ["userid": config.userId, "flat_id": config.flatId, "version": "4"]
        if let date { body["date"] = Int(date.timeIntervalSince1970) }
        let object = try await request("https://app.mygate.in/activity/v2/fetchcards", body: body)
        let rows = (object["data"] as? [[String: Any]]) ?? []
        return rows.compactMap { Self.parseFeedCard($0) }
    }

    func cancelPreApproval(gateMessageId: String, ntype: String?) async throws {
        var body: [String: Any] = ["userid": config.userId, "flatid": config.flatId,
                                   "gateMessageId": gateMessageId, "isDeleted": "1"]
        if let ntype, !ntype.isEmpty { body["ntype"] = ntype }
        _ = try await request("https://ack.mygate.in/preapprove/v2/send", body: body)
    }

    private static func parseFeedCard(_ item: [String: Any]) -> MGFeedCard? {
        guard let cardId = item["cardId"] as? String else { return nil }
        let cardType = (item["cardType"] as? String) ?? ""
        let name = (item["name"] as? String) ?? ""
        let status = (item["statusTitle"] as? String) ?? (item["status"] as? String) ?? ""
        let descriptions = (item["desc"] as? [[String: Any]]) ?? []
        var details: [String] = []
        for description in descriptions {
            guard var value = description["value"] as? String else { continue }
            value = value.replacingOccurrences(of: "<IMGU>.*?</IMGU>", with: "", options: .regularExpression)
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { details.append(value) }
        }
        var timestamp = Date()
        if let seconds = item["statusActionTime"] as? Double {
            timestamp = Date(timeIntervalSince1970: seconds)
        } else if let seconds = item["statusActionTime"] as? Int {
            timestamp = Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        var cancelId: String?
        for action in (item["actions"] as? [[String: Any]]) ?? [] {
            if (action["type"] as? String) == "CANCEL" {
                cancelId = action["actionId"] as? String
            }
        }
        let payload = (item["payload"] as? [String: Any]) ?? [:]
        let ntype = payload["ntype"] as? String
        return MGFeedCard(id: cardId, cardType: cardType, name: name, status: status,
                          detail: details.joined(separator: " · "), timestamp: timestamp,
                          cancelId: cancelId, ntype: ntype)
    }

    func myVisitsRaw() async throws -> [String: Any] {
        let query = "?userid=\(config.userId)&flatid=\(config.flatId)&societyid=\(config.societyId)&pageNo=0&version=2"
        return try await request("https://app.mygate.in/seekinvite/v1/myvisits" + query, body: [:], method: "GET")
    }

    func deleteVisit(inviteId: String, seekId: String?) async throws {
        var body: [String: Any] = ["userid": config.userId, "invite_id": inviteId]
        if let seekId, !seekId.isEmpty { body["seek_id"] = seekId }
        _ = try await request("https://app.mygate.in/seekinvite/v1/myvisits", body: body, method: "DELETE")
    }

    func myVisits() async throws -> [MGPass] {
        let query = "?userid=\(config.userId)&flatid=\(config.flatId)&societyid=\(config.societyId)&pageNo=0&version=2"
        let object = try await request("https://app.mygate.in/seekinvite/v1/myvisits" + query, body: [:], method: "GET")
        guard let list = object["seeker_visits"] as? [[String: Any]] else { return [] }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return list.compactMap { item in
            let id = (item["invite_id"] as? String) ?? UUID().uuidString
            let title = (item["title"] as? String) ?? "Pass"
            let status = (item["status_details"] as? [String: Any])?["statusText"] as? String ?? (item["status"] as? String ?? "")
            let color = (item["status_details"] as? [String: Any])?["statusColor"] as? String ?? "#8e8e93"
            let passcode = (item["passcode"] as? String) ?? ""
            var timeText = ""
            var detail = ""
            if let stamp = item["status_action_time"] as? TimeInterval {
                let date = Date(timeIntervalSince1970: stamp)
                timeText = formatter.string(from: date)
            }
            if let desc = item["description"] as? [[String: Any]] {
                let values = desc.compactMap { $0["value"] as? String }
                detail = values.first(where: { $0.contains("Valid") || $0.contains("•") }) ?? ""
            }
            let isToday: Bool
            if let stamp = item["status_action_time"] as? TimeInterval {
                isToday = Calendar.current.isDateInToday(Date(timeIntervalSince1970: stamp))
            } else { isToday = true }
            return MGPass(id: id, title: title, status: status, statusColor: color,
                          passcode: passcode, timeText: timeText, detail: detail, isToday: isToday,
                          seekId: item["seek_id"] as? String)
        }
    }

    func preApproveInfo() async throws -> MGPreApproveInfo {
        let object = try await request("https://ack.mygate.in/preapprove/v2/info",
                                       body: MGBodies.preApproveInfo(config))
        var info = MGPreApproveInfo()
        info.companies = (object["companyNames"] as? [String]) ?? []
        if let categories = object["categories"] as? [[String: Any]] {
            info.categories = categories.compactMap { dict in
                guard let name = dict["displayName"] as? String else { return nil }
                let typeId = String(describing: dict["typeId"] ?? "")
                return (name, typeId)
            }
        }
        return info
    }

    func deliveryProviders() async throws -> [String] {
        let query = "?userid=\(config.userId)&deviceid=\(config.deviceId)&societyid=\(config.societyId)"
        let object = try await request("https://app.mygate.in/society/v3/deliveryproviders" + query,
                                       body: [:], method: "GET")
        guard let list = object["cnd"] as? [[String: Any]] else { return [] }
        return list.compactMap { $0["dpname"] as? String }
    }

    func inviteGuest(name: String, mobile: String, start: Int, end: Int) async throws -> String {
        let object = try await request("https://ack.mygate.in/preapprove/v2/invite",
                                       body: MGBodies.inviteGuest(config, name: name, mobile: mobile,
                                                                  start: start, end: end))
        let data = (object["data"] as? [String: Any]) ?? object
        var passcodes: [String] = []
        if let invites = data["invite_info"] as? [[String: Any]] {
            passcodes = invites.compactMap { $0["passcode"] as? String }
        } else if let passcode = data["passcode"] as? String {
            passcodes = [passcode]
        }
        if passcodes.isEmpty { return "Invite sent" }
        return "Invite sent · passcode \(passcodes.joined(separator: ", "))"
    }

    func preApproveDelivery(company: String, start: Int, end: Int) async throws {
        _ = try await request("https://ack.mygate.in/preapprove/v2/send",
                              body: MGBodies.preApproveDelivery(config, company: company, start: start, end: end))
    }

    func preApprove(type: MGModel.PreApprovalType, name: String, vehicle: String,
                    userTypeId: String? = nil, start: Int, end: Int) async throws {
        _ = try await request("https://ack.mygate.in/preapprove/v2/send",
                              body: MGBodies.preApprove(config, type: type, name: name, vehicle: vehicle,
                                                        userTypeId: userTypeId, start: start, end: end))
    }

    static func parsePending(_ data: [String: Any]) -> MGPending? {
        guard let validationId = (data["validationid"] as? String) ?? findString(data, keys: ["validation_id", "validationId"]) else { return nil }
        var pending = MGPending(validationId: validationId)
        pending.requestId = (data["request_id"] as? String) ?? ""
        pending.visitId = (data["visitId"] as? String) ?? (data["visitid"] as? String) ?? ""
        pending.valstatus = (data["valstatus"] as? String) ?? ""
        pending.replyto = firstString(data, keys: ["replyto", "reply_to", "replyTo"]) ?? ""
        pending.notificationId = firstString(data, keys: ["notification_id", "notificationId"]) ?? ""
        pending.title = firstString(data, keys: ["visitor_title", "title", "visitor_name", "username", "name"]) ?? "Visitor at gate"
        pending.subtitle = firstString(data, keys: ["visitor_subtitle", "subtitle", "body", "message", "category"]) ?? ""
        pending.body = firstString(data, keys: ["body", "message", "additional_message"]) ?? ""
        pending.category = firstString(data, keys: ["category", "visitor_category", "ecom_type"]) ?? ""
        let rawTime = firstString(data, keys: ["time", "visit_time", "created_at"]) ?? ""
        if let epoch = Double(rawTime), epoch > 0 {
            let seconds = epoch > 1_000_000_000_000 ? epoch / 1000 : epoch
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "h:mm a"
            pending.time = formatter.string(from: Date(timeIntervalSince1970: seconds))
        } else {
            pending.time = rawTime
        }
        pending.flat = firstString(data, keys: ["flat", "flat_name"]) ?? ""
        pending.gate = firstString(data, keys: ["gate", "gate_name", "gateName"]) ?? ""
        if let raw = firstString(data, keys: ["image", "bigImage", "smallImage", "visitor_image", "photo"]) {
            pending.photoURL = URL(string: raw)
        }
        return pending
    }

    private static func findString(_ value: Any, keys: [String]) -> String? {
        if let dict = value as? [String: Any] {
            for key in keys { if let s = dict[key] as? String, !s.isEmpty { return s } }
            for (_, child) in dict { if let s = findString(child, keys: keys) { return s } }
        } else if let array = value as? [Any] {
            for child in array { if let s = findString(child, keys: keys) { return s } }
        }
        return nil
    }

    private static func firstString(_ data: [String: Any], keys: [String]) -> String? {
        for key in keys { if let s = data[key] as? String, !s.isEmpty { return s } }
        return nil
    }
}
