import AppKit
import Foundation

enum MGUnitTests {
    @MainActor
    static func run() -> Int {
        var failures = 0
        func check(_ condition: Bool, _ name: String) {
            if condition {
                print("PASS \(name)")
            } else {
                failures += 1
                print("FAIL \(name)")
            }
        }

        // Pending payload parsing
        let fixture: [String: Any] = [
            "validationid": "6ada1e0a7dd4022f3135de21",
            "visitor_title": "Delivery Executive",
            "body": "Murli from Box8 requires your approval",
            "category": "DELIVERY",
            "time": "8:00 PM",
            "gate": "Main Gate",
            "image": "https://example.com/visitor.jpg"
        ]
        let pending = MGAPI.parsePending(fixture)
        check(pending?.validationId == "6ada1e0a7dd4022f3135de21", "pending validation id")
        check(pending?.title == "Delivery Executive", "pending title")
        check(pending?.body == "Murli from Box8 requires your approval", "pending body")
        check(pending?.category == "DELIVERY", "pending category")
        check(pending?.photoURL?.absoluteString == "https://example.com/visitor.jpg", "pending photo")

        // Cab digits
        check(MGModel.normalizeCabDigits("12a34 567") == "1234", "cab digits stripped and capped")
        check(MGModel.normalizeCabDigits("") == "", "cab empty")
        check(MGModel.normalizeCabDigits("9999") == "9999", "cab exact four")
        check(MGModel.normalizeCabDigits("123") == "123", "cab shorter allowed")

        // Phone and OTP normalisation
        check(MGModel.normalizePhone("+91 98765 43210") == "9876543210", "phone strips country code")
        check(MGModel.normalizePhone("09876543210") == "9876543210", "phone strips leading zero")
        check(MGModel.normalizePhone("98765abc43210") == "9876543210", "phone strips letters")
        check(MGModel.normalizePhone("98765") == "98765", "phone short stays for validation")
        check(MGModel.normalizeOTP("12a34567") == "123456", "otp digits and six cap")
        check(MGModel.normalizeOTP("1234") == "1234", "otp short stays for validation")

        // Button labels
        check(MGModel.PreApprovalType.guest.actionTitle == "Send invite", "guest label")
        check(MGModel.PreApprovalType.delivery.actionTitle == "Pre-approve", "delivery label")
        check(MGModel.PreApprovalType.cab.actionTitle == "Pre-approve", "cab label")
        check(MGModel.PreApprovalType.visitingHelp.actionTitle == "Pre-approve", "help label")

        // Other delivery mapping
        check(MGModel.deliveryAddress(MGModel.otherDeliveryOption) == "DELIVERY", "other delivery maps to DELIVERY")
        check(MGModel.deliveryOptions(["AMAZON"]).first == MGModel.otherDeliveryOption, "other delivery listed first")
        check(MGModel.deliveryAddress("swiggy") == "SWIGGY", "named delivery uppercased")

        // Visitor photo is downscaled before layout.
        let huge = NSImage(size: NSSize(width: 3000, height: 4000))
        huge.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: 3000, height: 4000).fill()
        huge.unlockFocus()
        if let cg = huge.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let small = PendingImageLoader.resized(cg, targetSize: CGSize(width: 46, height: 46)) {
            check(small.size == NSSize(width: 46, height: 46), "visitor photo downscaled")
        } else {
            check(false, "visitor photo downscaled")
        }

        // History presentation.
        let deliveryCard = MGFeedCard(id: "f1", cardType: "DELIVERY", name: "", status: "INSIDE",
                                      detail: "Vinay Kumar  AMAZON · Allowed by you · Delivering to 16 more house(s)",
                                      timestamp: Date(), cancelId: nil, ntype: nil)
        let shown = MGModel.feedPresentation(deliveryCard)
        check(shown.title == "Vinay Kumar (Amazon)", "delivery heading name and company")
        check(shown.subtitle == "Allowed by you", "delivery action line")
        check(shown.note == "Delivering to 16 more houses", "delivery note line")
        check(MGHistoryFormat.cleanText("Dildar Alam<IMGS>VALIDATED</IMGS> · Pre-approved by you")
              == "Dildar Alam · Pre-approved by you", "history tags removed")
        check(MGHistoryFormat.formattedEpoch("1792738691831") != nil, "epoch history time formatted")

