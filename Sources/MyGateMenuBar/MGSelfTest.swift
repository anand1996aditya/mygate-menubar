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

        print("UNIT failures=\(failures)")
        return failures
    }
}
