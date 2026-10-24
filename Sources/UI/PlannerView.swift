import SwiftUI
import SwiftData

struct PlannerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(sort: \PlanItem.startTime) private var allPlans: [PlanItem]
    @Query private var targets: [DayTarget]

    @State private var weekStart: Date = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date().startOfDay
    @State private var selectedDay: Date = Date().startOfDay
    @State private var showAdd = false
    @State private var editingItem: PlanItem?
    @State private var showTarget = false
    @State private var confirmClear = false
    @State private var toast: String?

    private var dayItems: [PlanItem] {
        allPlans.filter { Calendar.current.isDate($0.day, inSameDayAs: selectedDay) }
    }

    private var stops: [Stop] { Planner.stops(for: dayItems) }
    private var target: Int { Targets.target(for: selectedDay, overrides: targets) }

    private var weekPlanned: Int {
        (0..<7).reduce(0) { sum, i in
            let day = weekStart.adding(days: i)
            return sum + allPlans.filter { Calendar.current.isDate($0.day, inSameDayAs: day) }.count
        }
    }

    private var weekTarget: Int {
        (0..<7).reduce(0) { $0 + Targets.target(for: weekStart.adding(days: $1), overrides: targets) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WeekStrip(weekStart: $weekStart, selected: $selectedDay) { day in
                        allPlans.filter { Calendar.current.isDate($0.day, inSameDayAs: day) }.count
                    }
                    Text("This week: \(weekPlanned) planned" + (weekTarget > 0 ? " · target \(weekTarget)" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 8)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section {
                    daySummary
                }

                if dayItems.isEmpty {
                    Section {
                        EmptyStateView(
                            systemImage: "calendar.badge.plus",
                            title: "Nothing planned",
                            message: "Add doctors for \(selectedDay.formatted(.dateTime.weekday(.wide))). Same-hospital doctors are grouped into one stop and timed inside their clinic hours.",
                            buttonTitle: "Add doctors",
                            action: { showAdd = true }
                        )
                    }
                }

                ForEach(stops) { stop in
                    Section {
                        ForEach(stop.items) { item in
                            PlanItemRow(item: item, warnings: Planner.warnings(for: item, among: dayItems))
                                .contentShape(Rectangle())
                                .onTapGesture { editingItem = item }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        withAnimation { PlanActions.remove(item, context: context) }
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        item.isDone.toggle()
                                        try? context.save()
                                    } label: {
                                        Label(item.isDone ? "Not done" : "Done", systemImage: "checkmark")
                                    }
                                    .tint(.green)
                                }
                        }
                    } header: {
                        StopHeader(stop: stop)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: dayItems.map { $0.id })
            .navigationTitle("Planner")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { arrange() } label: { Label("Auto-arrange times", systemImage: "wand.and.stars") }
                        Button { openRoute() } label: { Label("Open route in Google Maps", systemImage: "map") }
                        Button { showTarget = true } label: { Label("Set target for this day", systemImage: "target") }
                        Button {
                            withAnimation {
                                weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date().startOfDay
                                selectedDay = Date().startOfDay
                            }
                        } label: { Label("Go to today", systemImage: "calendar.circle") }
                        Divider()
                        Button(role: .destructive) { confirmClear = true } label: { Label("Clear this day", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                PlanAddSheet(day: selectedDay) { count in
                    toast = "Added \(count) · times arranged"
                }
            }
            .sheet(item: $editingItem) { item in
                PlanItemEditor(item: item)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showTarget) {
                TargetEditorSheet(day: selectedDay)
                    .presentationDetents([.medium])
            }
            .confirmationDialog("Remove all visits planned for this day?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear day", role: .destructive) {
                    for item in dayItems { context.delete(item) }
                    try? context.save()
                    Notifier.reschedule(context: context)
                }
            }
            .toast($toast)
        }
    }

    private var daySummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedDay.dayTitle).font(.headline)
                    Text("\(dayItems.count) planned · \(stops.count) location\(stops.count == 1 ? "" : "s")" + (dayItems.isEmpty ? "" : " · \(timeRange)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { showTarget = true } label: {
                    VStack(spacing: 0) {
                        Text(target > 0 ? "\(target)" : "—")
                            .font(.title3.weight(.bold))
                            .contentTransition(.numericText(value: Double(target)))
                        Text("target").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(width: 58, height: 50)
                    .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.borderless)
            }
            if target > 0 {
                ProgressView(value: Double(min(dayItems.count, target)), total: Double(target))
                    .tint(dayItems.count >= target ? Color.green : Theme.accent)
            }
            HStack(spacing: 10) {
                Button { showAdd = true } label: {
                    Label("Add", systemImage: "person.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                Button { arrange() } label: {
                    Label("Arrange", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
                .disabled(dayItems.isEmpty)
                Button { openRoute() } label: {
                    Label("Route", systemImage: "map").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
                .disabled(dayItems.isEmpty)
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(.vertical, 4)
    }

    private var timeRange: String {
        guard let first = stops.first, let last = stops.last else { return "" }
        return "\(first.startTime.shortTime)–\(last.endTime.shortTime)"
    }

    private func arrange() {
        withAnimation(.spring(response: 0.45)) {
            PlanActions.arrange(day: selectedDay, context: context)
        }
        toast = "Times arranged"
    }

    private func openRoute() {
        let hospitals = stops.filter { s in s.items.contains { !$0.isDone } }.compactMap { $0.hospital }
        if let url = Planner.googleMapsURL(for: hospitals) {
            openURL(url)
        } else {
            toast = "Add map locations to these hospitals first"
        }
    }
}

// MARK: - Week strip

struct WeekStrip: View {
    @Binding var weekStart: Date
    @Binding var selected: Date
    let count: (Date) -> Int
    @Namespace private var ns

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { shift(-7) } label: { Image(systemName: "chevron.left").padding(8) }
                Spacer()
                Text("\(weekStart.shortDate) – \(weekStart.adding(days: 6).shortDate)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button { shift(7) } label: { Image(systemName: "chevron.right").padding(8) }
            }
            .buttonStyle(.borderless)
            .tint(Theme.accent)

            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    dayButton(weekStart.adding(days: i))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func dayButton(_ day: Date) -> some View {
        let isSelected = Calendar.current.isDate(day, inSameDayAs: selected)
        let isToday = Calendar.current.isDateInToday(day)
        let n = count(day)
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selected = day.startOfDay }
        } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption2.weight(.medium))
                Text(day.formatted(.dateTime.day()))
                    .font(.headline)
                Text(n > 0 ? "\(n)" : " ")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Theme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.white : (isToday ? Theme.accent : Color.primary))
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.gradient)
                        .matchedGeometryEffect(id: "selectedDay", in: ns)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func shift(_ days: Int) {
        withAnimation(.spring(response: 0.4)) {
            weekStart = weekStart.adding(days: days)
            selected = selected.adding(days: days)
        }
    }
}