        // Default delivery companies
        let companies = MGModel.defaultDeliveryCompanies
        check(companies.contains("BLINKIT"), "default has Blinkit")
        check(companies.contains("ZOMATO"), "default has Zomato")
        check(companies.contains("SWIGGY"), "default has Swiggy")

        // History store round trip
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("mg-history-test-\(UUID().uuidString).json")
        let store = MGHistoryStore(fileURL: tempURL)
        let gate = MGPending(validationId: "test-gate", title: "Delivery Executive",
                             subtitle: "waiting", body: "at the gate", category: "DELIVERY",
                             time: "8:00 PM", flat: "T1 101", gate: "Main Gate", photoURL: nil)
        store.recordGate(gate)
        store.recordVisitor(name: "Test Visitor", type: "DELIVERY", passcode: "1234", photoURL: nil)
        store.recordPass(id: "pass-1", title: "Guest", status: "Pass Expired", timeText: "6:00 PM", detail: "Valid till 6:00 PM")
        check(store.entries.count == 3, "history records three entries")
        store.updateGate(validationId: "test-gate", status: "Approved")
        check(store.entries.first(where: { $0.id == "g:test-gate" })?.status == "Approved", "history gate status update")
        check(store.last24Hours.count == 3, "history last 24 hours")
        store.clear()
        check(store.entries.isEmpty, "history clear")
        try? FileManager.default.removeItem(at: tempURL)

        // History persists across instances
        let persistURL = FileManager.default.temporaryDirectory.appendingPathComponent("mg-history-persist-\(UUID().uuidString).json")
        let first = MGHistoryStore(fileURL: persistURL)
        first.recordPass(id: "persist-1", title: "Guest", status: "Active", timeText: "9:00 PM", detail: "Valid")
        let second = MGHistoryStore(fileURL: persistURL)
        check(second.entries.count == 1, "history persists across launches")
        try? FileManager.default.removeItem(at: persistURL)

        // Old entries are pruned on load
        let pruneURL = FileManager.default.temporaryDirectory.appendingPathComponent("mg-history-prune-\(UUID().uuidString).json")
        let old = MGHistoryEntry(id: "g:old", kind: .gate, title: "Old", subtitle: "", status: "Cleared",
                                 timeText: "", timestamp: Date().addingTimeInterval(-80 * 3600),
                                 photoURL: nil, passcode: nil)
        if let data = try? JSONEncoder().encode([old]) { try? data.write(to: pruneURL) }
        let pruned = MGHistoryStore(fileURL: pruneURL)
        check(pruned.entries.isEmpty, "history prunes beyond retention")
        try? FileManager.default.removeItem(at: pruneURL)

        // Keychain-backed access key storage, migration and log permissions
        tokenStorageTests(check)

