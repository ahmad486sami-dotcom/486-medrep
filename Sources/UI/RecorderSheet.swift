import SwiftUI
import SwiftData

// MARK: - Shared visit form

enum FollowUpChoice: String, CaseIterable, Identifiable {
    case none, tomorrow, threeDays, week, twoWeeks, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "No reminder"
        case .tomorrow: return "Tomorrow"
        case .threeDays: return "In 3 days"
        case .week: return "In 1 week"
        case .twoWeeks: return "In 2 weeks"
        case .custom: return "Custom date"
        }
    }

    func date(custom: Date) -> Date? {
        let nine = 9 * 60
        switch self {
        case .none: return nil
        case .tomorrow: return Date().startOfDay.adding(days: 1).at(minutes: nine)
        case .threeDays: return Date().startOfDay.adding(days: 3).at(minutes: nine)
        case .week: return Date().startOfDay.adding(days: 7).at(minutes: nine)
        case .twoWeeks: return Date().startOfDay.adding(days: 14).at(minutes: nine)
        case .custom: return custom
        }
    }
}

struct VisitForm {
    var date = Date()
    var summary = ""
    var transcript = ""
    var note = ""
    var tags: Set<String> = []
    var products: Set<String> = []
    var followUp: FollowUpChoice = .none
    var followUpDate = Date().startOfDay.adding(days: 7).at(minutes: 9 * 60)
    var followUpText = ""

    init() {}

    init(from visit: Visit) {
        date = visit.date
        summary = visit.summary
        transcript = visit.transcript
        note = visit.note
        tags = Set(visit.tags)
        products = Set(visit.products)
    }

    func apply(to visit: Visit) {
        visit.date = date
        visit.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        visit.transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        visit.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        visit.tags = tags.sorted()
        visit.products = products.sorted()
        visit.isQuick = false
    }
}

struct VisitFormView: View {
    @Binding var form: VisitForm
    var doctor: Doctor?
    var hasAudio: Bool
    var onChooseDoctor: (() -> Void)?
    @AppStorage(Keys.products) private var productsRaw = Defaults.productsDefault

    private var productOptions: [String] {
        var list = Defaults.parseList(productsRaw)
        for p in (doctor?.products ?? []) + Array(form.products) where !list.contains(p) { list.append(p) }
        return list
    }