// MARK: - Rows

struct StopHeader: View {
    let stop: Stop
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: stop.items.count > 1 ? "building.2.fill" : "mappin.circle.fill")
                .foregroundStyle(Theme.accent)
            Text(stop.title)
                .textCase(nil)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            if stop.items.count > 1 {
                Text("\(stop.items.count) doctors")
                    .textCase(nil)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.accent.opacity(0.12), in: Capsule())
                    .foregroundStyle(Theme.accent)
            }
            Spacer()
            if let phone = stop.hospital?.mainPhone, !phone.isEmpty, let url = Links.tel(phone) {
                Button { openURL(url) } label: { Image(systemName: "phone.fill") }
                    .buttonStyle(.borderless)
                    .tint(Theme.accent)
            }
        }
    }
}

struct PlanItemRow: View {
    let item: PlanItem
    let warnings: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.startTime.shortTime)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("\(item.durationMinutes) min")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 66, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.doctor?.displayName ?? "Doctor")
                    .font(.body.weight(.semibold))
                    .strikethrough(item.isDone)
                if let d = item.doctor {
                    Text(detail(for: d))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(warnings, id: \.self) { w in
                    Label(w, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            if item.isDone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(.scale)
            }
        }
        .padding(.vertical, 2)
    }

    private func detail(for d: Doctor) -> String {
        var parts: [String] = []
        if !d.specialty.isEmpty { parts.append(d.specialty) }
        let windows = d.windows(on: item.day.weekday)
        if !windows.isEmpty {
            parts.append("Clinic " + windows.map { $0.timeLabel }.joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Edit one planned visit

struct PlanItemEditor: View {
    @Bindable var item: PlanItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            Form {
                if let d = item.doctor {
                    Section {
                        DoctorRowLabel(doctor: d)
                        let windows = d.windows(on: item.day.weekday)
                        if !windows.isEmpty {
                            Label("Clinic: " + windows.map { $0.timeLabel }.joined(separator: ", "), systemImage: "clock")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else if !d.availability.isEmpty {
                            Label("No clinic on \(Fmt.weekdayName(item.day.weekday))", systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Section("Time") {
                    DatePicker("Start", selection: $item.startTime, displayedComponents: .hourAndMinute)
                    Stepper("Duration: \(item.durationMinutes) min", value: $item.durationMinutes, in: 5...120, step: 5)
                }
                Section {
                    Toggle("Visit done", isOn: $item.isDone)
                }
                if let d = item.doctor {
                    Section {
                        NavigationLink("Open doctor profile") { DoctorDetailView(doctor: d) }
                    }
                }
            }
            .navigationTitle("Planned visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? context.save()
                        Notifier.reschedule(context: context)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Add doctors to a day

struct PlanAddSheet: View {
    let day: Date
    var onAdded: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Doctor.name) private var doctors: [Doctor]
    @Query private var plans: [PlanItem]
    @AppStorage(Keys.cycle) private var cycleRaw = Cycle.month.rawValue

    @State private var selected: Set<UUID> = []
    @State private var mode = 0
    @State private var search = ""
    @State private var others: [Doctor] = []
    @State private var askOthers = false

    private var cycleStart: Date { (Cycle(rawValue: cycleRaw) ?? .month).start() }

    private var plannedIDs: Set<UUID> {
        Set(plans.filter { Calendar.current.isDate($0.day, inSameDayAs: day) }.compactMap { $0.doctor?.id })
    }

    private var candidates: [Doctor] {
        doctors.filter { $0.status != .left && !plannedIDs.contains($0.id) }
    }

    private var list: [Doctor] {
        var base = candidates
        if mode == 0 {
            base = base.filter { !$0.isAway(on: day) }.sorted { Planner.dueScore($0) > Planner.dueScore($1) }
        } else if mode == 2 {
            base = base.sorted { ($0.hospital?.name ?? "~", $0.name) < ($1.hospital?.name ?? "~", $1.name) }
        }
        if !search.isEmpty {
            base = base.filter {
                $0.name.localizedCaseInsensitiveContains(search)
                    || $0.specialty.localizedCaseInsensitiveContains(search)
                    || ($0.hospital?.name.localizedCaseInsensitiveContains(search) ?? false)
            }
        }
        return base
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Show", selection: $mode) {
                        Text("Suggested").tag(0)
                        Text("A–Z").tag(1)
                        Text("By hospital").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                if candidates.isEmpty {
                    Text(doctors.isEmpty ? "Add doctors in the Directory first." : "Everyone is already planned for this day.")
                        .foregroundStyle(.secondary)
                }

                ForEach(list) { d in
                    let away = d.isAway(on: day)
                    Button {
                        withAnimation(.spring(response: 0.3)) { selected.toggle(d.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected.contains(d.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selected.contains(d.id) ? Theme.accent : Color.secondary)
                                .contentTransition(.symbolEffect(.replace))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(d.displayName).font(.body.weight(.semibold))
                                    if d.priority == "A" {
                                        Text("A").font(.caption2.weight(.heavy)).padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Color.orange.opacity(0.18), in: Capsule()).foregroundStyle(.orange)
                                    }
                                }
                                Text(reason(for: d))
                                    .font(.caption)
                                    .foregroundStyle(away ? Color.orange : Color.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(away ? 0.55 : 1)
                }
            }
            .searchable(text: $search, prompt: "Search doctors")
            .navigationTitle("Plan \(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selected.isEmpty ? "" : "(\(selected.count))")") { add() }
                        .fontWeight(.semibold)
                        .disabled(selected.isEmpty)
                }
            }
            .confirmationDialog("Same hospital, not visited yet", isPresented: $askOthers, titleVisibility: .visible) {
                Button("Add \(others.count) more too") { commit(includeOthers: true) }
                Button("Just my selection") { commit(includeOthers: false) }
            } message: {
                Text(others.map { "\($0.displayName) (\($0.hospital?.name ?? ""))" }.joined(separator: "\n"))
            }
        }
    }

    private func reason(for d: Doctor) -> String {
        var parts: [String] = []
        if let h = d.hospital { parts.append(h.name) }
        if d.isAway(on: day) {
            parts.append(d.status == .left ? "Left UAE" : "Away" + (d.returnDate.map { " until \($0.shortDate)" } ?? ""))
        } else {
            parts.append(d.lastVisitText)
            let w = d.windows(on: day.weekday)
            if !w.isEmpty {
                parts.append("Clinic " + w.map { $0.timeLabel }.joined(separator: ", "))
            } else if !d.availability.isEmpty {
                parts.append("No clinic this day")
            }
        }
        return parts.joined(separator: " · ")
    }

    private func add() {
        let chosen = doctors.filter { selected.contains($0.id) }
        let hospitalIDs = Set(chosen.compactMap { $0.hospital?.id })
        others = doctors.filter { d in
            guard let hid = d.hospital?.id, hospitalIDs.contains(hid) else { return false }
            return !selected.contains(d.id)
                && !plannedIDs.contains(d.id)
                && d.status == .available
                && !d.isAway(on: day)
                && !d.visited(since: cycleStart)
        }
        if others.isEmpty {
            commit(includeOthers: false)
        } else {
            askOthers = true
        }
    }

    private func commit(includeOthers: Bool) {
        var chosen = doctors.filter { selected.contains($0.id) }
        if includeOthers { chosen += others }
        PlanActions.add(chosen, to: day, context: context)
        onAdded(chosen.count)
        dismiss()
    }
}