        print("UNIT failures=\(failures)")
        return failures
    }

    /// Exercises Keychain-backed storage, one-time migration and log permissions
    /// with an in-memory token store. The real Keychain is never touched here.
    private static func tokenStorageTests(_ check: (Bool, String) -> Void) {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory
            .appendingPathComponent("mg-storage-test-\(UUID().uuidString)", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("config.json")

        func writeLegacyJSON(_ token: String) {
            let legacy: [String: Any] = [
                "apiKey": token,
                "userId": "1000000",
                "flatId": "flat-1",
                "phone": "9876543210",
                "name": "Test Resident",
                "deviceId": "device-1",
                "versionCode": "36",
                "appVersion": "7.39.0"
            ]
            if let data = try? JSONSerialization.data(withJSONObject: legacy) {
                try? data.write(to: configURL)
            }
        }

        func rawJSON() -> [String: Any] {
            guard let data = try? Data(contentsOf: configURL),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return [:]
            }
            return object
        }

        let key = (service: MGConfig.keychainService, account: MGConfig.keychainAccount)

        // Deliberate failure paths must not write to the real diagnostics log.
        MGDiagnostics.suppressWrites = true
        defer { MGDiagnostics.suppressWrites = false }

        // Legacy plain-text token moves to the secure store and leaves the JSON.
        writeLegacyJSON("legacy-token-abc")
        let store = InMemoryTokenStore()
        let migrated = MGConfig.load(from: configURL, tokenStore: store)
        check(migrated?.apiKey == "legacy-token-abc", "legacy access key migrates in memory")
        check(store.value(service: key.service, account: key.account) == "legacy-token-abc",
              "legacy access key stored in secure store")
        check(rawJSON()["apiKey"] == nil, "legacy access key removed from config json")
        check(migrated?.userId == "1000000", "migration preserves user id")
        check(migrated?.name == "Test Resident", "migration preserves profile fields")

        // The secure store wins over a stale plain-text copy.
        writeLegacyJSON("stale-json-token")
        let preferred = MGConfig.load(from: configURL, tokenStore: store)
        check(preferred?.apiKey == "legacy-token-abc", "secure store preferred over legacy json")
        check(rawJSON()["apiKey"] == nil, "stale legacy copy scrubbed when secure store wins")

        // A failed secure-store write keeps the legacy copy and a usable session.
        writeLegacyJSON("cannot-migrate-token")
        let brokenStore = InMemoryTokenStore()
        brokenStore.failWrite = true
        let fallback = MGConfig.load(from: configURL, tokenStore: brokenStore)
        check(fallback?.apiKey == "cannot-migrate-token", "session works when secure store write fails")
        check(rawJSON()["apiKey"] as? String == "cannot-migrate-token",
              "legacy copy kept when migration fails")

        // Saving writes the token to the store and never to the JSON.
        var saved = fallback ?? MGConfig()
        saved.apiKey = "new-access-key"
        let saveStore = InMemoryTokenStore()
        check(saved.save(to: configURL, tokenStore: saveStore), "config save succeeds")
        check(saveStore.value(service: key.service, account: key.account) == "new-access-key",
              "save writes access key to secure store")
        check(rawJSON()["apiKey"] == nil, "save keeps access key out of config json")
        let reloaded = MGConfig.load(from: configURL, tokenStore: saveStore)
        check(reloaded?.apiKey == "new-access-key", "access key reloads from secure store")

        // Signing out clears the stored access key.
        var signedOut = reloaded ?? MGConfig()
        signedOut.apiKey = ""
        _ = signedOut.save(to: configURL, tokenStore: saveStore)
        check(saveStore.value(service: key.service, account: key.account) == nil,
              "sign out removes access key from secure store")
        check(rawJSON()["apiKey"] == nil, "sign out keeps access key out of config json")

        // A Keychain read error does not crash loading.
        let unreadable = InMemoryTokenStore()
        unreadable.failRead = true
        check(MGConfig.load(from: configURL, tokenStore: unreadable) != nil,
              "config loads when secure store read fails")

        // Diagnostics logs and dumps are owner-only.
        MGDiagnostics.suppressWrites = false
        let logURL = directory.appendingPathComponent("diagnostics.log")
        MGDiagnostics.append("permission test", to: logURL)
        check(fileMode(of: logURL) == 0o600, "diagnostics log created with 0600")
        try? manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: logURL.path)
        MGDiagnostics.append("permission repair", to: logURL)
        check(fileMode(of: logURL) == 0o600, "leftover log repaired to 0600")
        MGDiagnostics.saveRaw(["probe": 1], name: "pending-raw.json", directory: directory)
        check(fileMode(of: directory.appendingPathComponent("pending-raw.json")) == 0o600,
              "diagnostic dump created with 0600")
    }

    private static func fileMode(of url: URL) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return (attributes[.posixPermissions] as? NSNumber)?.intValue
    }
}
