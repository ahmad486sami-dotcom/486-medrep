import SwiftUI
import SwiftData
import MapKit

struct DirectoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Hospital.name) private var hospitals: [Hospital]
    @Query(sort: \Doctor.name) private var doctors: [Doctor]
    @AppStorage(Keys.cycle) private var cycleRaw = Cycle.month.rawValue

    @State private var mode = 0
    @State private var search = ""
    @State private var statusFilter: DoctorStatus?
    @State private var showAddHospital = false
    @State private var showAddDoctor = false
    @State private var toast: String?

    private var cycleStart: Date { (Cycle(rawValue: cycleRaw) ?? .month).start() }

    private var filteredHospitals: [Hospital] {
        guard !search.isEmpty else { return hospitals }
        return hospitals.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.area.localizedCaseInsensitiveContains(search)
                || $0.doctors.contains { $0.name.localizedCaseInsensitiveContains(search) }
        }
    }

    private var hospitalAreas: [String] {
        Array(Set(filteredHospitals.map { $0.area.isEmpty ? "Other" : $0.area })).sorted()
    }

    private var filteredDoctors: [Doctor] {
        doctors.filter { d in
            (statusFilter == nil || d.status == statusFilter!)
                && (search.isEmpty
                    || d.name.localizedCaseInsensitiveContains(search)
                    || d.specialty.localizedCaseInsensitiveContains(search)
                    || (d.hospital?.name.localizedCaseInsensitiveContains(search) ?? false))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("View", selection: $mode.animation(.spring(response: 0.35))) {
                        Text("Hospitals (\(hospitals.count))").tag(0)
                        Text("Doctors (\(doctors.count))").tag(1)
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if hospitals.isEmpty && doctors.isEmpty {
                    Section {
                        EmptyStateView(
                            systemImage: "building.2",
                            title: "Your directory is empty",
                            message: "Add the hospitals and clinics you cover, then the doctors in each one.",
                            buttonTitle: "Add hospital",
                            action: { showAddHospital = true },
                            secondaryTitle: "Load sample data",
                            secondaryAction: {
                                SampleData.load(into: context)
                                Notifier.reschedule(context: context)
                                toast = "Sample data loaded"
                            }
                        )
                    }
                } else if mode == 0 {
                    hospitalSections
                } else {
                    doctorSection
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $search, prompt: mode == 0 ? "Hospital, area or doctor" : "Name, specialty or hospital")
            .navigationTitle("Directory")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showAddHospital = true } label: { Label("Add hospital / clinic", systemImage: "building.2") }
                        Button { showAddDoctor = true } label: { Label("Add doctor", systemImage: "person.badge.plus") }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                }
                if mode == 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Picker("Status", selection: $statusFilter) {
                                Text("All").tag(DoctorStatus?.none)
                                ForEach(DoctorStatus.allCases) { s in
                                    Label(s.title, systemImage: s.icon).tag(Optional(s))
                                }
                            }
                        } label: {
                            Image(systemName: statusFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddHospital) { HospitalEditor() }
            .sheet(isPresented: $showAddDoctor) { DoctorEditor() }
            .toast($toast)
        }
    }

    @ViewBuilder
    private var hospitalSections: some View {
        ForEach(hospitalAreas, id: \.self) { area in
            Section(area) {
                ForEach(filteredHospitals.filter { ($0.area.isEmpty ? "Other" : $0.area) == area }) { h in
                    NavigationLink {
                        HospitalDetailView(hospital: h)
                    } label: {
                        HospitalRow(hospital: h, cycleStart: cycleStart)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var doctorSection: some View {
        Section {
            if filteredDoctors.isEmpty {
                Text("No doctors match").foregroundStyle(.secondary)
            }
            ForEach(filteredDoctors) { d in
                NavigationLink {
                    DoctorDetailView(doctor: d)
                } label: {
                    DoctorRowLabel(doctor: d, trailing: d.daysSinceLastVisit.map { "\($0)d" })
                }
            }
        }
    }
}

struct HospitalRow: View {
    let hospital: Hospital
    let cycleStart: Date

    var body: some View {
        let active = hospital.doctors.filter { $0.status != .left }
        let seen = active.filter { $0.visited(since: cycleStart) }.count
        HStack(spacing: 12) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 17))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(hospital.name).font(.body.weight(.semibold))
                HStack(spacing: 6) {
                    Text("\(active.count) doctor\(active.count == 1 ? "" : "s")")
                    if !active.isEmpty {
                        Text("·")
                        Text("\(seen) visited")
                            .foregroundStyle(seen == active.count ? Color.green : Color.secondary)
                    }
                    if !hospital.hasLocation {
                        Image(systemName: "mappin.slash").foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Hospital detail

struct HospitalDetailView: View {
    @Bindable var hospital: Hospital
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Keys.cycle) private var cycleRaw = Cycle.month.rawValue

    @State private var showEdit = false
    @State private var showAddDoctor = false
    @State private var showExport = false
    @State private var confirmDelete = false
    @State private var toast: String?

    private var cycleStart: Date { (Cycle(rawValue: cycleRaw) ?? .month).start() }

    var body: some View {
        List {
            if hospital.hasLocation {
                Section {
                    Map(initialPosition: .region(MKCoordinateRegion(center: hospital.clCoordinate, latitudinalMeters: 900, longitudinalMeters: 900))) {
                        Marker(hospital.name, systemImage: "cross.case.fill", coordinate: hospital.clCoordinate)
                            .tint(Theme.accent)
                    }
                    .frame(height: 170)
                    .allowsHitTesting(false)
                    .listRowInsets(EdgeInsets())
                }
            }

            Section {
                HStack(spacing: 10) {
                    if let url = Links.tel(hospital.mainPhone) {
                        ActionTile(title: "Call", systemImage: "phone.fill") { openURL(url) }
                    }
                    if let url = Links.navigate(to: hospital) {
                        ActionTile(title: "Navigate", systemImage: "car.fill") { openURL(url) }
                    }
                    ActionTile(title: "Plan all", systemImage: "calendar.badge.plus") { planAll() }
                    ActionTile(title: "PDF", systemImage: "doc.richtext") { showExport = true }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if !hospital.phones.isEmpty || !hospital.address.isEmpty || !hospital.area.isEmpty {
                Section("Contact") {
                    if !hospital.area.isEmpty || !hospital.address.isEmpty {
                        Label([hospital.area, hospital.address].filter { !$0.isEmpty }.joined(separator: " · "), systemImage: "mappin.and.ellipse")
                    }
                    ForEach(hospital.phones) { phone in
                        Button {
                            if let url = Links.tel(phone.number) { openURL(url) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(phone.label).font(.caption).foregroundStyle(.secondary)
                                    Text(phone.number).foregroundStyle(.primary)
                                }
                                Spacer()
                                Image(systemName: "phone.circle.fill").font(.title2).foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }

            if !hospital.tips.isEmpty {
                Section("Tips · parking, gate, rep hours") {
                    Text(hospital.tips).font(.callout)
                }
            }

            Section("Doctors (\(hospital.activeDoctors.count))") {
                ForEach(hospital.doctors.sorted { $0.name < $1.name }) { d in
                    NavigationLink {
                        DoctorDetailView(doctor: d)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: d.visited(since: cycleStart) ? "checkmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(d.visited(since: cycleStart) ? Color.green : Color.secondary)
                            DoctorRowLabel(doctor: d, showHospital: false, trailing: d.daysSinceLastVisit.map { "\($0)d" })
                        }
                    }
                }
                Button {
                    showAddDoctor = true
                } label: {
                    Label("Add doctor here", systemImage: "person.badge.plus")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(hospital.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEdit = true } label: { Label("Edit", systemImage: "pencil") }
                    Button { showExport = true } label: { Label("Export PDF", systemImage: "doc.richtext") }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete hospital", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEdit) { HospitalEditor(hospital: hospital) }
        .sheet(isPresented: $showAddDoctor) { DoctorEditor(hospital: hospital) }
        .sheet(isPresented: $showExport) { ExportSheet(initialScope: .hospital, initialHospital: hospital) }
        .confirmationDialog("Delete \(hospital.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete hospital and its \(hospital.doctors.count) doctors", role: .destructive) {
                VisitActions.deleteHospital(hospital, context: context)
                dismiss()
            }
        } message: {
            Text("This also deletes their visits and recordings. It can't be undone.")
        }
        .toast($toast)
    }

    private func planAll() {
        let list = hospital.doctors.filter { $0.status == .available && !PlanActions.isPlanned($0, on: Date()) }
        guard !list.isEmpty else {
            toast = "Everyone here is already planned"
            return
        }
        PlanActions.add(list, to: Date(), context: context)
        toast = "Added \(list.count) to today"
    }
}

// MARK: - Hospital editor

struct HospitalDraft {
    var name = ""
    var area = "Abu Dhabi"
    var address = ""
    var coordinate: CLLocationCoordinate2D?
    var phoneReception = ""
    var phoneDepartment = ""
    var phoneOther = ""
    var tips = ""

    init() {}

    init(from h: Hospital) {
        name = h.name
        area = h.area
        address = h.address
        coordinate = h.coordinate
        phoneReception = h.phoneReception
        phoneDepartment = h.phoneDepartment
        phoneOther = h.phoneOther
        tips = h.tips
    }

    func apply(to h: Hospital) {
        h.name = name.trimmingCharacters(in: .whitespaces)
        h.area = area
        h.address = address
        if let coordinate {
            h.latitude = coordinate.latitude
            h.longitude = coordinate.longitude
            h.hasLocation = true
        } else {
            h.hasLocation = false
        }
        h.phoneReception = phoneReception
        h.phoneDepartment = phoneDepartment
        h.phoneOther = phoneOther
        h.tips = tips
    }
}

struct HospitalEditor: View {
    var hospital: Hospital?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @ObservedObject private var location = LocationManager.shared
    @State private var draft: HospitalDraft
    @State private var showPicker = false

    init(hospital: Hospital? = nil) {
        self.hospital = hospital
        _draft = State(initialValue: hospital.map { HospitalDraft(from: $0) } ?? HospitalDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Hospital / clinic") {
                    TextField("Name", text: $draft.name)
                    Picker("Area", selection: $draft.area) {
                        ForEach(areaOptions, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Address or building (optional)", text: $draft.address)
                }

                Section {
                    if let c = draft.coordinate {
                        Map(initialPosition: .region(MKCoordinateRegion(center: c, latitudinalMeters: 700, longitudinalMeters: 700))) {
                            Marker(draft.name.isEmpty ? "Here" : draft.name, coordinate: c).tint(Theme.accent)
                        }
                        .id("\(c.latitude),\(c.longitude)")
                        .frame(height: 150)
                        .allowsHitTesting(false)
                        .listRowInsets(EdgeInsets())
                    }
                    Button {
                        if let loc = location.location {
                            withAnimation { draft.coordinate = loc.coordinate }
                        } else {
                            location.request()
                        }
                    } label: {
                        Label("Use my current location", systemImage: "location.fill")
                    }
                    Button { showPicker = true } label: {
                        Label(draft.coordinate == nil ? "Find on map" : "Change on map", systemImage: "map")
                    }
                    if draft.coordinate != nil {
                        Button(role: .destructive) { withAnimation { draft.coordinate = nil } } label: {
                            Label("Remove location", systemImage: "mappin.slash")
                        }
                    }
                } header: {
                    Text("Map location")
                } footer: {
                    Text("Needed for the map, routes and mileage. Tip: add it while you're standing at the hospital.")
                }

                Section("Phone numbers") {
                    TextField("Reception", text: $draft.phoneReception).keyboardType(.phonePad)
                    TextField("Department", text: $draft.phoneDepartment).keyboardType(.phonePad)
                    TextField("Other (switchboard…)", text: $draft.phoneOther).keyboardType(.phonePad)
                }

                Section {
                    TextField("Parking, gate, rep visiting hours, sign-in rules…", text: $draft.tips, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Tips")
                }
            }
            .navigationTitle(hospital == nil ? "New hospital" : "Edit hospital")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showPicker) {
                LocationPickerSheet(coordinate: $draft.coordinate, address: $draft.address, initialQuery: draft.name)
            }
        }
    }

    private var areaOptions: [String] {
        var list = Areas.all
        if !draft.area.isEmpty && !list.contains(draft.area) { list.append(draft.area) }
        return list
    }

    private func save() {
        if let hospital {
            draft.apply(to: hospital)
        } else {
            let h = Hospital(name: draft.name)
            context.insert(h)
            draft.apply(to: h)
        }
        try? context.save()
        dismiss()
    }
}

// MARK: - Location picker

struct LocationPickerSheet: View {
    @Binding var coordinate: CLLocationCoordinate2D?
    @Binding var address: String
    var initialQuery: String

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var picked: CLLocationCoordinate2D?
    @State private var position: MapCameraPosition = .automatic
    @State private var searching = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                MapReader { proxy in
                    Map(position: $position) {
                        UserAnnotation()
                        if let picked {
                            Marker("Hospital", systemImage: "cross.case.fill", coordinate: picked)
                                .tint(Theme.accent)
                        }
                    }
                    .onTapGesture { point in
                        if let c = proxy.convert(point, from: .local) {
                            withAnimation(.spring) { picked = c }
                            results = []
                        }
                    }
                }
                .mapControls { MapUserLocationButton() }

                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search hospital or clinic", text: $query)
                            .submitLabel(.search)
                            .onSubmit(search)
                        if searching { ProgressView() }
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if !results.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(results, id: \.self) { item in
                                    Button {
                                        choose(item)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name ?? "Place").font(.subheadline.weight(.semibold))
                                            Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                    }
                                    .buttonStyle(.plain)
                                    Divider()
                                }
                            }
                        }
                        .frame(maxHeight: 260)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Text(picked == nil ? "Search, or tap the map to drop the pin" : "Pin set — tap Done, or tap elsewhere to move it")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                }
                .padding()
                .animation(.spring(response: 0.35), value: results.count)
            }
            .navigationTitle("Hospital location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let picked { coordinate = picked }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(picked == nil)
                }
            }
            .onAppear {
                query = initialQuery
                if let c = coordinate {
                    picked = c
                    position = .region(MKCoordinateRegion(center: c, latitudinalMeters: 1200, longitudinalMeters: 1200))
                } else {
                    position = .userLocation(fallback: .automatic)
                }
            }
        }
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let loc = LocationManager.shared.location {
            request.region = MKCoordinateRegion(center: loc.coordinate, latitudinalMeters: 80_000, longitudinalMeters: 80_000)
        }
        searching = true
        MKLocalSearch(request: request).start { response, _ in
            searching = false
            results = response?.mapItems ?? []
        }
    }

    private func choose(_ item: MKMapItem) {
        let c = item.placemark.coordinate
        withAnimation(.spring) {
            picked = c
            position = .region(MKCoordinateRegion(center: c, latitudinalMeters: 800, longitudinalMeters: 800))
            results = []
        }
        if address.isEmpty, let title = item.placemark.title { address = title }
    }
}
