import Foundation

struct MGConfig: Codable, Equatable {
    var apiKey: String = ""
    var userId: String = ""
    var flatId: String = ""
    var societyId: String = ""
    var phone: String = ""
    var name: String = ""
    var flatName: String = ""
    var buildingName: String = ""
    var societyName: String = ""
    var deviceId: String = UUID().uuidString
    var versionCode: String = "36"
    var appVersion: String = "7.39.0"

    var isLoggedIn: Bool { !apiKey.isEmpty && !userId.isEmpty && !flatId.isEmpty }

    static var supportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MyGate MenuBar")
    }

    static var fileURL: URL { supportDir.appendingPathComponent("config.json") }

    static func load() -> MGConfig? {
        guard let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(MGConfig.self, from: data) else { return nil }
        return config
    }

    func save() {
        try? FileManager.default.createDirectory(at: MGConfig.supportDir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: MGConfig.fileURL, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: MGConfig.fileURL.path)
        }
    }
}

enum MGBodies {
    static func headers(_ c: MGConfig, authenticated: Bool = true) -> [String: String] {
        var headers = [
            "Accept": "application/json",
            "Content-Type": "application/json",
            "app-client": "N",
            "app-version": c.appVersion,
            "app-client-os-version": c.versionCode,
            "User-Agent": "okhttp/4.12.0"
        ]
        if authenticated, !c.apiKey.isEmpty { headers["access-key"] = c.apiKey }
        return headers
    }

    static func validateOTP(phone: String) -> [String: Any] {
        ["uname": phone, "country_code": "91", "device_type": "N"]
    }

    static func login(_ c: MGConfig, phone: String, otp: String) -> [String: Any] {
        ["username": phone, "country_code": "91", "version": 3, "password": otp,
         "deviceid": c.deviceId, "type": "N", "osversion": 36, "model": "Mac",
         "appversion": c.appVersion]
    }

    static func userInfo(_ c: MGConfig) -> [String: Any] { ["userid": c.userId] }

    static func allowOnce(_ c: MGConfig, validationId: String) -> [String: Any] {
        ["userid": c.userId, "flatid": c.flatId, "validation_id": validationId]
    }

    static func reject(_ c: MGConfig, validationId: String, reason: String) -> [String: Any] {
        ["userid": c.userId, "flatid": c.flatId, "validation_id": validationId, "reason": reason]
    }

    static func preApproveInfo(_ c: MGConfig) -> [String: Any] {
        ["userid": c.userId, "flatid": c.flatId]
    }

    static func inviteGuest(_ c: MGConfig, name: String, mobile: String, start: Int, end: Int) -> [String: Any] {
        ["userid": c.userId, "flatid": c.flatId, "invitetype": "1213",
         "startTime": start, "endTime": end, "isMulti": 0, "gathering_id": "",
         "invited_guest_info": [["name": name, "mobile": mobile]]]
    }

    static func preApprove(_ c: MGConfig, type: MGModel.PreApprovalType, name: String,
                           vehicle: String, userTypeId: String?, start: Int, end: Int) -> [String: Any] {
        var body: [String: Any] = ["userid": c.userId, "flatid": c.flatId,
                                   "startTime": start, "endTime": end,
                                   "userTypeId": userTypeId ?? type.userTypeId, "gateMessageType": "2305",
                                   "isDeliveryDelegated": "0", "isMulti": 0]
        switch type {
        case .guest:
            body["visitorName"] = name
            body["visitorMobile"] = vehicle
        case .delivery:
            body["visitorAddress"] = name.uppercased()
        case .cab:
            body["visitorVehicle"] = vehicle.uppercased()
        case .visitingHelp:
            body["visitorName"] = name
            body["visitorAddress"] = name
        }
        return body
    }

    static func preApproveDelivery(_ c: MGConfig, company: String, start: Int, end: Int) -> [String: Any] {
        ["userid": c.userId, "flatid": c.flatId, "startTime": start, "endTime": end,
         "userTypeId": "1008", "gateMessageType": "2305",
         "visitorAddress": company.uppercased(), "isDeliveryDelegated": "0", "isMulti": 0]
    }
}
