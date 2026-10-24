import SwiftUI
import SwiftData
import Charts

struct RecordsView: View {
    @State private var section = 0
    @State private var showExport = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $section.animation(.spring(response: 0.35))) {
                    Text("Visits").tag(0)
                    Text("Reminders").tag(1)
                    Text("Stats").tag(2)
                    Text("Mileage").tag(3)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                Group {
                    switch section {
                    case 0: VisitsLog()
                    case 1: RemindersList()
                    case 2: StatsView()
                    default: MileageView()
                    }
                }
                .transition(.opacity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Records")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showExport = true } label: {
                        Label("Export PDF", systemImage: "doc.richtext")
                    }
                }
            }
            .sheet(isPresented: $showExport) {
                ExportSheet(initialScope: section == 3 ? .mileage : .visits)
            }
        }
    }
}

// MARK: - Visit log

struct VisitsLog: View {
    @Query(sort: \Visit.date, order: .reverse) private var visits: [Visit]
    @State private var search = ""

    private var filtered: [Visit] {
        guard !search.isEmpty else { return visits }
        return visits.filter { v in
            let fields = [
                v.doctor?.name ?? "", v.doctor?.specialty ?? "", v.doctor?.hospital?.name ?? "",
                v.summary, v.note, v.transcript,
                v.tags.joined(separator: " "), v.products.joined(separator: " ")
            ]
            return fields.contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    private var days: [Date] {
        Array(Set(filtered.map { $0.date.startOfDay })).sorted(by: >)
    }

    var body: some View {
        List {
            if visits.isEmpty {
                EmptyStateView(systemImage: "waveform", title: "No visits yet", message: "Your debriefs and visits will appear here, newest first.")
            }
            ForEach(days, id: \.self) { day in
                let dayVisits = filtered.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
                Section {
                    ForEach(dayVisits) { v in
                        NavigationLink {
                            VisitDetailView(visit: v)
                        } label: {
                            VisitRow(visit: v)
                        }
                    }
                } header: {
                    HStack {
                        Text(day.formatted(.dateTime.weekday(.wide).day().month()))
                        Spacer()
                        Text("\(Set(dayVisits.compactMap { $0.doctor?.id }).count) doctors")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search, prompt: "Doctor, product, tag, words…")
    }
}

// MARK: - Reminders

struct RemindersList: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Reminder.dueDate) private var reminders: [Reminder]
    @State private var showNew = false
    @State private var showDone = false

    private var open: [Reminder] { reminders.filter { !$0.isDone } }
    private var done: [Reminder] { reminders.filter { $0.isDone }.sorted { $0.dueDate > $1.dueDate } }

    var body: some View {
        List {
            Section {
                Button { showNew = true } label: {
                    Label("New reminder", systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                }
                .tint(Theme.accent)
            }
            Section("Open (\(open.count))") {
                if open.isEmpty {
                    Text("All caught up").foregroundStyle(.secondary)
                }
                ForEach(open) { r in row(r) }
            }
            if !done.isEmpty {
                Section {
                    DisclosureGroup("Done (\(done.count))", isExpanded: $showDone) {
                        ForEach(done.prefix(50)) { r in row(r) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.spring(response: 0.4), value: reminders.map { $0.isDone })
        .sheet(isPresented: $showNew) { ReminderEditor() }
    }

    private func row(_ r: Reminder) -> some View {
        HStack(spacing: 12) {
            Button {
                r.isDone.toggle()
                try? context.save()
                Notifier.reschedule(context: context)
            } label: {
                Image(systemName: r.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(r.isDone ? Color.green : Theme.accent)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(r.isDone)
                Text([r.doctor?.displayName, r.dueDate.formatted(date: .abbreviated, time: .shortened)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(!r.isDone && r.dueDate < Date() ? Color.red : Color.secondary)
            }
            Spacer()
            if let d = r.doctor {
                NavigationLink {
                    DoctorDetailView(doctor: d)
                } label: { EmptyView() }
                .frame(width: 20)
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                context.delete(r)
                try? context.save()
                Notifier.reschedule(context: context)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Stats

struct SpecialtyCount: Identifiable {
    let name: String
    let count: Int
    var id: String { name }
}

struct DayCount: Identifiable {
    var id: Date { day }
    let day: Date
    let count: Int
}

struct StatsView: View {
    @Query(sort: \Visit.date, order: .reverse) private var visits: [Visit]
    @Query(sort: \Doctor.name) private var doctors: [Doctor]
    @Query(sort: \Hospital.name) private var hospitals: [Hospital]
    @AppStorage(Keys.cycle) private var cycleRaw = Cycle.month.rawValue

    private var cycle: Cycle { Cycle(rawValue: cycleRaw) ?? .month }

    /// Counts distinct doctors per day, summed over days.
    private func doctorVisits(since start: Date) -> Int {
        var seen = Set<String>()
        for v in visits where v.date >= start {
            guard let id = v.doctor?.id else { continue }
            seen.insert("\(v.date.startOfDay.timeIntervalSince1970)-\(id.uuidString)")
        }
        return seen.count
    }

    private var last14: [DayCount] {
        (0..<14).reversed().map { i in
            let day = Date().startOfDay.adding(days: -i)
            let n = Set(visits.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }.compactMap { $0.doctor?.id }).count
            return DayCount(day: day, count: n)
        }
    }

    private var activeDoctors: [Doctor] { doctors.filter { $0.status != .left } }

    private var coverage: (Int, Int) {
        let start = cycle.start()
        let list = activeDoctors.filter { $0.status == .available || $0.visited(since: start) }
        return (list.filter { $0.visited(since: start) }.count, list.count)
    }

    private var averagePerWorkingDay: Double {
        let start = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        let monthVisits = visits.filter { $0.date >= start }
        let workingDays = Set(monthVisits.map { $0.date.startOfDay }).count
        guard workingDays > 0 else { return 0 }
        return Double(doctorVisits(since: start)) / Double(workingDays)
    }

    private var notVisited30: [Doctor] {
        activeDoctors.filter { d in
            d.status == .available && (d.daysSinceLastVisit ?? 999) >= 30
        }
        .sorted { ($0.daysSinceLastVisit ?? 999) > ($1.daysSinceLastVisit ?? 999) }
    }

    private var bySpecialty: [SpecialtyCount] {
        let start = cycle.start()
        var counts: [String: Int] = [:]
        for v in visits where v.date >= start {
            let key = (v.doctor?.specialty ?? "").isEmpty ? "Other" : (v.doctor?.specialty ?? "Other")
            counts[key, default: 0] += 1
        }
        return counts.map { SpecialtyCount(name: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    statTile("Today", doctorVisits(since: Date().startOfDay))
                    statTile("This week", doctorVisits(since: Cycle.week.start()))
                    statTile("This month", doctorVisits(since: Cycle.month.start()))
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(title: "Visits per day · last 14 days", systemImage: "chart.bar.fill")
                    Chart(last14) { item in
                        BarMark(
                            x: .value("Day", item.day, unit: .day),
                            y: .value("Visits", item.count)
                        )
                        .foregroundStyle(Theme.gradient)
                        .cornerRadius(4)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                            AxisValueLabel(format: .dateTime.day(), centered: true)
                        }
                    }
                    .frame(height: 170)
                    Text(String(format: "Average this month: %.1f doctors per working day", averagePerWorkingDay))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .card()

                let c = coverage
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(title: "Coverage · \(cycle.title.lowercased())", systemImage: "scope")
                    HStack(alignment: .firstTextBaseline) {
                        Text(c.1 > 0 ? "\(Int(Double(c.0) / Double(c.1) * 100))%" : "—")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.gradient)
                        Text("\(c.0) of \(c.1) doctors visited")
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: c.1 > 0 ? Double(c.0) / Double(c.1) : 0).tint(Theme.accent)
                    ForEach(hospitals) { h in
                        let ds = h.doctors.filter { $0.status != .left }
                        if !ds.isEmpty {
                            let seen = ds.filter { $0.visited(since: cycle.start()) }.count
                            HStack {
                                Text(h.name).font(.caption).lineLimit(1)
                                Spacer()
                                Text("\(seen)/\(ds.count)").font(.caption.weight(.semibold))
                                    .foregroundStyle(seen == ds.count ? Color.green : Color.secondary)
                            }
                        }
                    }
                }
                .card()

                if !bySpecialty.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(title: "By specialty · \(cycle.title.lowercased())", systemImage: "stethoscope")
                        let maxCount = max(bySpecialty.first?.count ?? 1, 1)
                        ForEach(bySpecialty) { item in
                            HStack {
                                Text(item.name).font(.caption).frame(width: 110, alignment: .leading)
                                GeometryReader { geo in
                                    Capsule().fill(Theme.gradient)
                                        .frame(width: max(6, geo.size.width * CGFloat(item.count) / CGFloat(maxCount)))
                                }
                                .frame(height: 10)
                                Text("\(item.count)").font(.caption.weight(.semibold)).frame(width: 28, alignment: .trailing)
                            }
                        }
                    }
                    .card()
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(title: "Not visited in 30+ days", systemImage: "exclamationmark.circle.fill")
                    if notVisited30.isEmpty {
                        Text("Nobody — nice coverage.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(notVisited30.prefix(15)) { d in
                        NavigationLink {
                            DoctorDetailView(doctor: d)
                        } label: {
                            DoctorRowLabel(doctor: d, trailing: d.daysSinceLastVisit.map { "\($0)d" } ?? "never")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card()
            }
            .padding()
        }
    }

    private func statTile(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.gradient)
                .contentTransition(.numericText(value: Double(value)))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 14)
    }
}

// MARK: - Mileage

struct MileageView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MileageEntry.day, order: .reverse) private var entries: [MileageEntry]
    @Query private var visits: [Visit]
    @Query private var plans: [PlanItem]
    @State private var editing: MileageEntry?
    @State private var showNew = false
    @State private var calculating = false
    @State private var toast: String?

    private func total(since start: Date) -> Double {
        entries.filter { $0.day >= start }.reduce(0) { $0 + $1.km }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    kmTile("This week", total(since: Cycle.week.start()))
                    kmTile("This month", total(since: Cycle.month.start()))
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                Button {
                    calculateToday()
                } label: {
                    HStack {
                        Label("Calculate today from my visits", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        Spacer()
                        if calculating { ProgressView() }
                    }
                }
                .disabled(calculating)
                Button { showNew = true } label: {
                    Label("Add or edit a day manually", systemImage: "square.and.pencil")
                }
            } footer: {
                Text("Uses driving distance between the hospitals you visited, in order. Set a start point (home/office) in Settings to include the trip there and back.")
            }
            Section("Days") {
                if entries.isEmpty {
                    Text("No mileage logged yet").foregroundStyle(.secondary)
                }
                ForEach(entries) { e in
                    Button { editing = e } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.day.formatted(.dateTime.weekday(.abbreviated).day().month()))
                                    .foregroundStyle(.primary)
                                if !e.note.isEmpty {
                                    Text(e.note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(Fmt.km(e.km))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            context.delete(e)
                            try? context.save()
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(item: $editing) { e in MileageEditor(entry: e) }
        .sheet(isPresented: $showNew) { MileageEditor(entry: nil) }
        .toast($toast)
    }

    private func kmTile(_ title: String, _ km: Double) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%.0f", km))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.gradient)
            Text("km \(title.lowercased())").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 14)
    }

    private func calculateToday() {
        let day = Date().startOfDay
        let coords = Mileage.coordinates(for: day, visits: visits, plans: plans)
        guard coords.count > 1 else {
            toast = "Need at least 2 locations with map pins today"
            return
        }
        calculating = true
        Task { @MainActor in
            let km = await Mileage.estimateKm(coords)
            if let e = entries.first(where: { Calendar.current.isDate($0.day, inSameDayAs: day) }) {
                e.km = km
            } else {
                context.insert(MileageEntry(day: day, km: km))
            }
            try? context.save()
            calculating = false
            toast = "Today: \(Fmt.km(km))"
        }
    }
}

struct MileageEditor: View {
    let entry: MileageEntry?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var entries: [MileageEntry]
    @State private var day = Date()
    @State private var km = ""
    @State private var odoStart = ""
    @State private var odoEnd = ""
    @State private var note = ""
    @State private var loaded = false

    private var odometerKm: Double? {
        guard let s = Double(odoStart), let e = Double(odoEnd), e > s else { return nil }
        return e - s
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Day", selection: $day, displayedComponents: .date)
                    HStack {
                        Text("Kilometres")
                        Spacer()
                        TextField("0", text: $km)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                }
                Section {
                    TextField("Start reading", text: $odoStart).keyboardType(.decimalPad)
                    TextField("End reading", text: $odoEnd).keyboardType(.decimalPad)
                    if let o = odometerKm {
                        Button("Use odometer: \(Fmt.km(o))") { km = String(format: "%.1f", o) }
                    }
                } header: {
                    Text("Odometer (optional)")
                }
                Section("Note") {
                    TextField("e.g. Al Ain trip", text: $note)
                }
            }
            .navigationTitle(entry == nil ? "Mileage" : "Edit mileage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(Double(km) == nil && odometerKm == nil)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let e = entry {
                    day = e.day
                    km = String(format: "%.1f", e.km)
                    odoStart = e.odometerStart > 0 ? String(format: "%.0f", e.odometerStart) : ""
                    odoEnd = e.odometerEnd > 0 ? String(format: "%.0f", e.odometerEnd) : ""
                    note = e.note
                }
            }
        }
    }

    private func save() {
        let value = Double(km.replacingOccurrences(of: ",", with: ".")) ?? odometerKm ?? 0
        let target = entry ?? entries.first(where: { Calendar.current.isDate($0.day, inSameDayAs: day) })
        let e: MileageEntry
        if let target {
            e = target
        } else {
            e = MileageEntry(day: day, km: value)
            context.insert(e)
        }
        e.day = day.startOfDay
        e.km = value
        e.odometerStart = Double(odoStart) ?? 0
        e.odometerEnd = Double(odoEnd) ?? 0
        e.note = note
        e.isManual = true
        try? context.save()
        dismiss()
    }
}
