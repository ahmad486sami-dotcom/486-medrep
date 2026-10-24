import SwiftUI
import SwiftData
import PDFKit

enum ExportScope: String, CaseIterable, Identifiable {
    case doctor, hospital, area, visits, plan, mileage
    var id: String { rawValue }

    var title: String {
        switch self {
        case .doctor: return "One doctor"
        case .hospital: return "One hospital"
        case .area: return "An area"
        case .visits: return "Visits in a date range"
        case .plan: return "Week plan"
        case .mileage: return "Mileage"
        }
    }
}

struct ExportSheet: View {
    var initialScope: ExportScope = .doctor
    var initialDoctor: Doctor? = nil
    var initialHospital: Hospital? = nil

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Doctor.name) private var doctors: [Doctor]
    @Query(sort: \Hospital.name) private var hospitals: [Hospital]
    @Query(sort: \Visit.date, order: .reverse) private var visits: [Visit]
    @Query(sort: \PlanItem.startTime) private var plans: [PlanItem]
    @Query(sort: \MileageEntry.day) private var mileage: [MileageEntry]

    @State private var scope: ExportScope = .doctor
    @State private var doctorID: UUID?
    @State private var hospitalID: UUID?
    @State private var area = ""
    @State private var limitDates = false
    @State private var from = Date().startOfDay.adding(days: -30)
    @State private var to = Date()
    @State private var opts = PDFOptions()
    @State private var pdfURL: URL?
    @State private var building = false
    @State private var loaded = false

    private var areas: [String] {
        Array(Set(hospitals.map { $0.area }.filter { !$0.isEmpty })).sorted()
    }

    private var usesDates: Bool { scope == .visits || scope == .mileage || limitDates }

    var body: some View {
        NavigationStack {
            Form {
                Section("What to share") {
                    Picker("Export", selection: $scope) {
                        ForEach(ExportScope.allCases) { Text($0.title).tag($0) }
                    }
                    switch scope {
                    case .doctor:
                        Picker("Doctor", selection: $doctorID) {
                            Text("Choose").tag(UUID?.none)
                            ForEach(doctors) { Text($0.displayName).tag(Optional($0.id)) }
                        }
                    case .hospital:
                        Picker("Hospital", selection: $hospitalID) {
                            Text("Choose").tag(UUID?.none)
                            ForEach(hospitals) { Text($0.name).tag(Optional($0.id)) }
                        }
                    case .area:
                        Picker("Area", selection: $area) {
                            Text("Choose").tag("")
                            ForEach(areas, id: \.self) { Text($0).tag($0) }
                        }
                    case .plan:
                        DatePicker("Week starting", selection: $from, displayedComponents: .date)
                    case .visits, .mileage:
                        EmptyView()
                    }
                }

                if scope == .visits || scope == .mileage {
                    Section("Dates") {
                        DatePicker("From", selection: $from, displayedComponents: .date)
                        DatePicker("To", selection: $to, in: from..., displayedComponents: .date)
                    }
                } else if scope == .doctor || scope == .hospital || scope == .area {
                    Section("Dates") {
                        Toggle("Only visits in a date range", isOn: $limitDates.animation())
                        if limitDates {
                            DatePicker("From", selection: $from, displayedComponents: .date)
                            DatePicker("To", selection: $to, in: from..., displayedComponents: .date)
                        }
                    }
                }

                if scope != .mileage && scope != .plan {
                    Section {
                        Toggle("Contact details", isOn: $opts.contact)
                        Toggle("Status (away / left)", isOn: $opts.status)
                        Toggle("Clinic times", isOn: $opts.availability)
                        Toggle("Visit history", isOn: $opts.history)
                        Toggle("Visit summaries & notes", isOn: $opts.visitNotes)
                        Toggle("Hospital tips", isOn: $opts.hospitalTips)
                        Toggle("Private doctor notes", isOn: $opts.privateNotes)
                    } header: {
                        Text("Include")
                    } footer: {
                        Text("Private notes are off by default — only turn on if you want colleagues to see them.")
                    }
                }

                Section {
                    Button {
                        build()
                    } label: {
                        HStack {
                            Label("Create PDF", systemImage: "doc.badge.plus")
                                .font(.body.weight(.semibold))
                            Spacer()
                            if building { ProgressView() }
                        }
                    }
                    .disabled(!canBuild || building)
                }

                if let pdfURL {
                    Section("Ready") {
                        NavigationLink {
                            PDFPreview(url: pdfURL)
                                .ignoresSafeArea(edges: .bottom)
                                .navigationTitle("Preview")
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        ShareLink(item: pdfURL)
                                    }
                                }
                        } label: {
                            Label("Preview", systemImage: "eye")
                        }
                        ShareLink(item: pdfURL) {
                            Label("Share PDF (WhatsApp, email, AirDrop…)", systemImage: "square.and.arrow.up")
                                .font(.body.weight(.semibold))
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4), value: pdfURL)
            .navigationTitle("Export PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .onChange(of: scope) { _, _ in pdfURL = nil }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                scope = initialScope
                doctorID = initialDoctor?.id
                hospitalID = initialHospital?.id
                if initialScope == .plan {
                    from = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date().startOfDay
                }
            }
        }
    }

    private var canBuild: Bool {
        switch scope {
        case .doctor: return doctorID != nil
        case .hospital: return hospitalID != nil
        case .area: return !area.isEmpty
        default: return true
        }
    }

    private func build() {
        building = true
        let start: Date? = usesDates ? from.startOfDay : nil
        let end: Date? = usesDates ? to : nil
        var title = ""
        var subtitle = ""
        var body = ""
        var fileName = "486.pdf"

        switch scope {
        case .doctor:
            guard let d = doctors.first(where: { $0.id == doctorID }) else { building = false; return }
            title = d.displayName
            subtitle = [d.specialty, d.hospital?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
            if let h = d.hospital, opts.hospitalTips || opts.contact {
                body += PDFBuilder.hospitalHeader(h, opts: opts)
            }
            body += PDFBuilder.doctorSection(d, opts: opts, from: start, to: end, showHospital: false)
            fileName = "486 - \(d.displayName).pdf"
        case .hospital:
            guard let h = hospitals.first(where: { $0.id == hospitalID }) else { building = false; return }
            title = h.name
            subtitle = "\(h.activeDoctors.count) doctors"
            body = PDFBuilder.hospitalSection(h, opts: opts, from: start, to: end)
            fileName = "486 - \(h.name).pdf"
        case .area:
            let list = hospitals.filter { $0.area == area }
            title = area
            subtitle = "\(list.count) hospitals · \(list.reduce(0) { $0 + $1.activeDoctors.count }) doctors"
            body = list.map { PDFBuilder.hospitalSection($0, opts: opts, from: start, to: end) }.joined()
            fileName = "486 - \(area).pdf"
        case .visits:
            let endDay = to.startOfDay.adding(days: 1)
            let list = visits.filter { $0.date >= from.startOfDay && $0.date < endDay }
            title = "Visits"
            subtitle = "\(from.formatted(date: .abbreviated, time: .omitted)) – \(to.formatted(date: .abbreviated, time: .omitted)) · \(list.count) visits"
            body = list.isEmpty ? "<p class=\"muted\">No visits in this period.</p>" : PDFBuilder.visitsTable(list, opts: opts, showDoctor: true)
            fileName = "486 - Visits.pdf"
        case .plan:
            title = "Week plan"
            subtitle = "\(from.formatted(date: .abbreviated, time: .omitted)) – \(from.adding(days: 6).formatted(date: .abbreviated, time: .omitted))"
            let weekItems = plans.filter { $0.day >= from.startOfDay && $0.day < from.startOfDay.adding(days: 7) }
            body = PDFBuilder.planSection(weekItems, from: from)
            fileName = "486 - Week plan.pdf"
        case .mileage:
            let endDay = to.startOfDay.adding(days: 1)
            let list = mileage.filter { $0.day >= from.startOfDay && $0.day < endDay }
            title = "Mileage"
            subtitle = "\(from.formatted(date: .abbreviated, time: .omitted)) – \(to.formatted(date: .abbreviated, time: .omitted))"
            body = PDFBuilder.mileageSection(list)
            fileName = "486 - Mileage.pdf"
        }

        let html = PDFBuilder.document(title: title, subtitle: subtitle, body: body)
        DispatchQueue.main.async {
            withAnimation { pdfURL = PDFBuilder.render(html: html, fileName: fileName) }
            building = false
        }
    }
}

struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}
