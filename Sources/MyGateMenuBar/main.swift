import AppKit
import SwiftUI

enum HistoryTest {
    @MainActor
    static func run() {
        Task { @MainActor in
            guard let config = MGConfig.load(), config.isLoggedIn else {
                print("HISTORY FAIL no session")
                exit(1)
            }
            let model = MGModel()
            model.phase = .loggedIn
            await model.loadHistory()
            print("HISTORY total=\(model.history.entries.count)")
            for entry in model.history.recent.prefix(10) {
                print("  \(entry.kind.rawValue) | \(entry.title) | \(entry.status) | \(entry.subtitle)")
            }
            let api = MGAPI(config: config)
            if let entry = model.history.entries.first(where: {
                $0.cancelId != nil && $0.status.uppercased().contains("PRE")
            }) {
                let before = ((try? await api.activityFeed()) ?? []).filter { $0.status.uppercased().contains("PRE-APPROVED") }.count
                await model.revokeHistoryEntry(entry)
                let after = ((try? await api.activityFeed()) ?? []).filter { $0.status.uppercased().contains("PRE-APPROVED") }.count
                print("CANCEL msg=\(model.message) before=\(before) after=\(after)")
            }
            exit(0)
        }
        RunLoop.main.run()
        exit(3)
    }
}

enum FunctionalTest {
    @MainActor
    static func run() {
        Task { @MainActor in
            guard let config = MGConfig.load(), config.isLoggedIn else {
                print("FUNCTIONAL FAIL no session")
                exit(1)
            }
            let model = MGModel()
            model.phase = .loggedIn
            let api = MGAPI(config: model.config)

            func passes() async -> [String] {
                ((try? await api.myVisits()) ?? []).map { "\($0.title) [\($0.status)]" }
            }

            print("BEFORE passes=\((await passes()).joined(separator: "; "))")

            let delivery = await model.createPreApproval(type: .delivery, name: MGModel.otherDeliveryOption,
                                                         vehicle: "", phone: "", helpTypeId: nil, hours: 1)
            print("DELIVERY created=\(delivery) msg=\(model.message)")
            print("AFTER-DELIVERY passes=\((await passes()).joined(separator: "; "))")

            let cab = await model.createPreApproval(type: .cab, name: "",
                                                    vehicle: "1234", phone: "", helpTypeId: nil, hours: 1)
            print("CAB created=\(cab) msg=\(model.message)")

            let help = await model.createPreApproval(type: .visitingHelp, name: "Home repair",
                                                     vehicle: "", phone: "", helpTypeId: "939", hours: 1)
            print("HELP created=\(help) msg=\(model.message)")

            let guest = await model.createPreApproval(type: .guest, name: "Automation Test",
                                                      vehicle: "", phone: config.phone,
                                                      helpTypeId: nil, hours: 1)
            print("GUEST created=\(guest) msg=\(model.message)")
            print("AFTER-GUEST passes=\((await passes()).joined(separator: "; "))")

            await model.loadHistory()
            print("HISTORY stored=\(model.history.entries.count)")
            for entry in model.history.entries.prefix(8) {
                print("  log: \(entry.kind.rawValue) \(entry.title) \(entry.status)")
            }

            var passcode = ""
            if let range = model.message.range(of: "passcode ") {
                passcode = model.message[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let raw = try? await api.myVisitsRaw(),
               let visits = raw["seeker_visits"] as? [[String: Any]],
               let match = visits.first(where: { item in
                   let value = item["passcode"] as? String ?? String(describing: item["passcode"] ?? "")
                   return !passcode.isEmpty && value == passcode
               }),
               let inviteId = match["invite_id"] as? String {
                await model.revokePass(passId: inviteId, seekId: match["seek_id"] as? String)
                print("REVOKE msg=\(model.message)")
                let after = (try? await api.myVisits()) ?? []
                let stillListed = after.contains { $0.passcode == passcode }
                print("REVOKE verified=\(!stillListed) remainingPasses=\(after.count)")
            } else {
                print("REVOKE no guest invite found passcode=\(passcode)")
            }

            exit(0)
        }
        RunLoop.main.run()
        exit(3)
    }
}

enum SelfTest {
    @MainActor
    static func run() {
        MGDiagnostics.hardenExistingLogs()
        let unitFailures = MGUnitTests.run()
        if unitFailures > 0 {
            print("UNIT_TESTS_FAILED")
            exit(1)
        }
        Task { @MainActor in
            let config = MGConfig.load()
            print("CONFIG loggedIn=\(config?.isLoggedIn ?? false) user=\(config?.name ?? "-") flat=\(config?.flatName ?? "-")")
            if let config, config.isLoggedIn {
                do {
                    let pending = try await MGAPI(config: config).pending()
                    print("PENDING \(pending.map { "\($0.validationId) \($0.title)" } ?? "none")")
                    let providers = try await MGAPI(config: config).deliveryProviders()
                    print("PROVIDERS count=\(providers.count) blinkit=\(providers.contains("BLINKIT")) zomato=\(providers.contains("ZOMATO")) swiggy=\(providers.contains("SWIGGY"))")
                } catch {
                    print("PENDING_ERROR \(error.localizedDescription)")
                }
            }
            exit(0)
        }
        RunLoop.main.run()
        exit(3)
    }
}

enum HistorySelftest {
    @MainActor
    static func run() {
        Task { @MainActor in
            guard let config = MGConfig.load(), config.isLoggedIn else { print("HISTORY_FAIL no config"); exit(1) }
            let api = MGAPI(config: config)
            let model = MGModel()
            model.phase = .loggedIn
            await model.loadHistory()
            let store = model.history
            print("HISTORY STORE=\(store.entries.count) LAST24=\(store.last24Hours.count)")
            for entry in store.last24Hours.prefix(5) {
                print("  log:", entry.kind.rawValue, entry.title, entry.status, entry.timeLabel)
            }
            exit(0)
        }
        RunLoop.main.run()
        exit(3)
    }
}

enum HistorySnapshot {
    @MainActor
    static func run(path: String) {
        let model = MGModel()
        model.phase = .loggedIn
        model.historyVisitors = [MGVisitor(id: "1", name: "Delivery Visitor", type: "DELIVERY",
                                           photoURL: nil, passcode: "000000")]
        model.historyPasses = [MGPass(id: "p1", title: "Sample Resident", status: "Pass Expired",
                                      statusColor: "#c4c4c9", passcode: "000000",
                                      timeText: "6:37 PM", detail: "22 Oct 2026 • Valid till 06:37 PM",
                                      isToday: true)]
        let view = HistoryView(model: model)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) \(Int(image.size.width))x\(Int(image.size.height))")
            exit(0)
        }
        print("SNAPSHOT_FAILED"); exit(1)
    }
}


