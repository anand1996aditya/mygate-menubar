import AppKit
import SwiftUI

enum SelfTest {
    @MainActor
    static func run() {
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

enum PendingSnapshot {
    @MainActor
    static func run(path: String) {
        let pending = MGPending(validationId: "sample", title: "Zomato Delivery", subtitle: "Delivery",
                                body: "Delivery executive at the main gate", category: "Delivery",
                                time: "5:42 PM", flat: "T1 101", gate: "Main gate",
                                photoURL: nil)
        let view = PendingPanelView(pending: pending, onApprove: {}, onDeny: {})
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
MainActor.assumeIsolated {
    appDelegate = AppDelegate()
    app.delegate = appDelegate
    app.setActivationPolicy(.accessory)
}

if let index = CommandLine.arguments.firstIndex(of: "--snapshot-forms") {
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
    app.run()
} else if CommandLine.arguments.contains("--selftest") {
    MainActor.assumeIsolated { SelfTest.run() }
} else if let index = CommandLine.arguments.firstIndex(of: "--snapshot-pending") {
    let path = CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : "/tmp/mygate-pending.png"
    MainActor.assumeIsolated { PendingSnapshot.run(path: path) }
} else if let index = CommandLine.arguments.firstIndex(of: "--snapshot") {
    let path = CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : "/tmp/mygate-popover.png"
    MainActor.assumeIsolated { Snapshot.run(path: path) }
} else {
    app.run()
}
