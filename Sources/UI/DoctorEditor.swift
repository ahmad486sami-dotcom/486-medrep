import SwiftUI
import SwiftData
import PhotosUI

struct DoctorDraft {
    var name = ""
    var specialty = ""
    var department = ""
    var room = ""
    var phone = ""
    var phone2 = ""
    var email = ""
    var assistantName = ""
    var priority = "B"
    var language = "English"
    var products: Set<String> = []
    var generalNote = ""
    var visitEveryDays = 14
    var availability: [AvailabilityWindow] = []
    var photoData: Data?
    var importantDates = ""
    var hospitalID: UUID?

    init() {}

    init(from d: Doctor) {
        name = d.name
        specialty = d.specialty
        department = d.department
        room = d.room
        phone = d.phone
        phone2 = d.phone2
        email = d.email
        assistantName = d.assistantName
        priority = d.priority
        language = d.language
        products = Set(d.products)
        generalNote = d.generalNote
        visitEveryDays = d.visitEveryDays
        availability = d.availability
        photoData = d.photoData
        importantDates = d.importantDates
        hospitalID = d.hospital?.id
    }

    func apply(to d: Doctor, hospitals: [Hospital]) {
        d.name = name.trimmingCharacters(in: .whitespaces)
        d.specialty = specialty
        d.department = department
        d.room = room
        d.phone = phone
        d.phone2 = phone2
        d.email = email.trimmingCharacters(in: .whitespaces)
        d.assistantName = assistantName
        d.priority = priority
        d.language = language
        d.products = products.sorted()
        d.generalNote = generalNote
        d.visitEveryDays = visitEveryDays
        d.availability = availability
        d.photoData = photoData
        d.importantDates = importantDates
        let h = hospitals.first { $0.id == hospitalID }
        if d.hospital?.id != h?.id { d.hospital = h }
    }
}