    var body: some View {
        Form {
            Section("Doctor") {
                Button {
                    onChooseDoctor?()
                } label: {
                    HStack {
                        if let doctor {
                            DoctorRowLabel(doctor: doctor)
                        } else {
                            Label("Choose doctor", systemImage: "person.crop.circle.badge.plus")
                                .foregroundStyle(Theme.accent)
                        }
                        Spacer()
                        if onChooseDoctor != nil {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
                DatePicker("Date & time", selection: $form.date)
            }

            Section {
                TextField("2–4 lines: what was discussed, what was asked, next step", text: $form.summary, axis: .vertical)
                    .lineLimit(2...8)
            } header: {
                Label("Summary", systemImage: "sparkles")
            }

            if hasAudio || !form.transcript.isEmpty {
                Section("Transcript") {
                    TextField("Transcript", text: $form.transcript, axis: .vertical)
                        .lineLimit(3...14)
                        .font(.callout)
                }
            }

            Section("Visit note") {
                TextField("Anything else about this visit…", text: $form.note, axis: .vertical)
                    .lineLimit(3...10)
            }

            Section("Tags") {
                FlowLayout {
                    ForEach(VisitTags.all, id: \.self) { tag in
                        Chip(title: tag, selected: form.tags.contains(tag)) { form.tags.toggle(tag) }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Products discussed") {
                FlowLayout {
                    ForEach(productOptions, id: \.self) { p in
                        Chip(title: p, selected: form.products.contains(p)) { form.products.toggle(p) }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker("Remind me", selection: $form.followUp) {
                    ForEach(FollowUpChoice.allCases) { Text($0.title).tag($0) }
                }
                if form.followUp == .custom {
                    DatePicker("When", selection: $form.followUpDate, in: Date()...)
                }
                if form.followUp != .none {
                    TextField("What to do (e.g. bring the study)", text: $form.followUpText)
                }
            } header: {
                Label("Follow-up reminder", systemImage: "bell.fill")
            }
        }
    }
}

// MARK: - Recorder

struct RecorderSheet: View {
    var preselected: Doctor?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Hospital.name) private var hospitals: [Hospital]
    @Query(sort: \PlanItem.startTime) private var plans: [PlanItem]
    @StateObject private var recorder = AudioRecorder()
    @ObservedObject private var location = LocationManager.shared
    @AppStorage(Keys.speechLocale) private var speechLocale = Defaults.speechLocaleDefault

    @State private var doctor: Doctor?
    @State private var phase: Phase = .ready
    @State private var showPicker = false
    @State private var form = VisitForm()
    @State private var recordedFile: String?
    @State private var recordedDuration: Double = 0
    @State private var micDenied = false
    @State private var confirmDiscard = false
    @State private var saved = false
    @State private var didSetup = false

    enum Phase { case ready, recording, processing, review }

    private var nearby: Hospital? { location.nearestHospital(hospitals) }

    var body: some View {
        NavigationStack {
            ZStack {
                switch phase {
                case .ready, .recording:
                    recordView.transition(.opacity)
                case .processing:
                    processingView.transition(.opacity)
                case .review:
                    VisitFormView(form: $form, doctor: doctor, hasAudio: recordedFile != nil, onChooseDoctor: { showPicker = true })
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                if saved {
                    SavedOverlay().transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: phase)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if phase == .ready { close() } else { confirmDiscard = true }
                    }
                }
                if phase == .review {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .fontWeight(.semibold)
                            .disabled(doctor == nil)
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                DoctorPickerView(selection: $doctor)
            }
            .confirmationDialog("Discard this debrief?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { close() }
                Button("Keep editing", role: .cancel) {}
            }
            .alert("Microphone access needed", isPresented: $micDenied) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Allow microphone access for 486 in Settings to record debriefs. You can still log the visit without audio.")
            }
        }
        .interactiveDismissDisabled(phase != .ready)
        .onAppear(perform: setup)
    }

    private var title: String {
        switch phase {
        case .ready: return "New debrief"
        case .recording: return "Recording…"
        case .processing: return "Processing"
        case .review: return "Review visit"
        }
    }

    // MARK: Views

    private var recordView: some View {
        VStack(spacing: 22) {
            Button { showPicker = true } label: {
                HStack(spacing: 12) {
                    if let doctor {
                        Avatar(doctor: doctor, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(doctor.displayName).font(.headline).foregroundStyle(.primary)
                            Text([doctor.specialty, doctor.hospital?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 34))
                            .foregroundStyle(Theme.accent)
                        Text("Choose doctor").font(.headline).foregroundStyle(.primary)
                    }
                    Spacer()
                    Text("Change").font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                }
                .card()
            }
            .buttonStyle(PressableButtonStyle())

            if let nearby {
                Label("You're at \(nearby.name)", systemImage: "location.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }

            Spacer()

            Text(Fmt.duration(recorder.elapsed))
                .font(.system(size: 58, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            WaveformView(levels: recorder.levels, active: recorder.isRecording)
                .frame(height: 90)

            Spacer()

            RecordButton(isRecording: recorder.isRecording) { toggleRecording() }

            Text(recorder.isRecording ? "Tap to stop" : "Walk out, tap, and talk for 30–60 seconds")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if phase == .ready {
                Button("Log visit without recording") {
                    phase = .review
                }
                .font(.footnote.weight(.semibold))
                .tint(Theme.accent)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }

    private var processingView: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large).tint(Theme.accent)
            Text("Turning your voice into notes…")
                .font(.headline)
            Text("Transcribing on your iPhone and picking out products, tags and a short summary.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: Logic

    private func setup() {
        guard !didSetup else { return }
        didSetup = true
        location.request()
        doctor = preselected ?? suggestedDoctor()
    }

    private func suggestedDoctor() -> Doctor? {
        let todayPending = plans.filter { Calendar.current.isDateInToday($0.day) && !$0.isDone }
        if let h = nearby {
            if let item = todayPending.first(where: { $0.doctor?.hospital?.id == h.id }) { return item.doctor }
            return h.activeDoctors.first
        }
        let now = Date()
        return todayPending.min(by: { abs($0.startTime.timeIntervalSince(now)) < abs($1.startTime.timeIntervalSince(now)) })?.doctor
    }

    private func toggleRecording() {
        if recorder.isRecording {
            guard let result = recorder.stop() else { return }
            let file = result.0
            let duration = result.1
            recordedFile = file
            recordedDuration = duration
            phase = .processing
            Task { @MainActor in
                let url = AudioStore.directory.appendingPathComponent(file)
                let text = await Transcriber.transcribe(url: url, localeID: speechLocale)
                form.transcript = text
                let products = Defaults.products + (doctor?.products ?? [])
                form.products = VisitInsights.detectProducts(in: text, products: products)
                form.tags = VisitInsights.detectTags(in: text)
                if let ai = await Summarizer.summarize(text) {
                    form.summary = ai
                } else {
                    form.summary = VisitInsights.quickSummary(text)
                }
                if form.tags.contains("Follow-up needed") {
                    form.followUp = .week
                }
                phase = .review
            }
        } else {
            recorder.requestPermission { granted in
                if granted {
                    if recorder.start() { phase = .recording }
                } else {
                    micDenied = true
                }
            }
        }
    }

    private func save() {
        guard let doctor else { return }
        let visit = Visit(date: form.date)
        form.apply(to: visit)
        visit.audioFileName = recordedFile
        visit.duration = recordedDuration
        context.insert(visit)
        visit.doctor = doctor
        VisitActions.markPlanDone(for: doctor, on: form.date)
        for p in form.products where !doctor.products.contains(p) {
            doctor.products.append(p)
        }
        if let due = form.followUp.date(custom: form.followUpDate) {
            let text = form.followUpText.trimmingCharacters(in: .whitespaces)
            let reminder = Reminder(title: text.isEmpty ? "Follow up with \(doctor.displayName)" : text, dueDate: due)
            reminder.visitID = visit.id
            context.insert(reminder)
            reminder.doctor = doctor
        }
        try? context.save()
        Notifier.reschedule(context: context)
        recordedFile = nil
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { dismiss() }
    }

    private func close() {
        if recorder.isRecording { recorder.cancel() }
        if let recordedFile { AudioStore.delete(recordedFile) }
        dismiss()
    }
}

// MARK: - Recorder pieces

struct WaveformView: View {
    var levels: [CGFloat]
    var active: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Theme.gradient)
                    .frame(width: 4, height: max(5, level * 90))
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(active ? 1 : 0.3)
        .animation(.linear(duration: 0.08), value: levels)
        .animation(.easeInOut, value: active)
    }
}

struct RecordButton: View {
    var isRecording: Bool
    var action: () -> Void
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.18))
                    .frame(width: 128, height: 128)
                    .scaleEffect(pulse ? 1.18 : 0.92)
                    .opacity(isRecording ? 1 : 0)
                Circle()
                    .fill(isRecording ? AnyShapeStyle(Color.red) : AnyShapeStyle(Theme.gradient))
                    .frame(width: 92, height: 92)
                    .shadow(color: (isRecording ? Color.red : Theme.accent).opacity(0.4), radius: 14, y: 6)
                if isRecording {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white)
                        .frame(width: 30, height: 30)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isRecording)
        .sensoryFeedback(.impact(weight: .heavy), trigger: isRecording)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

struct SavedOverlay: View {
    @State private var draw = false
    var body: some View {
        ZStack {
            Color.black.opacity(0.15).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.white, Color.green)
                    .symbolEffect(.bounce, value: draw)
                Text("Saved").font(.headline)
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .sensoryFeedback(.success, trigger: draw)
        .onAppear { draw = true }
    }
}

// MARK: - Doctor picker

struct DoctorPickerView: View {
    @Binding var selection: Doctor?
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Doctor.name) private var doctors: [Doctor]
    @Query(sort: \Hospital.name) private var hospitals: [Hospital]
    @ObservedObject private var location = LocationManager.shared
    @State private var search = ""

    private struct DoctorGroup: Identifiable {
        let id: String
        let title: String
        let doctors: [Doctor]
    }

    private var groups: [DoctorGroup] {
        let filtered = doctors.filter { d in
            d.status != .left && (search.isEmpty
                || d.name.localizedCaseInsensitiveContains(search)
                || d.specialty.localizedCaseInsensitiveContains(search)
                || (d.hospital?.name.localizedCaseInsensitiveContains(search) ?? false))
        }
        let nearby = location.nearestHospital(hospitals)
        var result: [DoctorGroup] = []
        if let nearby {
            let here = filtered.filter { $0.hospital?.id == nearby.id }
            if !here.isEmpty { result.append(DoctorGroup(id: "near", title: "Nearby · \(nearby.name)", doctors: here)) }
        }
        let byHospital = Dictionary(grouping: filtered.filter { $0.hospital?.id != nearby?.id || nearby == nil }) { $0.hospital?.name ?? "No hospital" }
        for key in byHospital.keys.sorted() {
            result.append(DoctorGroup(id: key, title: key, doctors: byHospital[key] ?? []))
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                if doctors.isEmpty {
                    EmptyStateView(systemImage: "person.2.slash", title: "No doctors yet", message: "Add doctors in the Directory tab first.")
                }
                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.doctors) { d in
                            Button {
                                selection = d
                                dismiss()
                            } label: {
                                HStack {
                                    DoctorRowLabel(doctor: d, showHospital: false)
                                    if selection?.id == d.id {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Name, specialty or hospital")
            .navigationTitle("Choose doctor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
