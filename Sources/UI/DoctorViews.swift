import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Doctor detail

struct DoctorDetailView: View {
    @Bindable var doctor: Doctor
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Keys.cycle) private var cycleRaw = Cycle.month.rawValue

    @State private var showEdit = false
    @State private var showAway = false
    @State private var showNote = false
    @State private var showRecorder = false
    @State private var showExport = false
    @State private var showReminder = false
    @State private var confirmDelete = false
    @State private var toast: String?
    @State private var appeared = false

    private var cycleStart: Date { (Cycle(rawValue: cycleRaw) ?? .month).start() }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header.staggerIn(0, appeared)
                actionRow.staggerIn(1, appeared)
                briefCard.staggerIn(2, appeared)
                noteCard.staggerIn(3, appeared)
                availabilityCard.staggerIn(4, appeared)
                if !doctor.products.isEmpty { productsCard.staggerIn(5, appeared) }
                infoCard.staggerIn(6, appeared)
                followUpsCard.staggerIn(7, appeared)
                historyCard.staggerIn(8, appeared)
                bottomButtons.staggerIn(9, appeared)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(doctor.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEdit = true } label: { Label("Edit doctor", systemImage: "pencil") }
                    Button { showExport = true } label: { Label("Export PDF", systemImage: "doc.richtext") }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete doctor", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEdit) { DoctorEditor(doctor: doctor) }
        .sheet(isPresented: $showAway) {
            AwaySheet(doctor: doctor)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showNote) { NoteEditorSheet(title: "General note", text: $doctor.generalNote) }
        .sheet(isPresented: $showRecorder) { RecorderSheet(preselected: doctor) }
        .sheet(isPresented: $showExport) { ExportSheet(initialScope: .doctor, initialDoctor: doctor) }
        .sheet(isPresented: $showReminder) { ReminderEditor(doctor: doctor) }
        .confirmationDialog("Delete \(doctor.displayName)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete doctor", role: .destructive) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    VisitActions.deleteDoctor(doctor, context: context)
                }
            }
        } message: {
            Text("Their \(doctor.visits.count) visits, recordings and reminders will be deleted too.")
        }
        .toast($toast)
        .onAppear {
            if !appeared { withAnimation { appeared = true } }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            Avatar(doctor: doctor, size: 84)
                .shadow(color: Theme.accent.opacity(0.25), radius: 10, y: 4)
            Text(doctor.displayName)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text([doctor.specialty, doctor.hospital?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Menu {
                Button { setStatus(.available) } label: { Label("Available", systemImage: DoctorStatus.available.icon) }
                Button { showAway = true } label: { Label("Away…", systemImage: DoctorStatus.away.icon) }
                Button { setStatus(.left) } label: { Label("Left UAE", systemImage: DoctorStatus.left.icon) }
                Divider()
                Button {
                    doctor.statusCheckedAt = Date()
                    try? context.save()
                    toast = "Status confirmed"
                } label: { Label("Mark status checked now", systemImage: "checkmark.seal") }
            } label: {
                HStack(spacing: 4) {
                    StatusPill(status: doctor.status)
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                }
            }
            .animation(.spring, value: doctor.statusRaw)

            Text(statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 20)
    }

    private var statusLine: String {
        var parts: [String] = []
        if doctor.status == .away {
            if !doctor.awayReason.isEmpty { parts.append(doctor.awayReason) }
            if let r = doctor.returnDate { parts.append("back \(r.formatted(date: .abbreviated, time: .omitted))") }
        }
        if let checked = doctor.statusCheckedAt {
            let d = Date.daysBetween(checked, Date())
            parts.append(d == 0 ? "checked today" : "checked \(d)d ago")
        } else {
            parts.append("status not checked yet")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    private var actionRow: some View {
        HStack(spacing: 6) {
            if let url = Links.tel(doctor.phone) {
                ActionTile(title: "Call", systemImage: "phone.fill") { openURL(url) }
            }
            if let url = Links.whatsapp(doctor.phone) {
                ActionTile(title: "WhatsApp", systemImage: "message.fill", tint: .green) { openURL(url) }
            }
            if let h = doctor.hospital, let url = Links.tel(h.mainPhone) {
                ActionTile(title: "Hospital", systemImage: "building.2.fill") { openURL(url) }
            }
            if let h = doctor.hospital, let url = Links.navigate(to: h) {
                ActionTile(title: "Navigate", systemImage: "car.fill") { openURL(url) }
            }
            ActionTile(title: "Record", systemImage: "mic.fill", tint: .red) { showRecorder = true }
        }
        .card(padding: 12)
    }

    // MARK: Cards

    private var briefCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Before you go in", systemImage: "sparkles")
            if let last = doctor.lastVisit {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(doctor.lastVisitText) · \(last.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline.weight(.semibold))
                        Text(last.headline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                }
            } else {
                Label("First visit — no history yet", systemImage: "star.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let next = doctor.openReminders.first {
                Label("Open: \(next.title)", systemImage: "bell.badge.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
            if doctor.isOverdue, let days = doctor.daysSinceLastVisit {
                Label("Due — you aim for every \(doctor.visitEveryDays) days (\(days)d now)", systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .card()
    }

    private var noteCard: some View {
        Button {
            showNote = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "pin.fill").foregroundStyle(.orange)
                    Text("General note").font(.headline).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "square.and.pencil").foregroundStyle(Theme.accent)
                }
                Text(doctor.generalNote.isEmpty ? "Tap to add things to remember about this doctor — preferences, best approach, assistant name…" : doctor.generalNote)
                    .font(.subheadline)
                    .foregroundStyle(doctor.generalNote.isEmpty ? Color.secondary : Color.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .card()
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var availabilityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(title: "Clinic times", systemImage: "clock.fill")
                if doctor.isAvailableNow {
                    Text("Available now")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                }
            }
            let windows = doctor.availability.sorted { ($0.weekday, $0.startMinutes) < ($1.weekday, $1.startMinutes) }
            if windows.isEmpty {
                Button("Add clinic times") { showEdit = true }
                    .font(.subheadline)
                    .tint(Theme.accent)
            } else {
                FlowLayout {
                    ForEach(windows) { w in
                        Text(w.label)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(w.weekday == Date().weekday ? Theme.accent.opacity(0.18) : Color(.tertiarySystemFill), in: Capsule())
                    }
                }
            }
        }
        .card()
    }

    private var productsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Products", systemImage: "pills.fill")
            FlowLayout {
                ForEach(doctor.products, id: \.self) { TagLabel(text: $0) }
            }
        }
        .card()
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Details", systemImage: "person.text.rectangle")
            infoRow("Priority", doctor.priority)
            infoRow("Visit every", doctor.visitEveryDays > 0 ? "\(doctor.visitEveryDays) days" : "No target")
            if !doctor.department.isEmpty || !doctor.room.isEmpty {
                infoRow("Department", [doctor.department, doctor.room.isEmpty ? "" : "Room \(doctor.room)"].filter { !$0.isEmpty }.joined(separator: " · "))
            }
            if !doctor.phone.isEmpty { infoRow("Phone", doctor.phone) }
            if !doctor.phone2.isEmpty { infoRow("Phone 2", doctor.phone2) }
            if !doctor.email.isEmpty { infoRow("Email", doctor.email) }
            if !doctor.assistantName.isEmpty { infoRow("Assistant", doctor.assistantName) }
            infoRow("Language", doctor.language)
            if !doctor.importantDates.isEmpty { infoRow("Dates", doctor.importantDates) }
        }
        .card()
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.subheadline).foregroundStyle(.secondary).frame(width: 96, alignment: .leading)
            Text(value).font(.subheadline)
            Spacer(minLength: 0)
        }
    }

    private var followUpsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(title: "Follow-ups", systemImage: "bell.fill")
                Button { showReminder = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                    .tint(Theme.accent)
            }
            if doctor.openReminders.isEmpty {
                Text("No open follow-ups").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(doctor.openReminders) { r in
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.spring) { r.isDone = true }
                        try? context.save()
                        Notifier.reschedule(context: context)
                    } label: {
                        Image(systemName: "circle").font(.title3).foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.title).font(.subheadline.weight(.semibold))
                        Text(r.dueDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(r.dueDate < Date() ? Color.red : Color.secondary)
                    }
                    Spacer()
                }
            }
        }
        .card()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(title: "Meetings", systemImage: "clock.arrow.circlepath")
                Text("\(doctor.visits.count) total")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if doctor.visits.isEmpty {
                Text("No meetings yet. Record a debrief after your first visit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(doctor.sortedVisits) { v in
                NavigationLink {
                    VisitDetailView(visit: v)
                } label: {
                    VisitRow(visit: v, showDoctor: false)
                }
                .buttonStyle(.plain)
                if v.id != doctor.sortedVisits.last?.id { Divider() }
            }
        }
        .card()
    }

    private var bottomButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    PlanActions.add([doctor], to: Date(), context: context)
                    toast = "Added to today's plan"
                } label: {
                    Label("Plan today", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(PlanActions.isPlanned(doctor, on: Date()))

                Button {
                    if doctor.visited(since: Date().startOfDay) {
                        toast = "Already visited today"
                    } else {
                        VisitActions.markVisited(doctor, context: context)
                        Notifier.reschedule(context: context)
                        toast = "Marked visited"
                    }
                } label: {
                    Label("Mark visited", systemImage: "checkmark.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            }
            .controlSize(.large)
        }
    }

    private func setStatus(_ s: DoctorStatus) {
        withAnimation(.spring) {
            doctor.status = s
            if s != .away {
                doctor.returnDate = nil
                doctor.awayReason = ""
            }
            doctor.statusCheckedAt = Date()
        }
        try? context.save()
        Notifier.reschedule(context: context)
        toast = "Status: \(s.title)"
    }
}

// MARK: - Visit row & detail

struct VisitRow: View {
    let visit: Visit
    var showDoctor = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text(visit.date.formatted(.dateTime.day()))
                    .font(.headline)
                Text(visit.date.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44)
            .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                if showDoctor {
                    Text(visit.doctor?.displayName ?? "Unknown doctor")
                        .font(.subheadline.weight(.semibold))
                }
                Text(visit.headline)
                    .font(.subheadline)
                    .foregroundStyle(showDoctor ? Color.secondary : Color.primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(visit.date.shortTime)
                    if visit.audioFileName != nil { Image(systemName: "waveform") }
                    if !visit.note.isEmpty { Image(systemName: "note.text") }
                    ForEach(visit.tags.prefix(2), id: \.self) { t in
                        Text(t).lineLimit(1)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct VisitDetailView: View {
    @Bindable var visit: Visit
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = AudioPlayer()
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var showExport = false

    private var linkedReminders: [Reminder] {
        (visit.doctor?.reminders ?? []).filter { $0.visitID == visit.id }
    }

    var body: some View {
        List {
            Section {
                if let d = visit.doctor {
                    NavigationLink { DoctorDetailView(doctor: d) } label: { DoctorRowLabel(doctor: d) }
                }
                Label(visit.date.formatted(date: .complete, time: .shortened), systemImage: "calendar")
            }

            if let url = visit.audioURL {
                Section("Voice debrief") {
                    HStack(spacing: 14) {
                        Button {
                            player.toggle(url: url)
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(Theme.accent)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: player.progress).tint(Theme.accent)
                            Text(Fmt.duration(visit.duration)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if !visit.summary.isEmpty {
                Section { Text(visit.summary) } header: { Label("Summary", systemImage: "sparkles") }
            }
            if !visit.note.isEmpty {
                Section("Visit note") { Text(visit.note) }
            }
            if !visit.transcript.isEmpty {
                Section("Transcript") {
                    Text(visit.transcript).font(.callout).textSelection(.enabled)
                }
            }
            if !visit.tags.isEmpty || !visit.products.isEmpty {
                Section("Tags & products") {
                    FlowLayout {
                        ForEach(visit.tags, id: \.self) { TagLabel(text: $0) }
                        ForEach(visit.products, id: \.self) { p in
                            Text(p)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.12), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            if !linkedReminders.isEmpty {
                Section("Follow-up") {
                    ForEach(linkedReminders) { r in
                        Label("\(r.title) · \(r.dueDate.formatted(date: .abbreviated, time: .shortened))", systemImage: r.isDone ? "checkmark.circle.fill" : "bell")
                    }
                }
            }
            if visit.isQuick && !visit.hasContent {
                Section {
                    Text("Marked as visited without notes. Tap Edit to add a summary.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Visit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEdit = true } label: { Label("Edit", systemImage: "pencil") }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete visit", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEdit) { VisitEditSheet(visit: visit) }
        .confirmationDialog("Delete this visit?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                player.stop()
                let v = visit
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    VisitActions.delete(v, context: context)
                }
            }
        }
        .onDisappear { player.stop() }
    }
}

struct VisitEditSheet: View {
    let visit: Visit
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var form: VisitForm
    @State private var doctor: Doctor?
    @State private var showPicker = false

    init(visit: Visit) {
        self.visit = visit
        _form = State(initialValue: VisitForm(from: visit))
        _doctor = State(initialValue: visit.doctor)
    }

    var body: some View {
        NavigationStack {
            VisitFormView(form: $form, doctor: doctor, hasAudio: visit.audioFileName != nil, onChooseDoctor: { showPicker = true })
                .navigationTitle("Edit visit")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }.fontWeight(.semibold)
                    }
                }
                .sheet(isPresented: $showPicker) { DoctorPickerView(selection: $doctor) }
        }
    }

    private func save() {
        form.apply(to: visit)
        if let doctor, visit.doctor?.id != doctor.id { visit.doctor = doctor }
        if let due = form.followUp.date(custom: form.followUpDate), let d = doctor ?? visit.doctor {
            let text = form.followUpText.trimmingCharacters(in: .whitespaces)
            let r = Reminder(title: text.isEmpty ? "Follow up with \(d.displayName)" : text, dueDate: due)
            r.visitID = visit.id
            context.insert(r)
            r.doctor = d
        }
        try? context.save()
        Notifier.reschedule(context: context)
        dismiss()
    }
}

// MARK: - Small sheets

struct NoteEditorSheet: View {
    let title: String
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $draft)
                .focused($focused)
                .padding(.horizontal)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                            try? context.save()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
                .onAppear {
                    draft = text
                    focused = true
                }
        }
    }
}

struct AwaySheet: View {
    let doctor: Doctor
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var reason = "Leave"
    @State private var detail = ""
    @State private var knowsReturn = true
    @State private var returnDate = Date().adding(days: 7)

    var body: some View {
        NavigationStack {
            Form {
                Section("Reason") {
                    FlowLayout {
                        ForEach(AwayReasons.all, id: \.self) { r in
                            Chip(title: r, selected: reason == r) { reason = r }
                        }
                    }
                    .padding(.vertical, 4)
                    TextField("Details (optional)", text: $detail)
                }
                Section {
                    Toggle("I know the return date", isOn: $knowsReturn.animation())
                    if knowsReturn {
                        DatePicker("Back on", selection: $returnDate, in: Date()..., displayedComponents: .date)
                    }
                } footer: {
                    Text("486 skips this doctor when planning and reminds you the morning they're back.")
                }
            }
            .navigationTitle("Mark away")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        doctor.status = .away
                        let d = detail.trimmingCharacters(in: .whitespaces)
                        doctor.awayReason = d.isEmpty ? reason : "\(reason): \(d)"
                        doctor.returnDate = knowsReturn ? returnDate.startOfDay : nil
                        doctor.statusCheckedAt = Date()
                        try? context.save()
                        Notifier.reschedule(context: context)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let r = doctor.returnDate, r > Date() { returnDate = r }
            }
        }
    }
}

struct ReminderEditor: View {
    var doctor: Doctor?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var title = ""
    @State private var due = Date().startOfDay.adding(days: 1).at(minutes: 9 * 60)
    @State private var chosen: Doctor?
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What to remember", text: $title, axis: .vertical)
                    DatePicker("When", selection: $due, in: Date()...)
                }
                Section("Doctor (optional)") {
                    Button {
                        showPicker = true
                    } label: {
                        if let d = chosen ?? doctor {
                            DoctorRowLabel(doctor: d)
                        } else {
                            Label("Choose doctor", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                    .buttonStyle(.plain)
                }
                Section {
                    HStack {
                        quick("Tomorrow", 1)
                        quick("3 days", 3)
                        quick("1 week", 7)
                        quick("2 weeks", 14)
                    }
                }
            }
            .navigationTitle("New reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showPicker) { DoctorPickerView(selection: $chosen) }
        }
    }

    private func quick(_ label: String, _ days: Int) -> some View {
        Button(label) {
            withAnimation { due = Date().startOfDay.adding(days: days).at(minutes: 9 * 60) }
        }
        .buttonStyle(.bordered)
        .font(.caption.weight(.semibold))
        .tint(Theme.accent)
        .frame(maxWidth: .infinity)
    }

    private func save() {
        let r = Reminder(title: title.trimmingCharacters(in: .whitespaces), dueDate: due)
        context.insert(r)
        r.doctor = chosen ?? doctor
        try? context.save()
        Notifier.reschedule(context: context)
        dismiss()
    }
}
