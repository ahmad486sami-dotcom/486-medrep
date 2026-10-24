import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(sort: \PlanItem.startTime) private var allPlans: [PlanItem]
    @Query(sort: \Visit.date, order: .reverse) private var allVisits: [Visit]
    @Query(sort: \Reminder.dueDate) private var reminders: [Reminder]
    @Query private var targets: [DayTarget]
    @Query private var hospitals: [Hospital]
    @Query private var mileage: [MileageEntry]
    @ObservedObject private var router = AppRouter.shared

    @State private var showRecorder = false
    @State private var recorderDoctor: Doctor?
    @State private var showSettings = false
    @State private var showTarget = false
    @State private var showExport = false
    @State private var appeared = false
    @State private var displayedDone = 0
    @State private var toast: String?

    private var today: Date { Date().startOfDay }

    private var todayItems: [PlanItem] {
        allPlans.filter { Calendar.current.isDate($0.day, inSameDayAs: today) }
    }

    private var stops: [Stop] { Planner.stops(for: todayItems) }

    private var visitedTodayIDs: Set<UUID> {
        Set(allVisits.filter { Calendar.current.isDateInToday($0.date) }.compactMap { $0.doctor?.id })
    }

    private var doneCount: Int { visitedTodayIDs.count }
    private var target: Int { Targets.target(for: today, overrides: targets) }

    private var dueReminders: [Reminder] {
        reminders.filter { !$0.isDone && $0.dueDate < today.adding(days: 1) }
    }

    private var todayKm: Double? {
        mileage.first(where: { Calendar.current.isDateInToday($0.day) })?.km
    }

    private func isDone(_ item: PlanItem) -> Bool {
        if item.isDone { return true }
        if let id = item.doctor?.id { return visitedTodayIDs.contains(id) }
        return false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard.staggerIn(0, appeared)

                    if hospitals.isEmpty {
                        welcomeCard.staggerIn(1, appeared)
                    } else if todayItems.isEmpty {
                        emptyPlanCard.staggerIn(1, appeared)
                    } else {
                        routeCard.staggerIn(1, appeared)
                    }

                    ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                        StopCard(
                            stop: stop,
                            isDone: isDone,
                            onToggle: toggle,
                            onRecord: { doctor in
                                recorderDoctor = doctor
                                showRecorder = true
                            }
                        )
                        .staggerIn(index + 2, appeared)
                    }

                    if !dueReminders.isEmpty {
                        remindersCard.staggerIn(stops.count + 2, appeared)
                    }

                    if !todayItems.isEmpty || todayKm != nil {
                        mileageCard.staggerIn(stops.count + 3, appeared)
                    }

                    Color.clear.frame(height: 90)
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showExport = true } label: { Image(systemName: "doc.richtext") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                }
            }
            .overlay(alignment: .bottom) { recordButton }
            .sheet(isPresented: $showRecorder) {
                RecorderSheet(preselected: recorderDoctor)
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showTarget) {
                TargetEditorSheet(day: today)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showExport) { ExportSheet(initialScope: .plan) }
            .toast($toast)
            .onAppear {
                if !appeared {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                        appeared = true
                        withAnimation(.spring(response: 0.8)) { displayedDone = doneCount }
                    }
                } else {
                    displayedDone = doneCount
                }
            }
            .onChange(of: doneCount) { _, value in
                withAnimation(.spring(response: 0.6)) { displayedDone = value }
            }
        }
    }

    // MARK: Header

    private var headerCard: some View {
        HStack(spacing: 18) {
            ZStack {
                ProgressRing(progress: target > 0 ? Double(displayedDone) / Double(target) : (displayedDone > 0 ? 1 : 0))
                VStack(spacing: 0) {
                    Text("\(displayedDone)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(value: Double(displayedDone)))
                    Text(target > 0 ? "of \(target)" : "visits")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 98, height: 98)

            VStack(alignment: .leading, spacing: 6) {
                Text(Date().dayTitle)
                    .font(.headline)
                Text(summaryLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showTarget = true
                } label: {
                    Label(target > 0 ? "Target \(target)" : "No target", systemImage: "target")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private var summaryLine: String {
        let planned = todayItems.count
        if planned == 0 { return doneCount == 0 ? "Nothing planned yet." : "\(doneCount) visited today." }
        let left = todayItems.filter { !isDone($0) }.count
        if left == 0 { return "All \(planned) planned visits done. Great job!" }
        return "\(left) of \(planned) planned visits left · \(stops.count) location\(stops.count == 1 ? "" : "s")"
    }

    // MARK: Cards

    private var routeCard: some View {
        let remainingStops = stops.filter { stop in stop.items.contains { !isDone($0) } }
        let hospitalsLeft = remainingStops.compactMap { $0.hospital }
        return Button {
            if let url = Planner.googleMapsURL(for: hospitalsLeft) {
                openURL(url)
            } else {
                toast = "Add map locations to your hospitals first"
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(remainingStops.isEmpty ? "Route complete" : "Open route in Google Maps")
                        .font(.headline)
                    Text("\(remainingStops.count) stop\(remainingStops.count == 1 ? "" : "s") left · same-place doctors grouped")
                        .font(.caption)
                        .opacity(0.85)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(remainingStops.isEmpty)
    }

    private var welcomeCard: some View {
        EmptyStateView(
            systemImage: "hand.wave.fill",
            title: "Welcome to 486",
            message: "Start by adding your hospitals and doctors in the Directory, or load sample data to look around.",
            buttonTitle: "Open Directory",
            action: { router.tab = .directory },
            secondaryTitle: "Load sample data",
            secondaryAction: {
                SampleData.load(into: context)
                Notifier.reschedule(context: context)
                toast = "Sample data loaded"
            }
        )
        .card()
    }

    private var emptyPlanCard: some View {
        EmptyStateView(
            systemImage: "calendar.badge.plus",
            title: "No visits planned today",
            message: "Pick the doctors you want to see. 486 will order them by clinic time and location.",
            buttonTitle: "Plan today",
            action: { router.tab = .planner }
        )
        .card()
    }

    private var remindersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Reminders due", systemImage: "bell.badge.fill")
            ForEach(dueReminders) { r in
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.spring) { r.isDone = true }
                        try? context.save()
                        Notifier.reschedule(context: context)
                    } label: {
                        Image(systemName: "circle")
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.title).font(.subheadline.weight(.semibold))
                        Text([r.doctor?.displayName, Fmt.relativeDays(r.dueDate)].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(r.dueDate < today ? Color.red : Color.secondary)
                    }
                    Spacer()
                }
            }
        }
        .card()
    }

    private var mileageCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "car.fill")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Mileage today").font(.subheadline.weight(.semibold))
                Text(todayKm.map { Fmt.km($0) } ?? "Not calculated yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Calculate") { calculateMileage() }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
        }
        .card()
    }

    private var recordButton: some View {
        Button {
            recorderDoctor = nil
            showRecorder = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18, weight: .bold))
                Text("Record debrief")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(Theme.gradient, in: Capsule())
            .shadow(color: Theme.accent.opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.bottom, 10)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.6)
        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.3), value: appeared)
    }

    // MARK: Actions

    private func toggle(_ item: PlanItem) {
        guard let doctor = item.doctor else { return }
        if isDone(item) {
            let todays = doctor.visits.filter { Calendar.current.isDateInToday($0.date) }
            if todays.contains(where: { $0.hasContent }) {
                toast = "This visit has a debrief — open the doctor to edit it"
                return
            }
            for v in todays { context.delete(v) }
            item.isDone = false
        } else {
            VisitActions.markVisited(doctor, context: context)
            item.isDone = true
        }
        try? context.save()
        Notifier.reschedule(context: context)
    }

    private func calculateMileage() {
        let coords = Mileage.coordinates(for: today, visits: allVisits, plans: allPlans)
        guard coords.count > 1 else {
            toast = "Need at least 2 locations with map pins"
            return
        }
        Task { @MainActor in
            let km = await Mileage.estimateKm(coords)
            if let entry = mileage.first(where: { Calendar.current.isDateInToday($0.day) }) {
                entry.km = km
            } else {
                context.insert(MileageEntry(day: today, km: km))
            }
            try? context.save()
            toast = "Today: \(Fmt.km(km))"
        }
    }
}

