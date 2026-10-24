import Foundation
import SwiftData
import CoreLocation

// MARK: - Enums

enum DoctorStatus: String, CaseIterable, Identifiable {
    case available, away, left
    var id: String { rawValue }

    var title: String {
        switch self {
        case .available: return "Available"
        case .away: return "Away"
        case .left: return "Left UAE"
        }
    }

    var icon: String {
        switch self {
        case .available: return "checkmark.circle.fill"
        case .away: return "pause.circle.fill"
        case .left: return "airplane.departure"
        }
    }
}

enum Cycle: String, CaseIterable, Identifiable {
    case week, month, last30
    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "This week"
        case .month: return "This month"
        case .last30: return "Last 30 days"
        }
    }

    var shortTitle: String {
        switch self {
        case .week: return "this week"
        case .month: return "this month"
        case .last30: return "in 30 days"
        }
    }

    func start(_ now: Date = Date()) -> Date {
        let cal = Calendar.current
        switch self {
        case .week: return cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now.startOfDay
        case .month: return cal.dateInterval(of: .month, for: now)?.start ?? now.startOfDay
        case .last30: return now.startOfDay.adding(days: -29)
        }
    }
}

struct AvailabilityWindow: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    /// 1 = Sunday ... 7 = Saturday (Calendar weekday)
    var weekday: Int
    var startMinutes: Int
    var endMinutes: Int

    var timeLabel: String { "\(Fmt.hm(startMinutes))–\(Fmt.hm(endMinutes))" }
    var label: String { "\(Fmt.weekdayShort(weekday)) \(timeLabel)" }
}

struct PhoneEntry: Identifiable, Hashable {
    let label: String
    let number: String
    var id: String { label + number }
}

// MARK: - Hospital

@Model
final class Hospital {
    var id: UUID = UUID()
    var name: String = ""
    var area: String = ""
    var address: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var hasLocation: Bool = false
    var phoneReception: String = ""
    var phoneDepartment: String = ""
    var phoneOther: String = ""
    var tips: String = ""
    var createdAt: Date = Date()
    var isSample: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Doctor.hospital)
    var doctors: [Doctor] = []

    init(name: String, area: String = "") {
        self.name = name
        self.area = area
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var coordinate: CLLocationCoordinate2D? {
        hasLocation ? clCoordinate : nil
    }

    var activeDoctors: [Doctor] {
        doctors.filter { $0.status != .left }.sorted { $0.name < $1.name }
    }

    var mainPhone: String {
        [phoneReception, phoneDepartment, phoneOther].first(where: { !$0.isEmpty }) ?? ""
    }

    var phones: [PhoneEntry] {
        var list: [PhoneEntry] = []
        if !phoneReception.isEmpty { list.append(PhoneEntry(label: "Reception", number: phoneReception)) }
        if !phoneDepartment.isEmpty { list.append(PhoneEntry(label: "Department", number: phoneDepartment)) }
        if !phoneOther.isEmpty { list.append(PhoneEntry(label: "Other", number: phoneOther)) }
        return list
    }
}

// MARK: - Doctor

@Model
final class Doctor {
    var id: UUID = UUID()
    var name: String = ""
    var specialty: String = ""
    var department: String = ""
    var room: String = ""
    var phone: String = ""
    var phone2: String = ""
    var email: String = ""
    var assistantName: String = ""
    var priority: String = "B"
    var language: String = "English"
    var products: [String] = []
    var generalNote: String = ""
    var statusRaw: String = "available"
    var awayReason: String = ""
    var returnDate: Date? = nil
    var statusCheckedAt: Date? = nil
    var visitEveryDays: Int = 14
    var availabilityJSON: String = "[]"
    @Attribute(.externalStorage) var photoData: Data? = nil
    var importantDates: String = ""
    var createdAt: Date = Date()
    var isSample: Bool = false

    var hospital: Hospital?

    @Relationship(deleteRule: .cascade, inverse: \Visit.doctor)
    var visits: [Visit] = []

    @Relationship(deleteRule: .cascade, inverse: \Reminder.doctor)
    var reminders: [Reminder] = []

    @Relationship(deleteRule: .cascade, inverse: \PlanItem.doctor)
    var planItems: [PlanItem] = []

    init(name: String, specialty: String = "") {
        self.name = name
        self.specialty = specialty
    }

    var status: DoctorStatus {
        get { DoctorStatus(rawValue: statusRaw) ?? .available }
        set { statusRaw = newValue.rawValue }
    }

