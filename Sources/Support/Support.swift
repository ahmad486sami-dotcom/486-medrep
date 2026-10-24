import Foundation
import CoreLocation
import SwiftUI

// MARK: - Settings keys & defaults

enum Keys {
    static let faceID = "faceIDEnabled"
    static let weekdayTargets = "weekdayTargets"
    static let visitMinutes = "defaultVisitMinutes"
    static let workStart = "workStartMinutes"
    static let workEnd = "workEndMinutes"
    static let cycle = "cycle"
    static let speechLocale = "speechLocale"
    static let products = "productList"
    static let notifyMorning = "notifyMorning"
    static let morningMinutes = "morningMinutes"
    static let notifyPreVisit = "notifyPreVisit"
    static let preVisitLead = "preVisitLead"
    static let notifyEndOfDay = "notifyEndOfDay"
    static let notifyBackFromLeave = "notifyBackFromLeave"
    static let notifyOverdue = "notifyOverdue"
    static let notifyWeekly = "notifyWeekly"
    static let notifyStatusCheck = "notifyStatusCheck"
    static let hasStart = "hasStartLocation"
    static let startLat = "startLatitude"
    static let startLng = "startLongitude"
    static let includeStart = "includeStartInMileage"
}

enum Defaults {
    static let workStartDefault = 8 * 60
    static let workEndDefault = 17 * 60
    static let visitMinutesDefault = 15
    static let morningDefault = 7 * 60 + 30
    static let preVisitLeadDefault = 15
    /// Sunday ... Saturday
    static let weekdayTargetsDefault = "0,8,8,8,8,6,0"
    static let speechLocaleDefault = "en-US"
    static let productsDefault = "Jardiance|Synjardy|Glyxambi|Trajenta|Jentadueto|Pradaxa|Spiriva|Spiolto|Ofev|Micardis|Twynsta"

    static func int(_ key: String, _ def: Int) -> Int {
        (UserDefaults.standard.object(forKey: key) as? Int) ?? def
    }
    static func bool(_ key: String, _ def: Bool) -> Bool {
        (UserDefaults.standard.object(forKey: key) as? Bool) ?? def
    }
    static func string(_ key: String, _ def: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? def
    }

    static var workStart: Int { int(Keys.workStart, workStartDefault) }
    static var workEnd: Int { int(Keys.workEnd, workEndDefault) }
    static var visitMinutes: Int { int(Keys.visitMinutes, visitMinutesDefault) }
    static var products: [String] { parseList(string(Keys.products, productsDefault)) }
    static var weekdayTargets: [Int] { parseTargets(string(Keys.weekdayTargets, weekdayTargetsDefault)) }

    static func parseList(_ raw: String) -> [String] {
        raw.split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func parseTargets(_ raw: String) -> [Int] {
        var values = raw.split(separator: ",").map { Int(String($0)) ?? 0 }
        while values.count < 7 { values.append(0) }
        return Array(values.prefix(7))
    }

    static var startCoordinate: CLLocationCoordinate2D? {
        guard bool(Keys.hasStart, false) else { return nil }
        let d = UserDefaults.standard
        return CLLocationCoordinate2D(latitude: d.double(forKey: Keys.startLat), longitude: d.double(forKey: Keys.startLng))
    }
}

enum Targets {
    static func target(for day: Date, overrides: [DayTarget]) -> Int {
        if let o = overrides.first(where: { Calendar.current.isDate($0.day, inSameDayAs: day) }) {
            return o.target
        }
        return weekdayDefault(for: day)
    }

    static func weekdayDefault(for day: Date) -> Int {
        let t = Defaults.weekdayTargets
        let index = max(0, min(6, day.weekday - 1))
        return t[index]
    }
}

// MARK: - Fixed lists

enum Specialties {
    static let all = [
        "Cardiologist", "Endocrinologist", "Diabetologist", "Internist", "GP",
        "Family Physician", "Pulmonologist", "Nephrologist", "Neurologist",
        "Geriatrician", "Rheumatologist", "Pharmacist", "Other"
    ]
}

enum Areas {
    static let all = [
        "Abu Dhabi", "Al Ain", "Al Dhafra", "Dubai", "Sharjah",
        "Ajman", "Umm Al Quwain", "Ras Al Khaimah", "Fujairah"
    ]
}

enum VisitTags {
    static let all = ["Samples given", "Follow-up needed", "Asked for study", "Objection", "Positive", "Materials given", "Short visit", "Not available"]
}

enum AwayReasons {
    static let all = ["Leave", "Conference", "Sick", "Other"]
}

struct SpeechLocale: Identifiable, Hashable {
    let id: String
    let title: String
}

enum SpeechLocales {
    static let all: [SpeechLocale] = [
        SpeechLocale(id: "en-US", title: "English (US)"),
        SpeechLocale(id: "en-GB", title: "English (UK)"),
        SpeechLocale(id: "en-AE", title: "English (UAE)"),
        SpeechLocale(id: "ar-AE", title: "Arabic (UAE)"),
        SpeechLocale(id: "ar-SA", title: "Arabic (Saudi)")
    ]
}

// MARK: - Dates & formatting

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    var minutesOfDay: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: self)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    var weekday: Int { Calendar.current.component(.weekday, from: self) }

    func at(minutes: Int) -> Date {
        let m = max(0, min(minutes, 23 * 60 + 59))
        return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: self) ?? self
    }

    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    static func daysBetween(_ a: Date, _ b: Date) -> Int {
        Calendar.current.dateComponents([.day], from: a.startOfDay, to: b.startOfDay).day ?? 0
    }

    var shortTime: String { formatted(date: .omitted, time: .shortened) }
    var shortDate: String { formatted(.dateTime.day().month(.abbreviated)) }
    var dayTitle: String { formatted(.dateTime.weekday(.wide).day().month(.wide)) }
}

enum Fmt {
    static func hm(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    static func weekdayShort(_ weekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        let i = max(0, min(6, weekday - 1))
        return symbols[i]
    }

    static func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let i = max(0, min(6, weekday - 1))
        return symbols[i]
    }

    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func km(_ value: Double) -> String {
        String(format: "%.1f km", value)
    }

    static func relativeDays(_ date: Date) -> String {
        let d = Date.daysBetween(Date(), date)
        if d == 0 { return "Today" }
        if d == 1 { return "Tomorrow" }
        if d == -1 { return "Yesterday" }
        if d < 0 { return "\(-d) days ago" }
        return "In \(d) days"
    }
}

extension Set {
    mutating func toggle(_ element: Element) {
        if contains(element) { remove(element) } else { insert(element) }
    }
}

// MARK: - Geo & links

enum Geo {
    static let roadFactor = 1.3

    static func km(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 1000
    }
}

enum Links {
    static func tel(_ phone: String) -> URL? {
        let cleaned = phone.filter { $0.isNumber || $0 == "+" }
        guard !cleaned.isEmpty else { return nil }
        return URL(string: "tel:\(cleaned)")
    }

    static func whatsapp(_ phone: String) -> URL? {
        var digits = phone.filter { $0.isNumber }
        if digits.hasPrefix("00") { digits.removeFirst(2) }
        else if digits.hasPrefix("0") { digits = "971" + digits.dropFirst() }
        guard !digits.isEmpty else { return nil }
        return URL(string: "https://wa.me/\(digits)")
    }

    static func mail(_ email: String) -> URL? {
        guard !email.isEmpty else { return nil }
        return URL(string: "mailto:\(email)")
    }

    static func navigate(to hospital: Hospital) -> URL? {
        Planner.googleMapsURL(for: [hospital])
    }
}