// MARK: - Stop card

struct StopCard: View {
    let stop: Stop
    let isDone: (PlanItem) -> Bool
    var onToggle: (PlanItem) -> Void
    var onRecord: (Doctor) -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(stop.startTime.shortTime) – \(stop.endTime.shortTime)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accent)
                    Text(stop.title)
                        .font(.headline)
                    if let h = stop.hospital, !h.area.isEmpty {
                        Text(h.area).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let phone = stop.hospital?.mainPhone, !phone.isEmpty, let url = Links.tel(phone) {
                    CircleIconButton(systemImage: "phone.fill") { openURL(url) }
                }
                if let h = stop.hospital, h.hasLocation, let url = Links.navigate(to: h) {
                    CircleIconButton(systemImage: "car.fill") { openURL(url) }
                }
            }

            ForEach(stop.items) { item in
                if let doctor = item.doctor {
                    PlanDoctorRow(item: item, doctor: doctor, done: isDone(item),
                                  onToggle: { onToggle(item) },
                                  onRecord: { onRecord(doctor) })
                    if item.id != stop.items.last?.id { Divider().padding(.leading, 44) }
                }
            }
        }
        .card()
    }
}

struct PlanDoctorRow: View {
    let item: PlanItem
    let doctor: Doctor
    let done: Bool
    var onToggle: () -> Void
    var onRecord: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26))
                    .foregroundStyle(done ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: done)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: done)

            NavigationLink {
                DoctorDetailView(doctor: doctor)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(doctor.displayName)
                            .font(.subheadline.weight(.semibold))
                            .strikethrough(done, color: .secondary)
                            .foregroundStyle(.primary)
                        if doctor.status != .available {
                            StatusPill(status: doctor.status, compact: true)
                        }
                    }
                    Text("\(item.startTime.shortTime) · \(doctor.specialty.isEmpty ? "Doctor" : doctor.specialty)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onRecord) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(PressableButtonStyle())
        }
        .opacity(done ? 0.65 : 1)
        .animation(.spring(response: 0.35), value: done)
    }
}

