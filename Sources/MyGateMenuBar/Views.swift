import SwiftUI
import AppKit

private let MGFieldHeight: CGFloat = 40

private enum Brand {
    static let yellow = Color(red: 1.00, green: 0.79, blue: 0.00)
    static let ink = Color(white: 0.10)
    static let green = Color(red: 0.13, green: 0.66, blue: 0.36)
    static let orange = Color(red: 0.95, green: 0.52, blue: 0.13)
}

private func brandLogo(size: CGFloat) -> some View {
    Group {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("BrandLogo.png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 6).fill(Brand.yellow)
        }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
}

private func gateMark(size: CGFloat) -> some View {
    Group {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("MenuIcon.png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().renderingMode(.template).scaledToFit()
        } else {
            Image(systemName: "door.left.hand.closed").resizable().scaledToFit()
        }
    }
    .frame(width: size, height: size)
}

struct PopoverView: View {
    @ObservedObject var model: MGModel
    var staticMode = false
    @State private var phone = ""
    @State private var otp = ""
    @State private var selectedType: MGModel.PreApprovalType? = .delivery
    @State private var name = ""
    @State private var guestPhone = ""
    @State private var vehicle = ""
    @State private var helpTypeId: String?
    @State private var hours = 1
    @State private var showHistory = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            VStack(spacing: 14) {
                if model.phase == .loggedIn, showHistory {
                    HistoryView(model: model)
                } else if model.phase == .loggedIn {
                    HeroCard(model: model)
                    PreApprovalSection(model: model,
                                       staticMode: staticMode,
                                       selected: $selectedType,
                                       name: $name,
                                       guestPhone: $guestPhone,
                                       vehicle: $vehicle,
                                       hours: $hours,
                                       helpTypeId: $helpTypeId,
                                       onCreate: createPreApproval)
                    if !model.message.isEmpty {
                        Text(model.message)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                    }
                } else {
                    LoginCard(model: model, staticMode: staticMode, phone: $phone, otp: $otp)
                }
            }
            .padding(.vertical, 14)
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 420)
        .background(.regularMaterial)
        .animation(.easeInOut(duration: 0.25), value: model.pending?.validationId)
        .animation(.easeInOut(duration: 0.2), value: selectedType)
        .onAppear {
            phone = model.config.phone
            Task { await model.loadPreApproveLists() }
        }
    }

    private func createPreApproval() {
        guard let type = selectedType else { return }
        Task {
            let created = await model.createPreApproval(type: type, name: name, vehicle: vehicle,
                                                        phone: guestPhone, helpTypeId: helpTypeId, hours: hours)
            if created {
                selectedType = nil
                name = ""
                guestPhone = ""
                vehicle = ""
                helpTypeId = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            brandLogo(size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("MyGate")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(flatLine)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if model.phase == .loggedIn { statusPill }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var flatLine: String {
        guard model.phase == .loggedIn else { return "Not signed in" }
        let flat = [model.config.buildingName, model.config.flatName].filter { !$0.isEmpty }.joined(separator: " ")
        return [flat, model.config.societyName].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle().fill(model.pending == nil ? Brand.green : Brand.orange).frame(width: 6, height: 6)
            Text(model.pending == nil ? "LIVE" : "VISITOR")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(model.pending == nil ? Brand.green : Brand.orange)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background((model.pending == nil ? Brand.green : Brand.orange).opacity(0.10), in: Capsule())
    }

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(model.phase == .loggedIn ? model.config.name : "SECUREU")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.phase == .loggedIn {
                Button {
                    showHistory.toggle()
                    if showHistory { Task { await model.loadHistory() } }
                } label: {
                    Text(showHistory ? "Home" : "History")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    Task {
                        await model.checkPending()
                        await model.loadHistory()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(model.busy)
                Button {
                    model.signOut()
                } label: {
                    Text("Sign out")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
    }
}

struct HeroCard: View {
    @ObservedObject var model: MGModel

    var body: some View {
        if let pending = model.pending { pendingCard(pending) } else { clearCard }
    }

    private func pendingCard(_ pending: MGPending) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                visitorPhoto(pending)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(pending.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text([pending.subtitle, pending.time].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if !pending.category.isEmpty { chip(pending.category) }
                        if !pending.gate.isEmpty { chip(pending.gate) }
                    }
                }
                Spacer()
            }
            if !model.message.isEmpty {
                Text(model.message)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                Button { Task { await model.reject(pending) } } label: {
                    Text("Deny")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(Color.red.opacity(0.08), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.busy)
                Button { Task { await model.approve(pending) } } label: {
                    Text(model.busy ? "Working…" : "Approve")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(Brand.green.opacity(model.busy ? 0.5 : 1), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.busy)
            }
        }
        .padding(12)
        .background(LinearGradient(colors: [Brand.orange.opacity(0.14), Brand.yellow.opacity(0.06)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Brand.orange.opacity(0.18), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private var clearCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Brand.green.opacity(0.10)).frame(width: 46, height: 46)
                gateMark(size: 20).foregroundStyle(Brand.green)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Gate is clear")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(model.statusLine)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 16))
                .foregroundStyle(Brand.green.opacity(0.7))
        }
        .padding(14)
        .background(LinearGradient(colors: [Brand.green.opacity(0.08), Brand.yellow.opacity(0.05)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Brand.green.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    @ViewBuilder private func visitorPhoto(_ pending: MGPending) -> some View {
        if let url = pending.photoURL {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { photoPlaceholder }
            }
        } else { photoPlaceholder }
    }

    private var photoPlaceholder: some View {
        ZStack { Color.gray.opacity(0.15); Image(systemName: "person.fill").foregroundStyle(.secondary) }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Color.secondary.opacity(0.10), in: Capsule())
    }
}

struct PreApprovalSection: View {
    @ObservedObject var model: MGModel
    var staticMode: Bool
    @Binding var selected: MGModel.PreApprovalType?
    @Binding var name: String
    @Binding var guestPhone: String
    @Binding var vehicle: String
    @Binding var hours: Int
    @Binding var helpTypeId: String?
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ALLOW FUTURE ENTRIES")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                Spacer()
                Text("Skip the approval call")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                ForEach(MGModel.PreApprovalType.allCases) { type in tile(type) }
            }

            if let selected {
                VStack(spacing: 10) {
                    form(for: selected)
                    HStack(spacing: 8) {
                        durationMenu
                        Button(action: onCreate) {
                            Text(actionLabel)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Brand.ink)
                                .padding(.horizontal, 16)
                                .frame(height: MGFieldHeight)
                                .background(Brand.yellow.opacity(canSubmit ? 1 : 0.45), in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit || model.busy)
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Text("Pre-approval lets a visitor enter without a gate call.")
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
    }

    private var actionLabel: String {
        selected?.actionTitle ?? "Pre-approve"
    }

    private var canSubmit: Bool {
        guard let selected else { return false }
        switch selected {
        case .guest:
            return !name.trimmingCharacters(in: .whitespaces).isEmpty && MGModel.normalizePhone(guestPhone).count == 10
        case .delivery:
            return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .cab:
            return vehicle.filter(\.isNumber).count == 4
        case .visitingHelp:
            return !name.isEmpty && helpTypeId != nil
        }
    }

    @ViewBuilder private func form(for type: MGModel.PreApprovalType) -> some View {
        switch type {
        case .guest:
            HStack(spacing: 8) {
                textField("Guest name", text: $name)
                guestMobileField
            }
        case .delivery:
            dropdown(title: name.isEmpty ? "Select delivery company" : name,
                     options: model.companies,
                     onPick: { name = $0 },
                     searchable: true,
                     isPlaceholder: name.isEmpty)
        case .cab:
            CabCodeField(code: $vehicle)
        case .visitingHelp:
            dropdown(title: helpTitle, options: model.helpCategories.map(\.name),
                     onPick: { picked in
                         if let match = model.helpCategories.first(where: { $0.name == picked }) {
                             helpTypeId = match.typeId
                         }
                         name = picked
                     },
                     isPlaceholder: name.isEmpty)
        }
    }

    private var guestMobileField: some View {
        let filtered = Binding(
            get: { guestPhone },
            set: { guestPhone = MGModel.normalizePhone($0) }
        )
        return textField("Mobile number", text: filtered)
    }

    private var helpTitle: String {
        if !name.isEmpty, selected == .visitingHelp { return name }
        return "Select visiting help category"
    }

    private func textField(_ placeholder: String, text: Binding<String>) -> some View {
        Group {
            if staticMode {
                HStack {
                    Text(placeholder).font(.system(size: 12, design: .rounded)).foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .rounded))
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: MGFieldHeight)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func dropdown(title: String, options: [String], onPick: @escaping (String) -> Void,
                          searchable: Bool = false, isPlaceholder: Bool) -> some View {
        PopupField(options: options, onPick: onPick) {
            HStack {
                Text(options.isEmpty ? "Loading…" : title)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(options.isEmpty ? Color.secondary.opacity(0.7)
                                     : (isPlaceholder ? Color.secondary : Color.primary))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: MGFieldHeight)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }

    private var durationMenu: some View {
        let values = [1, 2, 4, 8, 12, 24]
        let titles = values.map { $0 == 24 ? "24 hours" : "\($0) hour\($0 == 1 ? "" : "s")" }
        return PopupField(options: titles, onPick: { picked in
            if let index = titles.firstIndex(of: picked) { hours = values[index] }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(hours == 24 ? "24 hours" : "\(hours) hour\(hours == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: MGFieldHeight)
            .background(Color.secondary.opacity(0.08), in: Capsule())
            .contentShape(Capsule())
        }
    }

    private func tile(_ type: MGModel.PreApprovalType) -> some View {
        let isSelected = selected == type
        return Button {
            selected = isSelected ? nil : type
            name = ""
            guestPhone = ""
            vehicle = ""
            helpTypeId = nil
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle().fill(isSelected ? Brand.yellow : Color.secondary.opacity(0.08)).frame(width: 36, height: 36)
                    Image(systemName: type.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Brand.ink : .secondary)
                }
                Text(type.label)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct CabCodeField: View {
    @Binding var code: String
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { index in
                    box(index)
                }
            }
            TextField("", text: Binding(
                get: { code },
                set: { code = MGModel.normalizeCabDigits($0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 18, weight: .semibold, design: .monospaced))
            .foregroundStyle(.clear)
            .tint(.clear)
            .focused($focused)
            .opacity(0.03)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    private func box(_ index: Int) -> some View {
        let character = index < code.count ? String(Array(code)[index]) : ""
        let isNext = focused && code.count == index
        return Text(character)
            .font(.system(size: 18, weight: .semibold, design: .monospaced))
            .frame(maxWidth: .infinity)
            .frame(height: MGFieldHeight)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isNext ? Brand.orange : Color.secondary.opacity(0.15),
                            lineWidth: isNext ? 1.5 : 1)
            )
    }
}

final class PopupMenuAction: NSObject {
    var handler: ((String) -> Void)?
    @objc func fire(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String { handler?(value) }
    }
}

struct PopupField<Label: View>: View {
    let options: [String]
    let onPick: (String) -> Void
    @ViewBuilder var label: () -> Label
    @State private var action = PopupMenuAction()

    var body: some View {
        Button {
            guard !options.isEmpty else { return }
            action.handler = onPick
            let menu = NSMenu()
            for option in options {
                let item = NSMenuItem(title: option, action: #selector(PopupMenuAction.fire(_:)), keyEquivalent: "")
                item.target = action
                item.representedObject = option
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        } label: {
            label()
        }
        .buttonStyle(.plain)
    }
}

struct LoginCard: View {
    @ObservedObject var model: MGModel
    var staticMode: Bool
    @Binding var phone: String
    @Binding var otp: String

    var body: some View {
        VStack(spacing: 12) {
            brandLogo(size: 56).padding(.top, 6)
            VStack(spacing: 3) {
                Text("Welcome to MyGate")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(model.phase == .otpSent ? "Enter the OTP sent to \(model.config.phone)" : "Sign in with your registered mobile number")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if model.phase == .otpSent {
                digitsInput("OTP", text: $otp, limit: 6)
                HStack(spacing: 8) {
                    primaryButton("Verify", enabled: otp.count == 6 && !model.busy) {
                        Task { await model.verifyOTP(otp) }
                    }
                    Button {
                        Task { await model.sendOTP(phone: model.config.phone) }
                    } label: {
                        Text("Resend")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.busy)
                }
            } else {
                digitsInput("Mobile number", text: $phone, limit: 10)
                primaryButton("Send OTP", enabled: phone.count == 10 && !model.busy) {
                    Task { await model.sendOTP(phone: phone) }
                }
            }
            if !model.message.isEmpty {
                Text(model.message)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(18)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 16)
    }

    @ViewBuilder private func input(_ placeholder: String, text: Binding<String>) -> some View {
        if staticMode {
            HStack {
                Text(placeholder).font(.system(size: 13, design: .rounded)).foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: MGFieldHeight)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .rounded))
                .padding(.horizontal, 12)
                .frame(height: MGFieldHeight)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func primaryButton(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Brand.yellow.opacity(enabled ? 1 : 0.4), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    @ViewBuilder private func digitsInput(_ placeholder: String, text: Binding<String>, limit: Int) -> some View {
        let filtered = Binding(
            get: { text.wrappedValue },
            set: { raw in
                text.wrappedValue = limit == 10
                    ? MGModel.normalizePhone(raw)
                    : String(raw.filter(\.isNumber).prefix(limit))
            }
        )
        input(placeholder, text: filtered)
    }
}

struct HistoryView: View {
    @ObservedObject var model: MGModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Today at the gate")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Text(Date().formatted(.dateTime.day().month(.abbreviated)))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            section("INSIDE NOW")
            if model.historyVisitors.isEmpty {
                emptyRow("No one is inside right now")
            } else {
                ForEach(model.historyVisitors) { visitor in
                    HStack(spacing: 10) {
                        photo(url: visitor.photoURL)
                            .frame(width: 34, height: 34)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(visitor.name)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Text(visitor.type.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !visitor.passcode.isEmpty {
                            Text(visitor.passcode)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            section("GATE LOG (3 DAYS)")
            let log = model.history.entries
            if log.isEmpty {
                emptyRow("No gate activity recorded yet")
            } else {
                ForEach(log.prefix(30)) { entry in
                    HStack(spacing: 8) {
                        Image(systemName: entry.kind == .gate ? "bell.fill" : (entry.kind == .visitor ? "person.fill" : "ticket.fill"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.title)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .lineLimit(1)
                            Text(entry.subtitle.isEmpty ? entry.kind.rawValue.capitalized : entry.subtitle)
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(entry.status)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text(entry.timeLabel)
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Divider().opacity(0.3)
                }
            }

            Text("Stored locally for up to three days.")
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { Task { await model.loadHistory() } }
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .tracking(0.6)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, design: .rounded))
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder private func photo(url: URL?) -> some View {
        if let url {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { Color.gray.opacity(0.2) }
            }
        } else {
            ZStack { Color.gray.opacity(0.2); Image(systemName: "person.fill").font(.system(size: 13)).foregroundStyle(.secondary) }
        }
    }
}

struct PendingPanelView: View {
    let pending: MGPending
    var errorText: String? = nil
    let onApprove: () -> Void
    let onDeny: () -> Void
    @State private var busy = false

    var body: some View {
        ZStack(alignment: .bottom) {
            photo
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.15), .black.opacity(0.55)],
                                        startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("VISITOR AT GATE", systemImage: "bell.badge.fill")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.black.opacity(0.35), in: Capsule())
                    Spacer()
                    Text(pending.time)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text(pending.title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text([pending.subtitle, pending.body].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let errorText, !errorText.isEmpty {
                    Text(errorText)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Button {
                        busy = true
                        onDeny()
                    } label: {
                        Group {
                            if busy {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Text("Deny")
                            }
                        }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(.white.opacity(0.18), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                    Button {
                        busy = true
                        onApprove()
                    } label: {
                        Group {
                            if busy {
                                ProgressView().controlSize(.small).tint(Brand.ink)
                            } else {
                                Text("Approve")
                            }
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Brand.yellow, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
            }
            .padding(18)
        }
        .frame(width: 400, height: 620)
        .background(.black)
        .ignoresSafeArea()
    }

    @ViewBuilder private var photo: some View {
        if let url = pending.photoURL {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { placeholder }
            }
        } else { placeholder }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.18), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 10) {
                Image(systemName: "person.crop.square.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.white.opacity(0.35))
                Text("Photo not shared by guard")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}
