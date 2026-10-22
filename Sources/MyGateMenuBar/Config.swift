import Foundation

struct MGConfig: Codable, Equatable {
    /// MyGate access key. It is never written to config.json; it lives in the macOS Keychain.
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

    static let keychainService = "com.secureu.mygate"
    static let keychainAccount = "access-key"
    /// Field name used by older builds that stored the access key as plain text.
    static let legacyTokenKey = "apiKey"

    var isLoggedIn: Bool { !apiKey.isEmpty && !userId.isEmpty && !flatId.isEmpty }

    /// Every stored property except `apiKey`. The access key must never be encoded.
    enum CodingKeys: String, CodingKey {
        case userId, flatId, societyId, phone, name, flatName, buildingName, societyName
        case deviceId, versionCode, appVersion
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = MGConfig()
        userId = try container.decodeIfPresent(String.self, forKey: .userId) ?? fallback.userId
        flatId = try container.decodeIfPresent(String.self, forKey: .flatId) ?? fallback.flatId
        societyId = try container.decodeIfPresent(String.self, forKey: .societyId) ?? fallback.societyId
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? fallback.phone
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? fallback.name
        flatName = try container.decodeIfPresent(String.self, forKey: .flatName) ?? fallback.flatName
        buildingName = try container.decodeIfPresent(String.self, forKey: .buildingName) ?? fallback.buildingName
        societyName = try container.decodeIfPresent(String.self, forKey: .societyName) ?? fallback.societyName
        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId) ?? fallback.deviceId
        versionCode = try container.decodeIfPresent(String.self, forKey: .versionCode) ?? fallback.versionCode
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? fallback.appVersion
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(flatId, forKey: .flatId)
        try container.encode(societyId, forKey: .societyId)
        try container.encode(phone, forKey: .phone)
        try container.encode(name, forKey: .name)
        try container.encode(flatName, forKey: .flatName)
        try container.encode(buildingName, forKey: .buildingName)
        try container.encode(societyName, forKey: .societyName)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(versionCode, forKey: .versionCode)
        try container.encode(appVersion, forKey: .appVersion)
        // apiKey is deliberately not encoded.
    }

    static var supportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MyGate MenuBar")
    }

    static var fileURL: URL { supportDir.appendingPathComponent("config.json") }

    static func load() -> MGConfig? {
        load(from: fileURL, tokenStore: KeychainTokenStore.shared)
    }

    /// Loads the non-secret config from JSON and the access key from the secure store.
    ///
    /// The secure store wins. A plain-text token left in an older config.json is
    /// moved to the secure store and blanked from the JSON (one-time migration).
    static func load(from url: URL, tokenStore: SecureTokenStore) -> MGConfig? {
        guard let data = try? Data(contentsOf: url),
              var config = try? JSONDecoder().decode(MGConfig.self, from: data) else { return nil }

        let legacyToken = legacyPlaintextToken(in: data)
        var keychainToken: String?
        do {
            keychainToken = try tokenStore.read(service: keychainService, account: keychainAccount)
        } catch {
            MGDiagnostics.append("keychain read failed: \(error.localizedDescription)")
        }

        if let token = keychainToken, !token.isEmpty {
            config.apiKey = token
            if !legacyToken.isEmpty {
                config.save(to: url, tokenStore: tokenStore)
                MGDiagnostics.append("preferred Keychain access key and removed legacy plaintext copy")
            }
        } else if !legacyToken.isEmpty {
            config.apiKey = legacyToken
            do {
                try tokenStore.write(legacyToken, service: keychainService, account: keychainAccount)
                config.save(to: url, tokenStore: tokenStore)
                MGDiagnostics.append("migrated access key to Keychain")
            } catch {
                // Keep the legacy copy so the session still works and migration can retry.
                MGDiagnostics.append("keychain migration failed; kept legacy copy: \(error.localizedDescription)")
            }
        }
        return config
    }

    @discardableResult
    func save() -> Bool {
        save(to: MGConfig.fileURL, tokenStore: KeychainTokenStore.shared)
    }

    /// Saves the non-secret config to JSON and the access key to the secure store.
    ///
    /// The JSON never contains the access key. A Keychain failure does not abort
    /// the JSON write, so the rest of the config is still saved.
    @discardableResult
    func save(to url: URL = MGConfig.fileURL,
              tokenStore: SecureTokenStore = KeychainTokenStore.shared) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
        } catch {
            MGDiagnostics.append("config directory failed: \(error.localizedDescription)")
        }

        var keychainOK = true
        do {
            if apiKey.isEmpty {
                try tokenStore.delete(service: MGConfig.keychainService, account: MGConfig.keychainAccount)
            } else {
                try tokenStore.write(apiKey, service: MGConfig.keychainService, account: MGConfig.keychainAccount)
            }
        } catch {
            keychainOK = false
            MGDiagnostics.append("keychain write failed: \(error.localizedDescription)")
        }

        do {
            let data = try JSONEncoder().encode(self)
            try data.write(to: url, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            MGDiagnostics.append("config write failed: \(error.localizedDescription)")
            return false
        }
        return keychainOK
    }

    private static func legacyPlaintextToken(in data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object[legacyTokenKey] as? String else { return "" }
        return token.trimmingCharacters(in: .whitespacesAndNewlines)
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