// MARK: - Target editor

struct TargetEditorSheet: View {
    let day: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var targets: [DayTarget]
    @State private var value = 0
    @State private var useDefault = true
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Use \(Fmt.weekdayName(day.weekday)) default (\(Targets.weekdayDefault(for: day)))", isOn: $useDefault)
                    if !useDefault {
                        Stepper(value: $value, in: 0...40) {
                            HStack {
                                Text("Target")
                                Spacer()
                                Text(value == 0 ? "No target" : "\(value) visits")
                                    .foregroundStyle(.secondary)
                                    .contentTransition(.numericText(value: Double(value)))
                                    .animation(.spring, value: value)
                            }
                        }
                    }
                } footer: {
                    Text("Your number, your call. 0 means no target — 486 just counts your visits. Weekday defaults are in Settings.")
                }
            }
            .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let o = targets.first(where: { Calendar.current.isDate($0.day, inSameDayAs: day) }) {
                    useDefault = false
                    value = o.target
                } else {
                    value = Targets.weekdayDefault(for: day)
                }
            }
        }
    }

    private func save() {
        for o in targets where Calendar.current.isDate(o.day, inSameDayAs: day) {
            context.delete(o)
        }
        if !useDefault {
            context.insert(DayTarget(day: day, target: value))
        }
        try? context.save()
        dismiss()
    }
}
