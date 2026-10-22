import Foundation
import Combine
import SwiftUI

@MainActor
final class MGModel: ObservableObject {
    enum Phase: Equatable { case loggedOut, otpSent, loggedIn }

    @Published var config: MGConfig
    @Published var phase: Phase = .loggedOut
    @Published var pending: MGPending?
    @Published var busy = false
    @Published var message = ""
    @Published var lastChecked: Date?
    @Published var companies: [String] = []
    @Published var helpCategories: [(name: String, typeId: String)] = []
    @Published var historyVisitors: [MGVisitor] = []
    @Published var historyPasses: [MGPass] = []
    let history = MGHistoryStore.shared

    static let otherDeliveryOption = "OTHERS (ANY DELIVERY)"

    static func deliveryOptions(_ companies: [String]) -> [String] {
        var options = companies
        if !options.contains(otherDeliveryOption) {
            options.insert(otherDeliveryOption, at: 0)
        }
        return options
    }

    static func deliveryAddress(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased().contains("OTHERS") || trimmed.uppercased().contains("ANY DELIVERY") {
            return "DELIVERY"
        }
        return trimmed.uppercased()
    }

    static let defaultDeliveryCompanies = [
        "AMAZON", "BIGBASKET", "BLINKIT", "DOMINOS PIZZA", "FLIPKART", "INSTAMART",
        "SWIGGY", "ZEPTO", "ZOMATO"
    ]

    private var lastPendingId: String?

    var onPending: ((MGPending) -> Void)?
    var onPendingCleared: (() -> Void)?

    private var pollTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var seenValidationId: String?

    private var historyCancellable: AnyCancellable?