    var availability: [AvailabilityWindow] {
        get {
            (try? JSONDecoder().decode([AvailabilityWindow].self, from: Data(availabilityJSON.utf8))) ?? []
        }
        set {
            availabilityJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        }
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("dr") { return trimmed }
        return "Dr. \(trimmed)"
    }

    var initials: String {
        let cleaned = name.replacingOccurrences(of: "Dr.", with: "").replacingOccurrences(of: "Dr ", with: "")
        let parts = cleaned.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first.map { String($0) } }
        return letters.joined().uppercased()
    }

    func windows(on weekday: Int) -> [AvailabilityWindow] {
        availability.filter { $0.weekday == weekday }.sorted { $0.startMinutes < $1.startMinutes }
    }

    func isInWindow(_ date: Date) -> Bool {
        let m = date.minutesOfDay
        return windows(on: date.weekday).contains { m >= $0.startMinutes && m < $0.endMinutes }
    }

    var isAvailableNow: Bool { status == .available && isInWindow(Date()) }

    func isAway(on day: Date) -> Bool {
        switch status {
        case .available: return false
        case .left: return true
        case .away:
            if let r = returnDate { return day.startOfDay < r.startOfDay }
            return true
        }
    }

    var sortedVisits: [Visit] { visits.sorted { $0.date > $1.date } }
    var lastVisit: Visit? { visits.max(by: { $0.date < $1.date }) }

    var daysSinceLastVisit: Int? {
        guard let last = lastVisit else { return nil }
        return Date.daysBetween(last.date, Date())
    }

    func visited(since start: Date) -> Bool { visits.contains { $0.date >= start } }

    var openReminders: [Reminder] {
        reminders.filter { !$0.isDone }.sorted { $0.dueDate < $1.dueDate }
    }

    var isOverdue: Bool {
        guard visitEveryDays > 0, status == .available else { return false }
        guard let d = daysSinceLastVisit else { return true }
        return d >= visitEveryDays
    }

    var lastVisitText: String {
        guard let d = daysSinceLastVisit else { return "Never visited" }
        if d == 0 { return "Visited today" }
        if d == 1 { return "Visited yesterday" }
        return "Last visit \(d)d ago"
    }
}

// MARK: - Visit

@Model
final class Visit {
    var id: UUID = UUID()
    var date: Date = Date()
    var audioFileName: String? = nil
    var duration: Double = 0
    var transcript: String = ""
    var summary: String = ""
    var note: String = ""
    var tags: [String] = []
    var products: [String] = []
    var isQuick: Bool = false

    var doctor: Doctor?

    init(date: Date = Date()) {
        self.date = date
    }

    var audioURL: URL? {
        guard let audioFileName else { return nil }
        let url = AudioStore.directory.appendingPathComponent(audioFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var hasContent: Bool {
        audioFileName != nil || !note.isEmpty || !transcript.isEmpty || !summary.isEmpty
    }

    var headline: String {
        if !summary.isEmpty { return summary }
        if !note.isEmpty { return note }
        if !transcript.isEmpty { return transcript }
        return isQuick ? "Marked as visited" : "Visit"
    }
}

// MARK: - Reminder

@Model
final class Reminder {
    var id: UUID = UUID()
    var title: String = ""
    var dueDate: Date = Date()
    var isDone: Bool = false
    var createdAt: Date = Date()
    var visitID: UUID? = nil

    var doctor: Doctor?

    init(title: String, dueDate: Date) {
        self.title = title
        self.dueDate = dueDate
    }
}

// MARK: - Plan

@Model
final class PlanItem {
    var id: UUID = UUID()
    var day: Date = Date()
    var startTime: Date = Date()
    var durationMinutes: Int = 15
    var order: Int = 0
    var isDone: Bool = false

    var doctor: Doctor?

    init(day: Date, start: Date, duration: Int) {
        self.day = day.startOfDay
        self.startTime = start
        self.durationMinutes = duration
    }

    var endTime: Date { startTime.addingTimeInterval(Double(durationMinutes) * 60) }
}

// MARK: - Mileage & targets

@Model
final class MileageEntry {
    var id: UUID = UUID()
    var day: Date = Date()
    var km: Double = 0
    var odometerStart: Double = 0
    var odometerEnd: Double = 0
    var isManual: Bool = false
    var note: String = ""

    init(day: Date, km: Double) {
        self.day = day.startOfDay
        self.km = km
    }
}

@Model
final class DayTarget {
    var day: Date = Date()
    var target: Int = 0

    init(day: Date, target: Int) {
        self.day = day.startOfDay
        self.target = target
    }
}