struct DoctorEditor: View {
    var doctor: Doctor?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Hospital.name) private var hospitals: [Hospital]
    @AppStorage(Keys.products) private var productsRaw = Defaults.productsDefault

    @State private var draft: DoctorDraft
    @State private var photoItem: PhotosPickerItem?
    @State private var showWindowEditor = false
    @State private var showNewHospital = false

    init(doctor: Doctor? = nil, hospital: Hospital? = nil) {
        self.doctor = doctor
        var d = doctor.map { DoctorDraft(from: $0) } ?? DoctorDraft()
        if doctor == nil { d.hospitalID = hospital?.id }
        _draft = State(initialValue: d)
    }

    private var productOptions: [String] {
        var list = Defaults.parseList(productsRaw)
        for p in draft.products where !list.contains(p) { list.append(p) }
        return list
    }

    private var specialtyOptions: [String] {
        var list = Specialties.all
        if !draft.specialty.isEmpty && !list.contains(draft.specialty) { list.insert(draft.specialty, at: 0) }
        return list
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            ZStack(alignment: .bottomTrailing) {
                                if let data = draft.photoData, let img = UIImage(data: data) {
                                    Image(uiImage: img).resizable().scaledToFill()
                                        .frame(width: 72, height: 72).clipShape(Circle())
                                } else {
                                    Circle().fill(Theme.gradient).frame(width: 72, height: 72)
                                        .overlay(Image(systemName: "person.fill").font(.title).foregroundStyle(.white))
                                }
                                Image(systemName: "camera.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color.white, Theme.accent)
                            }
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading) {
                            TextField("Full name", text: $draft.name)
                                .font(.title3.weight(.semibold))
                                .textInputAutocapitalization(.words)
                            Text("“Dr.” is added automatically").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Work") {
                    Picker("Hospital", selection: $draft.hospitalID) {
                        Text("None").tag(UUID?.none)
                        ForEach(hospitals) { h in Text(h.name).tag(Optional(h.id)) }
                    }
                    Button { showNewHospital = true } label: {
                        Label("New hospital", systemImage: "plus")
                    }
                    Picker("Specialty", selection: $draft.specialty) {
                        Text("—").tag("")
                        ForEach(specialtyOptions, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Department", text: $draft.department)
                    TextField("Room / clinic number", text: $draft.room)
                }

                Section("Contact") {
                    TextField("Phone (tap to call, WhatsApp)", text: $draft.phone).keyboardType(.phonePad)
                    TextField("Second number", text: $draft.phone2).keyboardType(.phonePad)
                    TextField("Email", text: $draft.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Assistant / nurse name", text: $draft.assistantName)
                }

                Section {
                    Picker("Priority", selection: $draft.priority) {
                        Text("A").tag("A")
                        Text("B").tag("B")
                        Text("C").tag("C")
                    }
                    .pickerStyle(.segmented)
                    Stepper(value: $draft.visitEveryDays, in: 0...90, step: 7) {
                        HStack {
                            Text("Visit every")
                            Spacer()
                            Text(draft.visitEveryDays == 0 ? "No target" : "\(draft.visitEveryDays) days")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Picker("Language", selection: $draft.language) {
                        Text("English").tag("English")
                        Text("Arabic").tag("Arabic")
                        Text("Both").tag("Both")
                    }
                } header: {
                    Text("Visiting")
                } footer: {
                    Text("You decide how often to see each doctor. 486 reminds you when they're due.")
                }

                Section {
                    ForEach(draft.availability.sorted { ($0.weekday, $0.startMinutes) < ($1.weekday, $1.startMinutes) }) { w in
                        HStack {
                            Text(Fmt.weekdayName(w.weekday))
                            Spacer()
                            Text(w.timeLabel).foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                draft.availability.removeAll { $0.id == w.id }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    Button { showWindowEditor = true } label: {
                        Label("Add clinic time", systemImage: "clock.badge.plus")
                    }
                } header: {
                    Text("Clinic times")
                } footer: {
                    Text("Morning and evening clinics can be added separately. Swipe to delete.")
                }

                Section("Products") {
                    FlowLayout {
                        ForEach(productOptions, id: \.self) { p in
                            Chip(title: p, selected: draft.products.contains(p)) { draft.products.toggle(p) }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("General note") {
                    TextField("Preferences, best approach, things to remember…", text: $draft.generalNote, axis: .vertical)
                        .lineLimit(3...10)
                }

                Section("Important dates") {
                    TextField("e.g. Birthday 12 Mar", text: $draft.importantDates)
                }
            }
            .navigationTitle(doctor == nil ? "New doctor" : "Edit doctor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showWindowEditor) {
                WindowEditor { windows in draft.availability.append(contentsOf: windows) }
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showNewHospital) { HospitalEditor() }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { @MainActor in
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        draft.photoData = Self.downscale(data)
                    }
                }
            }
            .onChange(of: hospitals.count) { old, new in
                if new > old, draft.hospitalID == nil, let newest = hospitals.max(by: { $0.createdAt < $1.createdAt }) {
                    draft.hospitalID = newest.id
                }
            }
        }
    }

    static func downscale(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = CGSize(width: 300, height: 300)
        let thumb = image.preparingThumbnail(of: size) ?? image
        return thumb.jpegData(compressionQuality: 0.8)
    }

    private func save() {
        if let doctor {
            draft.apply(to: doctor, hospitals: hospitals)
        } else {
            let d = Doctor(name: draft.name)
            d.statusCheckedAt = Date()
            context.insert(d)
            draft.apply(to: d, hospitals: hospitals)
        }
        try? context.save()
        Notifier.reschedule(context: context)
        dismiss()
    }
}

// MARK: - Clinic time editor

struct WindowEditor: View {
    var onAdd: ([AvailabilityWindow]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var days: Set<Int> = [2]
    @State private var start = Date().startOfDay.at(minutes: 9 * 60)
    @State private var end = Date().startOfDay.at(minutes: 12 * 60)

    var body: some View {
        NavigationStack {
            Form {
                Section("Days") {
                    FlowLayout {
                        ForEach(1...7, id: \.self) { wd in
                            Chip(title: Fmt.weekdayShort(wd), selected: days.contains(wd)) { days.toggle(wd) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Time") {
                    DatePicker("From", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("To", selection: $end, displayedComponents: .hourAndMinute)
                    if end.minutesOfDay <= start.minutesOfDay {
                        Label("End must be after start", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Clinic time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let s = start.minutesOfDay
                        let e = end.minutesOfDay
                        onAdd(days.sorted().map { AvailabilityWindow(weekday: $0, startMinutes: s, endMinutes: e) })
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(days.isEmpty || end.minutesOfDay <= start.minutesOfDay)
                }
            }
        }
    }
}