    init() {
        config = MGConfig.load() ?? MGConfig()
        phase = config.isLoggedIn ? .loggedIn : .loggedOut
        historyCancellable = history.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var statusLine: String {
        if !message.isEmpty { return message }
        if let pending { return "\(pending.title) at the gate" }
        if let lastChecked { return "No visitor waiting · checked \(Self.timeString(lastChecked))" }
        return "Waiting for first check"
    }

    func start() {
        guard phase == .loggedIn, pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkPending()
                try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
            }
        }
        historyTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.loadHistory()
                try? await Task.sleep(nanoseconds: 300 * 1_000_000_000)
            }
        }
    }

    func stop() {
        pollTask?.cancel(); pollTask = nil
        historyTask?.cancel(); historyTask = nil
    }

    func sendOTP(phone: String) async {
        let number = MGModel.normalizePhone(phone)
        guard number.count == 10 else { message = "Enter a 10-digit mobile number"; return }
        busy = true; message = ""
        defer { busy = false }
        do {
            _ = try await MGAPI.validate(config, phone: number)
            config.phone = number
            config.save()
            phase = .otpSent
            message = "OTP sent to \(number)"
        } catch {
            message = "Could not send OTP: \(error.localizedDescription)"
        }
    }

    func verifyOTP(_ otp: String) async {
        let code = MGModel.normalizeOTP(otp)
        guard code.count == 6 else { message = "Enter the 6-digit OTP"; return }
        busy = true; message = ""
        defer { busy = false }
        do {
            let (apiKey, userId) = try await MGAPI.login(config, phone: config.phone, otp: code)
            config.apiKey = apiKey
            config.userId = userId
            let profile = try await MGAPI.profile(config)
            apply(profile: profile)
            config.save()
            phase = .loggedIn
            message = "Signed in as \(config.name) · \(config.flatName)"
            await loadPreApproveLists()
            start()
            await checkPending()
        } catch {
            message = "Login failed: \(error.localizedDescription)"
        }
    }

    private func apply(profile: [String: Any]) {
        config.name = (profile["name"] as? String) ?? config.name
        if let flats = profile["flats"] as? [[String: Any]], let flat = flats.first {
            config.flatId = (flat["flatid"] as? String) ?? ""
            config.flatName = (flat["flatname"] as? String) ?? ""
            config.buildingName = (flat["buildingname"] as? String) ?? ""
            config.societyName = (flat["societyname"] as? String) ?? ""
            config.societyId = (flat["societyid"] as? String) ?? ""
        }
    }

    func checkPending() async {
        guard phase == .loggedIn, config.isLoggedIn else { return }
        let api = MGAPI(config: config)
        do {
            let found = try await api.pending()
            lastChecked = Date()
            message = ""
            if let found {
                if found.validationId != seenValidationId {
                    seenValidationId = found.validationId
                    lastPendingId = found.validationId
                    pending = found
                    history.recordGate(found)
                    onPending?(found)
                }
            } else if pending != nil {
                pending = nil
                if let lastPendingId {
                    history.updateGate(validationId: lastPendingId, status: "Cleared")
                }
                lastPendingId = nil
                onPendingCleared?()
            }
        } catch {
            message = error.localizedDescription
            MGDiagnostics.append("pending error: \(error.localizedDescription)")
        }
    }

    func approve(_ pending: MGPending) async {
        busy = true; message = ""
        defer { busy = false }
        do {
            try await MGAPI(config: config).approve(pending)
            MGDiagnostics.append("approve ok id=\(pending.validationId)")
            history.updateGate(validationId: pending.validationId, status: "Approved")
            lastPendingId = nil
            message = "Approved \(pending.title)"
            self.pending = nil
            onPendingCleared?()
        } catch {
            MGDiagnostics.append("approve failed id=\(pending.validationId) error=\(error.localizedDescription)")
            message = "Approve failed: \(error.localizedDescription)"
        }
    }

    func reject(_ pending: MGPending, reason: String = "Not expecting") async {
        busy = true; message = ""
        defer { busy = false }
        do {
            try await MGAPI(config: config).reject(pending, reason: reason)
            MGDiagnostics.append("reject ok id=\(pending.validationId)")
            history.updateGate(validationId: pending.validationId, status: "Denied")
            lastPendingId = nil
            message = "Denied \(pending.title)"
            self.pending = nil
            onPendingCleared?()
        } catch {
            MGDiagnostics.append("reject failed id=\(pending.validationId) error=\(error.localizedDescription)")
            message = "Deny failed: \(error.localizedDescription)"
        }
    }

    static func normalizeCabDigits(_ raw: String) -> String {
        String(raw.filter(\.isNumber).prefix(4))
    }

    static func normalizePhone(_ raw: String) -> String {
        var digits = raw.filter(\.isNumber)
        if digits.count == 12 && digits.hasPrefix("91") { digits = String(digits.dropFirst(2)) }
        if digits.count == 11 && digits.hasPrefix("0") { digits = String(digits.dropFirst()) }
        return String(digits.prefix(10))
    }

    static func normalizeOTP(_ raw: String) -> String {
        String(raw.filter(\.isNumber).prefix(6))
    }

    enum PreApprovalType: String, CaseIterable, Identifiable {
        case guest, delivery, cab, visitingHelp
        var id: String { rawValue }
        var actionTitle: String {
            self == .guest ? "Send invite" : "Pre-approve"
        }

        var label: String {
            switch self {
            case .guest: return "Guest"
            case .delivery: return "Delivery"
            case .cab: return "Cab"
            case .visitingHelp: return "Visiting Help"
            }
        }
        var userTypeId: String {
            switch self {
            case .guest: return "1213"
            case .delivery: return "1008"
            case .cab: return "1022"
            case .visitingHelp: return "1026"
            }
        }
        var symbol: String {
            switch self {
            case .guest: return "person.fill"
            case .delivery: return "shippingbox.fill"
            case .cab: return "car.fill"
            case .visitingHelp: return "wrench.and.screwdriver.fill"
            }
        }
    }

    @discardableResult
    func createPreApproval(type: PreApprovalType, name: String, vehicle: String,
                           phone: String, helpTypeId: String?, hours: Int) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        switch type {
        case .guest:
            guard !trimmedName.isEmpty else { message = "Enter the guest name"; return false }
            guard MGModel.normalizePhone(phone).count == 10 else { message = "Enter a 10-digit mobile number"; return false }
        case .delivery:
            guard !trimmedName.isEmpty else { message = "Select a delivery company"; return false }
        case .cab:
            guard MGModel.normalizeCabDigits(vehicle).count == 4 else { message = "Enter the last four digits of the cab number"; return false }
        case .visitingHelp:
            guard !trimmedName.isEmpty, helpTypeId != nil else { message = "Select a visiting help category"; return false }
        }
        busy = true; message = ""
        defer { busy = false }
        let api = MGAPI(config: config)
        let now = Int(Date().timeIntervalSince1970)
        let end = now + hours * 3600
        do {
            switch type {
            case .guest:
                message = try await api.inviteGuest(name: trimmedName, mobile: MGModel.normalizePhone(phone), start: now, end: end)
            default:
                let addressName = type == .delivery ? MGModel.deliveryAddress(trimmedName) : trimmedName
                try await api.preApprove(type: type, name: addressName,
                                         vehicle: MGModel.normalizeCabDigits(vehicle),
                                         userTypeId: helpTypeId, start: now, end: end)
                message = "Pre-approved \(type.label) for \(hours)h"
            }
            return true
        } catch {
            message = "Pre-approval failed: \(error.localizedDescription)"
            return false
        }
    }

    func revokePass(passId: String, seekId: String?) async {
        guard phase == .loggedIn else { return }
        busy = true; message = ""
        defer { busy = false }
        do {
            try await MGAPI(config: config).deleteVisit(inviteId: passId, seekId: seekId)
            MGDiagnostics.append("pass revoked id=\(passId)")
            history.updateStatus(id: "p:\(passId)", status: "Revoked")
            message = "Pass revoked"
            await loadHistory()
        } catch {
            MGDiagnostics.append("pass revoke failed id=\(passId) error=\(error.localizedDescription)")
            message = "Revoke failed: \(error.localizedDescription)"
        }
    }

    static func feedTitle(_ card: MGFeedCard) -> String {
        switch card.cardType.uppercased() {
        case "DELIVERY": return "Delivery"
        case "CAB": return "Cab"
        case "VISITORS": return "Visiting Help"
        case "GUEST": return card.name.isEmpty ? "Guest invite" : "Guest invite – \(card.name)"
        default: return card.name.isEmpty ? card.cardType.capitalized : card.name
        }
    }

    func revokeHistoryEntry(_ entry: MGHistoryEntry) async {
        guard phase == .loggedIn else { return }
        busy = true; message = ""
        defer { busy = false }
        do {
            if let cancelId = entry.cancelId, entry.id.hasPrefix("f:") {
                try await MGAPI(config: config).cancelPreApproval(gateMessageId: cancelId, ntype: entry.cancelNtype)
                MGDiagnostics.append("preapproval cancelled id=\(entry.id) gateMessage=\(cancelId)")
                history.updateStatus(id: entry.id, status: "Cancelled")
                message = "Pre-approval cancelled"
            } else if entry.id.hasPrefix("p:") {
                let passId = String(entry.id.dropFirst(2))
                try await MGAPI(config: config).deleteVisit(inviteId: passId, seekId: nil)
                MGDiagnostics.append("pass revoked id=\(passId)")
                history.updateStatus(id: entry.id, status: "Revoked")
                message = "Pass revoked"
            } else {
                return
            }
            await loadHistory()
        } catch {
            MGDiagnostics.append("revoke failed id=\(entry.id) error=\(error.localizedDescription)")
            message = "Revoke failed: \(error.localizedDescription)"
        }
    }

    func loadHistory() async {
        guard phase == .loggedIn else { return }
        let api = MGAPI(config: config)
        let visitors = (try? await api.currentVisitors()) ?? []
        let passes = (try? await api.myVisits()) ?? []
        historyVisitors = visitors
        historyPasses = passes
        var currentKeys = Set<String>()
        for visitor in visitors {
            let key = "v:\(visitor.name.lowercased())|\(visitor.type.lowercased())|\(MGHistoryStore.dayKey())"
            currentKeys.insert(key)
            history.recordVisitor(name: visitor.name, type: visitor.type,
                                  passcode: visitor.passcode, photoURL: visitor.photoURL?.absoluteString)
        }
        history.markVisitorsLeft(except: currentKeys)
        for pass in passes {
            let title = pass.title == config.name ? "Guest invite" : pass.title
            history.recordPass(id: pass.id, title: title, status: pass.status,
                               timeText: pass.timeText, detail: pass.detail,
                               passcode: pass.passcode)
        }
        var feedCards: [String: MGFeedCard] = [:]
        for day in 0...3 {
            let date = day == 0 ? nil : Date().addingTimeInterval(-Double(day) * 86_400)
            if let cards = try? await api.activityFeed(date: date) {
                for card in cards { feedCards[card.id] = card }
            }
        }
        for card in feedCards.values {
            history.recordFeedCard(id: card.id, title: Self.feedTitle(card),
                                   subtitle: card.detail.isEmpty ? card.cardType.capitalized : card.detail,
                                   status: card.status, timestamp: card.timestamp,
                                   cancelId: card.cancelId, cancelNtype: card.ntype)
        }
        MGDiagnostics.append("history visitors=\(visitors.count) passes=\(passes.count) feed=\(feedCards.count) stored=\(history.entries.count)")
    }

    func loadPreApproveLists() async {
        guard phase == .loggedIn else { return }
        let api = MGAPI(config: config)
        if let providers = try? await api.deliveryProviders() {
            companies = providers.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        if let info = try? await api.preApproveInfo() {
            if companies.isEmpty {
                companies = info.companies.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            }
            helpCategories = info.categories.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        if companies.isEmpty {
            companies = MGModel.defaultDeliveryCompanies
        }
    }

    func createDeliveryPreApproval(company: String, hours: Int) async {
        busy = true; message = ""
        defer { busy = false }
        let now = Int(Date().timeIntervalSince1970)
        let end = now + hours * 3600
        do {
            try await MGAPI(config: config).preApproveDelivery(company: company, start: now, end: end)
            message = "Pre-approved \(company.uppercased()) for \(hours)h"
        } catch {
            message = "Pre-approval failed: \(error.localizedDescription)"
        }
    }

    func signOut() {
        stop()
        config = MGConfig()
        config.save()
        phase = .loggedOut
        pending = nil
        seenValidationId = nil
        lastPendingId = nil
        onPendingCleared?()
        message = "Signed out"
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        return formatter.string(from: date)
    }
}