struct FormPreview: View {
    @State var selected: MGModel.PreApprovalType?
    @State var name = ""
    @State var guestPhone = ""
    @State var vehicle = ""
    @State var hours = 2
    @State var helpTypeId: String? = nil
    @ObservedObject var model: MGModel

    init(selected: MGModel.PreApprovalType?, name: String = "", guestPhone: String = "",
         vehicle: String = "", helpTypeId: String? = nil, model: MGModel) {
        _selected = State(initialValue: selected)
        _name = State(initialValue: name)
        _guestPhone = State(initialValue: guestPhone)
        _vehicle = State(initialValue: vehicle)
        _helpTypeId = State(initialValue: helpTypeId)
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text((selected?.label ?? "Form").uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            PreApprovalSection(model: model, staticMode: false, selected: $selected, name: $name,
                               guestPhone: $guestPhone, vehicle: $vehicle, hours: $hours,
                               helpTypeId: $helpTypeId, onCreate: {})
        }
        .padding(16)
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

enum FormSnapshot {
    @MainActor
    static func run(prefix: String) {
        let model = MGModel()
        model.phase = .loggedIn
        model.companies = MGModel.defaultDeliveryCompanies.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        model.helpCategories = [("Home repair", "939"), ("Appliance repair", "968"), ("Beautician", "1197")]

        let cases: [(MGModel.PreApprovalType, String, String, String, String?)] = [
            (.delivery, "ZOMATO", "", "", nil),
            (.cab, "", "", "1234", nil),
            (.guest, "Test Guest", "9876543210", "", nil),
            (.visitingHelp, "Home repair", "", "", "939")
        ]
        for (type, name, phone, vehicle, help) in cases {
            let view = FormPreview(selected: type, name: name, guestPhone: phone,
                                   vehicle: vehicle, helpTypeId: help, model: model)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            let path = "\(prefix)-\(type.rawValue).png"
            try? png.write(to: URL(fileURLWithPath: path))
            print("FORM \(path) \(Int(image.size.width))x\(Int(image.size.height))")
        }
        exit(0)
    }
}

enum Snapshot {
    @MainActor
    static func run(path: String) {
        let model = MGModel()
        model.phase = .loggedIn
        model.config.name = "Sample Resident"
        model.config.buildingName = "T1"
        model.config.flatName = "101"
        model.config.societyName = "Sample Society"
        model.message = ""
        let view = PopoverView(model: model, staticMode: true)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) \(Int(image.size.width))x\(Int(image.size.height))")
            exit(0)
        }
        print("SNAPSHOT_FAILED")
        exit(1)
    }
}

