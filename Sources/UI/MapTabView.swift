import SwiftUI
import SwiftData
import MapKit

enum PinState: Equatable {
    case visited, partial, notYet, inactive

    var color: Color {
        switch self {
        case .visited: return .green
        case .partial: return .orange
        case .notYet: return .red
        case .inactive: return .gray
        }
    }
}

struct MapTabView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Hospital.name) private var hospitals: [Hospital]
    @AppStorage(Keys.cycle) private var cycleRaw = Cycle.month.rawValue

    @State private var area = "All areas"
    @State private var specialty = "All specialties"
    @State private var availableNow = false
    @State private var selected: Hospital?
    @State private var position: MapCameraPosition = .automatic

    private var cycle: Cycle { Cycle(rawValue: cycleRaw) ?? .month }
    private var cycleStart: Date { cycle.start() }
    private var filtersActive: Bool { specialty != "All specialties" || availableNow }

    private func doctors(of h: Hospital) -> [Doctor] {
        h.doctors.filter { d in
            d.status != .left
                && (specialty == "All specialties" || d.specialty == specialty)
                && (!availableNow || d.isAvailableNow)
        }
        .sorted { $0.name < $1.name }
    }

    private var visible: [Hospital] {
        hospitals.filter { h in
            guard h.hasLocation else { return false }
            guard area == "All areas" || h.area == area else { return false }
            let ds = doctors(of: h)
            return !ds.isEmpty || (!filtersActive && h.doctors.isEmpty)
        }
    }

    private func pinState(_ h: Hospital) -> PinState {
        let active = doctors(of: h).filter { $0.status == .available || $0.visited(since: cycleStart) }
        if active.isEmpty { return .inactive }
        let seen = active.filter { $0.visited(since: cycleStart) }.count
        if seen == active.count { return .visited }
        if seen > 0 { return .partial }
        return .notYet
    }

    private var coverage: (seen: Int, total: Int) {
        let all = visible.flatMap { doctors(of: $0) }.filter { $0.status == .available || $0.visited(since: cycleStart) }
        return (all.filter { $0.visited(since: cycleStart) }.count, all.count)
    }

    private var areaOptions: [String] {
        let used = Set(hospitals.map { $0.area }.filter { !$0.isEmpty })
        return ["All areas"] + used.sorted()
    }

    private var specialtyOptions: [String] {
        let used = Set(hospitals.flatMap { $0.doctors }.map { $0.specialty }.filter { !$0.isEmpty })
        return ["All specialties"] + used.sorted()
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                UserAnnotation()
                ForEach(visible) { h in
                    Annotation(h.name, coordinate: h.clCoordinate, anchor: .bottom) {
                        HospitalPin(state: pinState(h), count: doctors(of: h).count)
                            .onTapGesture { selected = h }
                    }
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .safeAreaInset(edge: .top) { topOverlay }
            .overlay {
                if hospitals.filter({ $0.hasLocation }).isEmpty {
                    EmptyStateView(systemImage: "mappin.slash", title: "No locations yet", message: "Add a map location to your hospitals in the Directory to see them here.")
                        .card()
                        .padding(30)
                }
            }
            .sheet(item: $selected) { h in
                HospitalMapSheet(hospital: h, doctors: doctors(of: h), cycleStart: cycleStart, cycleTitle: cycle.shortTitle)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var topOverlay: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        Picker("Cycle", selection: $cycleRaw) {
                            ForEach(Cycle.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                    } label: {
                        filterLabel(cycle.title, systemImage: "calendar")
                    }
                    Menu {
                        Picker("Area", selection: $area) {
                            ForEach(areaOptions, id: \.self) { Text($0).tag($0) }
                        }
                    } label: {
                        filterLabel(area, systemImage: "map")
                    }
                    Menu {
                        Picker("Specialty", selection: $specialty) {
                            ForEach(specialtyOptions, id: \.self) { Text($0).tag($0) }
                        }
                    } label: {
                        filterLabel(specialty, systemImage: "stethoscope")
                    }
                    Button {
                        withAnimation(.spring) { availableNow.toggle() }
                    } label: {
                        filterLabel("Available now", systemImage: "clock.fill", active: availableNow)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
            }

            let c = coverage
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Visited \(c.seen) / \(c.total) doctors \(cycle.shortTitle)")
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.numericText())
                    Spacer()
                    Text(c.total > 0 ? "\(Int(Double(c.seen) / Double(c.total) * 100))%" : "—")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.accent)
                }
                ProgressView(value: c.total > 0 ? Double(c.seen) / Double(c.total) : 0)
                    .tint(Theme.accent)
                    .animation(.spring(response: 0.8), value: c.seen)
                HStack(spacing: 12) {
                    legend(.visited, "Visited")
                    legend(.partial, "Partly")
                    legend(.notYet, "Not yet")
                    legend(.inactive, "Away")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal)
        }
        .padding(.top, 6)
    }

    private func filterLabel(_ text: String, systemImage: String, active: Bool = false) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(active ? Color.white : Color.primary)
            .background {
                if active {
                    Capsule().fill(Theme.gradient)
                } else {
                    Capsule().fill(.regularMaterial)
                }
            }
    }

    private func legend(_ state: PinState, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(state.color).frame(width: 8, height: 8)
            Text(text)
        }
    }
}

