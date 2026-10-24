import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @ObservedObject private var location = LocationManager.shared

    @AppStorage(Keys.faceID) private var faceID = false
    @AppStorage(Keys.weekdayTargets) private var targetsRaw = Defaults.weekdayTargetsDefault
    @AppStorage(Keys.visitMinutes) private var visitMinutes = Defaults.visitMinutesDefault
    @AppStorage(Keys.workStart) private var workStart = Defaults.workStartDefault
    @AppStorage(Keys.workEnd) private var workEnd = Defaults.workEndDefault
    @AppStorage(Keys.cycle) private var cycleRaw = Cycle.month.rawValue
    @AppStorage(Keys.speechLocale) private var speechLocale = Defaults.speechLocaleDefault
    @AppStorage(Keys.products) private var productsRaw = Defaults.productsDefault

    @AppStorage(Keys.notifyMorning) private var notifyMorning = true
    @AppStorage(Keys.morningMinutes) private var morningMinutes = Defaults.morningDefault
    @AppStorage(Keys.notifyPreVisit) private var notifyPreVisit = true
    @AppStorage(Keys.preVisitLead) private var preVisitLead = Defaults.preVisitLeadDefault
    @AppStorage(Keys.notifyEndOfDay) private var notifyEndOfDay = true
    @AppStorage(Keys.notifyBackFromLeave) private var notifyBackFromLeave = true
    @AppStorage(Keys.notifyOverdue) private var notifyOverdue = true
    @AppStorage(Keys.notifyWeekly) private var notifyWeekly = true
    @AppStorage(Keys.notifyStatusCheck) private var notifyStatusCheck = false

    @AppStorage(Keys.hasStart) private var hasStart = false
    @AppStorage(Keys.startLat) private var startLat = 0.0
    @AppStorage(Keys.startLng) private var startLng = 0.0
    @AppStorage(Keys.includeStart) private var includeStart = true

    @State private var newProduct = ""
    @State private var confirmErase = false
    @State private var confirmRemoveSamples = false
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: faceIDBinding) {
                        Label("Lock with Face ID", systemImage: "faceid")
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("486 locks when you leave the app. Your passcode works as a fallback.")
                }

                Section {
                    ForEach(weekdayOrder, id: \.self) { wd in
                        Stepper(value: targetBinding(wd), in: 0...40) {
                            HStack {
                                Text(Fmt.weekdayName(wd))
                                Spacer()
                                Text(targetBinding(wd).wrappedValue == 0 ? "Off" : "\(targetBinding(wd).wrappedValue)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                } header: {
                    Text("Daily visit targets")
                } footer: {
                    Text("Your own numbers. Change any single day from Today or the Planner. 0 = no target.")
                }

                Section("Work day") {
                    DatePicker("Start", selection: timeBinding($workStart), displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: timeBinding($workEnd), displayedComponents: .hourAndMinute)
                    Stepper("Default visit: \(visitMinutes) min", value: $visitMinutes, in: 5...60, step: 5)
                    Picker("Map & coverage period", selection: $cycleRaw) {
                        ForEach(Cycle.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                }

                Section {
                    Toggle("Morning brief", isOn: $notifyMorning)
                    if notifyMorning {
                        DatePicker("Time", selection: timeBinding($morningMinutes), displayedComponents: .hourAndMinute)
                    }
                    Toggle("Before each visit", isOn: $notifyPreVisit)
                    if notifyPreVisit {
                        Stepper("\(preVisitLead) min before", value: $preVisitLead, in: 5...60, step: 5)
                    }
                    Toggle("End-of-day wrap up", isOn: $notifyEndOfDay)
                    Toggle("Doctor back from leave", isOn: $notifyBackFromLeave)
                    Toggle("Doctor due for a visit", isOn: $notifyOverdue)
                    Toggle("Sunday evening planning", isOn: $notifyWeekly)
                    Toggle("Status not checked in 2 weeks", isOn: $notifyStatusCheck)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Follow-up reminders you set after visits are always on.")
                }

                Section {
                    Picker("Language", selection: $speechLocale) {
                        ForEach(SpeechLocales.all) { Text($0.title).tag($0.id) }
                    }
                } header: {
                    Text("Voice debrief")
                } footer: {
                    Text("Transcription runs on your iPhone when the language supports it, so it works offline.")
                }

                Section {
                    ForEach(Defaults.parseList(productsRaw), id: \.self) { p in
                        Text(p)
                    }
                    .onDelete { idx in
                        var list = Defaults.parseList(productsRaw)
                        list.remove(atOffsets: idx)
                        productsRaw = list.joined(separator: "|")
                    }
                    HStack {
                        TextField("Add product", text: $newProduct)
                            .onSubmit(addProduct)
                        Button("Add", action: addProduct)
                            .disabled(newProduct.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("My products")
                } footer: {
                    Text("Used for quick tags and to spot products mentioned in your debriefs. Swipe to delete.")
                }

                Section {
                    if hasStart {
                        Label(String(format: "Start point set (%.4f, %.4f)", startLat, startLng), systemImage: "house.fill")
                        Toggle("Include trip from and back to start", isOn: $includeStart)
                    }
                    Button {
                        if let loc = location.location {
                            startLat = loc.coordinate.latitude
                            startLng = loc.coordinate.longitude
                            hasStart = true
                            toast = "Start point saved"
                        } else {
                            location.request()
                            toast = "Getting your location — tap again"
                        }
                    } label: {
                        Label(hasStart ? "Update to my current location" : "Set start point to my current location", systemImage: "location.fill")
                    }
                    if hasStart {
                        Button("Remove start point", role: .destructive) { hasStart = false }
                    }
                } header: {
                    Text("Mileage")
                } footer: {
                    Text("Your home or office. Also used as the first stop when 486 arranges your day.")
                }

                Section("Data") {
                    Button {
                        SampleData.load(into: context)
                        Notifier.reschedule(context: context)
                        toast = "Sample data loaded"
                    } label: { Label("Load sample data", systemImage: "tray.and.arrow.down") }
                    Button(role: .destructive) { confirmRemoveSamples = true } label: {
                        Label("Remove sample data", systemImage: "tray.and.arrow.up")
                    }
                    Button(role: .destructive) { confirmErase = true } label: {
                        Label("Erase everything", systemImage: "trash")
                    }
                }

                Section {
                    HStack {
                        Text("486")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.gradient)
                        Spacer()
                        Text("Version 1.0").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Everything is stored only on this iPhone. Record your own debrief after each visit — don't record doctors without their consent.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Notifier.reschedule(context: context)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .confirmationDialog("Remove all sample hospitals and doctors?", isPresented: $confirmRemoveSamples, titleVisibility: .visible) {
                Button("Remove sample data", role: .destructive) {
                    SampleData.remove(from: context)
                    toast = "Sample data removed"
                }
            }
            .confirmationDialog("Erase all hospitals, doctors, visits, recordings and reminders?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase everything", role: .destructive) {
                    SampleData.eraseAll(context: context)
                    toast = "All data erased"
                }
            } message: {
                Text("This can't be undone.")
            }
            .toast($toast)
        }
    }

    /// Monday first, matching the UAE work week.
    private var weekdayOrder: [Int] { [2, 3, 4, 5, 6, 7, 1] }

    private var faceIDBinding: Binding<Bool> {
        Binding(
            get: { faceID },
            set: { newValue in
                if newValue {
                    LockManager.authenticate(reason: "Turn on Face ID lock for 486") { ok in
                        if ok { faceID = true }
                    }
                } else {
                    faceID = false
                }
            }
        )
    }

    private func targetBinding(_ weekday: Int) -> Binding<Int> {
        Binding(
            get: { Defaults.parseTargets(targetsRaw)[weekday - 1] },
            set: { value in
                var list = Defaults.parseTargets(targetsRaw)
                list[weekday - 1] = value
                targetsRaw = list.map { String($0) }.joined(separator: ",")
            }
        )
    }

    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Date().startOfDay.at(minutes: minutes.wrappedValue) },
            set: { minutes.wrappedValue = $0.minutesOfDay }
        )
    }

    private func addProduct() {
        let p = newProduct.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return }
        var list = Defaults.parseList(productsRaw)
        if !list.contains(where: { $0.caseInsensitiveCompare(p) == .orderedSame }) { list.append(p) }
        productsRaw = list.joined(separator: "|")
        newProduct = ""
    }
}