enum PendingPhotoSnapshot {
    @MainActor
    static func run(path: String) {
        let width = 3000, height = 4000
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSColor.black.setFill()
        NSRect(x: 500, y: 700, width: 2000, height: 2600).fill()
        image.unlockFocus()
        let pending = MGPending(validationId: "photo", title: "Zomato Delivery", subtitle: "Delivery",
                                body: "Delivery executive at the main gate", category: "Delivery",
                                time: "5:42 PM", flat: "T1 101", gate: "Main gate",
                                photoURL: URL(string: "https://example.invalid/photo.jpg"))
        let view = PendingPanelView(pending: pending, onApprove: {}, onDeny: {}, onClose: {},
                                    previewImage: image)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let rendered = renderer.nsImage, let tiff = rendered.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("PHOTO_SNAPSHOT \(path) \(Int(rendered.size.width))x\(Int(rendered.size.height))")
            exit(0)
        }
        print("PHOTO_SNAPSHOT_FAILED")
        exit(1)
    }
}

enum PendingSnapshot {
    @MainActor
    static func run(path: String) {
        let pending = MGPending(validationId: "sample", title: "Zomato Delivery", subtitle: "Delivery",
                                body: "Delivery executive at the main gate", category: "Delivery",
                                time: "5:42 PM", flat: "T1 101", gate: "Main gate",
                                photoURL: nil)
        let view = PendingPanelView(pending: pending, onApprove: {}, onDeny: {}, onClose: {})
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) \(Int(image.size.width))x\(Int(image.size.height))")
            exit(0)
        }
        print("SNAPSHOT_FAILED")
        exit(1)
    }
}

let app = NSApplication.shared
nonisolated(unsafe) var appDelegate: AppDelegate?

/// The app delegate is created only for the menu bar app and the demo window.
/// Command-line modes (including --selftest) must not touch the user's session
/// or the Keychain before their tests run.
func startMenuBarApp() {
    MainActor.assumeIsolated {
        appDelegate = AppDelegate()
        app.delegate = appDelegate
        app.setActivationPolicy(.accessory)
    }
    app.run()
}

if CommandLine.arguments.contains("--history-test") {
    MainActor.assumeIsolated { HistoryTest.run() }
} else if CommandLine.arguments.contains("--functional-test") {
    MainActor.assumeIsolated { FunctionalTest.run() }
} else if let index = CommandLine.arguments.firstIndex(of: "--snapshot-forms") {
    let prefix = CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : "/tmp/mygate-form"
    MainActor.assumeIsolated { FormSnapshot.run(prefix: prefix) }
} else if CommandLine.arguments.contains("--selftest-history") {
    MainActor.assumeIsolated { HistorySelftest.run() }
} else if let index = CommandLine.arguments.firstIndex(of: "--snapshot-history") {
    let path = CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : "/tmp/mygate-history.png"
    MainActor.assumeIsolated { HistorySnapshot.run(path: path) }
} else if let index = CommandLine.arguments.firstIndex(of: "--demo-pending-window") {
    let path = CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : "/tmp/mygate-panel-window.png"
    MainActor.assumeIsolated { AppDelegate.demoCapturePath = path }
    startMenuBarApp()
} else if CommandLine.arguments.contains("--selftest") {
    MainActor.assumeIsolated { SelfTest.run() }
} else if let index = CommandLine.arguments.firstIndex(of: "--snapshot-pending-photo") {
    let path = CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : "/tmp/pending-photo.png"
    MainActor.assumeIsolated { PendingPhotoSnapshot.run(path: path) }
} else if let index = CommandLine.arguments.firstIndex(of: "--snapshot-pending") {
    let path = CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : "/tmp/mygate-pending.png"
    MainActor.assumeIsolated { PendingSnapshot.run(path: path) }
} else if let index = CommandLine.arguments.firstIndex(of: "--snapshot") {
    let path = CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : "/tmp/mygate-popover.png"
    MainActor.assumeIsolated { Snapshot.run(path: path) }
} else {
    startMenuBarApp()
}