// MARK: - Pin

struct HospitalPin: View {
    let state: PinState
    let count: Int
    @State private var dropped = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(state.color)
                    .frame(width: 38, height: 38)
                    .overlay(Circle().stroke(.white, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                Text("\(count)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Image(systemName: "triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(state.color)
                .rotationEffect(.degrees(180))
                .offset(y: -4)
        }
        .offset(y: dropped ? 0 : -40)
        .opacity(dropped ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: state)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(Double.random(in: 0...0.35))) {
                dropped = true
            }
        }
    }
}

// MARK: - Hospital sheet from the map

struct HospitalMapSheet: View {
    let hospital: Hospital
    let doctors: [Doctor]
    let cycleStart: Date
    let cycleTitle: String

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @State private var toast: String?
    @State private var others: [Doctor] = []
    @State private var askOthers = false
    @State private var recordDoctor: Doctor?
    @State private var blockedMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        if !hospital.mainPhone.isEmpty, let url = Links.tel(hospital.mainPhone) {
                            ActionTile(title: "Call", systemImage: "phone.fill") { openURL(url) }
                        }
                        if let url = Links.navigate(to: hospital) {
                            ActionTile(title: "Navigate", systemImage: "car.fill") { openURL(url) }
                        }
                        ActionTile(title: "Plan all", systemImage: "calendar.badge.plus") { planAll() }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section("Doctors · visited \(cycleTitle)") {
                    if doctors.isEmpty {
                        Text("No doctors here yet").foregroundStyle(.secondary)
                    }
                    ForEach(doctors) { d in
                        HStack(spacing: 10) {
                            VisitedToggle(isOn: d.visited(since: cycleStart)) { toggleVisited(d) }
                            NavigationLink {
                                DoctorDetailView(doctor: d)
                            } label: {
                                DoctorRowLabel(doctor: d, showHospital: false, trailing: d.daysSinceLastVisit.map { "\($0)d" })
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button { addToToday(d) } label: { Label("Plan", systemImage: "calendar.badge.plus") }
                                .tint(Theme.accent)
                            Button { recordDoctor = d } label: { Label("Record", systemImage: "mic.fill") }
                                .tint(.red)
                        }
                        .contextMenu {
                            Button { addToToday(d) } label: { Label("Add to today's plan", systemImage: "calendar.badge.plus") }
                            Button { recordDoctor = d } label: { Label("Record debrief", systemImage: "mic.fill") }
                            if !d.phone.isEmpty, let url = Links.tel(d.phone) {
                                Button { openURL(url) } label: { Label("Call doctor", systemImage: "phone") }
                            }
                        }
                    }
                }

                if !hospital.tips.isEmpty {
                    Section("Tips") {
                        Text(hospital.tips).font(.callout)
                    }
                }
            }
            .navigationTitle(hospital.name)
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Add the other doctors here too?", isPresented: $askOthers, titleVisibility: .visible) {
                Button("Add \(others.count) more") {
                    PlanActions.add(others, to: Date(), context: context)
                    toast = "Added \(others.count) more to today"
                }
                Button("No thanks", role: .cancel) {}
            } message: {
                Text(others.map { $0.displayName }.joined(separator: ", ") + " — not visited yet \(cycleTitle).")
            }
            .alert("Has a recorded debrief", isPresented: Binding(get: { blockedMessage != nil }, set: { if !$0 { blockedMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(blockedMessage ?? "")
            }
            .sheet(item: $recordDoctor) { d in RecorderSheet(preselected: d) }
            .toast($toast)
        }
    }

    private func toggleVisited(_ d: Doctor) {
        if d.visited(since: cycleStart) {
            if !VisitActions.unmarkVisited(d, since: cycleStart, context: context) {
                blockedMessage = "\(d.displayName) has a recorded visit \(cycleTitle). Open the profile to edit or delete it."
            }
        } else {
            VisitActions.markVisited(d, context: context)
            toast = "\(d.displayName) marked visited"
        }
        Notifier.reschedule(context: context)
    }

    private func addToToday(_ d: Doctor) {
        PlanActions.add([d], to: Date(), context: context)
        toast = "Added to today's plan"
        let candidates = hospital.activeDoctors.filter { o in
            o.id != d.id && o.status == .available && !o.visited(since: cycleStart) && !PlanActions.isPlanned(o, on: Date())
        }
        if !candidates.isEmpty {
            others = candidates
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { askOthers = true }
        }
    }

    private func planAll() {
        let list = doctors.filter { $0.status == .available && !PlanActions.isPlanned($0, on: Date()) }
        guard !list.isEmpty else {
            toast = "Everyone here is already planned"
            return
        }
        PlanActions.add(list, to: Date(), context: context)
        toast = "Added \(list.count) to today"
    }
}

struct VisitedToggle: View {
    let isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 26))
                .foregroundStyle(isOn ? Color.green : Color.red.opacity(0.7))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.success, trigger: isOn)
    }
}
