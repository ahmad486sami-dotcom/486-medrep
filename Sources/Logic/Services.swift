import Foundation
import CoreLocation
import LocalAuthentication
import UserNotifications
import SwiftData
import MapKit
import SwiftUI

// MARK: - Location

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    @Published var location: CLLocation?
    @Published var authorization: CLAuthorizationStatus = .notDetermined
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorization = manager.authorizationStatus
    }

    func request() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            manager.requestLocation()
        }
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if isAuthorized { manager.requestLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    func nearestHospital(_ hospitals: [Hospital], within meters: Double = 700) -> Hospital? {
        guard let loc = location else { return nil }
        var best: (Hospital, Double)?
        for h in hospitals where h.hasLocation {
            let d = loc.distance(from: CLLocation(latitude: h.latitude, longitude: h.longitude))
            if d <= meters, best == nil || d < best!.1 { best = (h, d) }
        }
        return best?.0
    }

    func distanceKm(to h: Hospital) -> Double? {
        guard let loc = location, h.hasLocation else { return nil }
        return loc.distance(from: CLLocation(latitude: h.latitude, longitude: h.longitude)) / 1000
    }
}

// MARK: - Face ID lock

final class LockManager: ObservableObject {
    @Published var isLocked: Bool
    private var isAuthenticating = false

    init() {
        isLocked = UserDefaults.standard.bool(forKey: Keys.faceID)
    }

    func lockIfNeeded() {
        if UserDefaults.standard.bool(forKey: Keys.faceID) { isLocked = true }
    }

    func unlock() {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        LockManager.authenticate(reason: "Unlock 486") { ok in
            self.isAuthenticating = false
            if ok {
                withAnimation(.easeInOut(duration: 0.35)) { self.isLocked = false }
            }
        }
    }

    static func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(true)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
            DispatchQueue.main.async { completion(ok) }
        }
    }
}

// MARK: - Notifications

enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private static func make(_ id: String, title: String, body: String, at date: Date, info: [String: String]) -> (Date, UNNotificationRequest)? {
        guard date > Date() else { return nil }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = info
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return (date, UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Rebuilds every scheduled reminder from the current data (iOS allows 64 pending).
    static func reschedule(context: ModelContext) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let doctors = (try? context.fetch(FetchDescriptor<Doctor>())) ?? []
        let reminders = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
        let plans = (try? context.fetch(FetchDescriptor<PlanItem>())) ?? []
        let cal = Calendar.current
        let today = Date().startOfDay
        var list: [(Date, UNNotificationRequest)] = []

        // Follow-ups
        for r in reminders where !r.isDone {
            var info = ["tab": AppTab.records.rawValue]
            var title = "Reminder"
            if let d = r.doctor {
                info = ["doctorID": d.id.uuidString]
                title = "Follow-up · \(d.displayName)"
            }
            if let n = make("rem-\(r.id.uuidString)", title: title, body: r.title, at: r.dueDate, info: info) { list.append(n) }
        }

        // Morning brief
        if Defaults.bool(Keys.notifyMorning, true) {
            let morning = Defaults.int(Keys.morningMinutes, Defaults.morningDefault)
            for i in 0..<7 {
                let day = today.adding(days: i)
                let items = plans.filter { cal.isDate($0.day, inSameDayAs: day) && !$0.isDone }.sorted { $0.startTime < $1.startTime }
                guard !items.isEmpty else { continue }
                let stopCount = Planner.stops(for: items).count
                var body = "\(items.count) visit\(items.count == 1 ? "" : "s") planned at \(stopCount) location\(stopCount == 1 ? "" : "s")."
                if let first = items.first, let d = first.doctor {
                    body += " First: \(d.displayName) at \(first.startTime.shortTime)."
                }
                body += " Tap to open your route."
                if let n = make("morning-\(i)", title: "Good morning", body: body, at: day.at(minutes: morning), info: ["tab": AppTab.today.rawValue]) {
                    list.append(n)
                }
            }
        }

        // Before each visit
        if Defaults.bool(Keys.notifyPreVisit, true) {
            let lead = Defaults.int(Keys.preVisitLead, Defaults.preVisitLeadDefault)
            let limit = today.adding(days: 3)
            for p in plans where !p.isDone && p.startTime < limit {
                guard let d = p.doctor else { continue }
                let place = d.hospital?.name ?? "your next stop"
                var body = "\(d.displayName) at \(p.startTime.shortTime) · \(place)."
                if !d.generalNote.isEmpty { body += " Note: \(d.generalNote.prefix(80))" }
                if let n = make("pre-\(p.id.uuidString)", title: "Next visit in \(lead) min", body: body, at: p.startTime.addingTimeInterval(Double(-lead * 60)), info: ["doctorID": d.id.uuidString]) {
                    list.append(n)
                }
            }
        }

        // End of day
        if Defaults.bool(Keys.notifyEndOfDay, true) {
            let end = Defaults.int(Keys.workEnd, Defaults.workEndDefault)
            for i in 0..<7 {
                let day = today.adding(days: i)
                let items = plans.filter { cal.isDate($0.day, inSameDayAs: day) }
                guard !items.isEmpty else { continue }
                let open = items.filter { !$0.isDone }.count
                let body = i == 0 && open > 0
                    ? "\(open) planned visit\(open == 1 ? " is" : "s are") not marked done. Record any missing debriefs."
                    : "Mark today's visits done and record any missing debriefs."
                if let n = make("eod-\(i)", title: "Wrap up your day", body: body, at: day.at(minutes: end), info: ["tab": AppTab.today.rawValue]) {
                    list.append(n)
                }
            }
        }

        for d in doctors {
            // Back from leave
            if Defaults.bool(Keys.notifyBackFromLeave, true), d.status == .away, let r = d.returnDate {
                if let n = make("back-\(d.id.uuidString)", title: "\(d.displayName) is back", body: "Expected back today\(d.hospital.map { " at \($0.name)" } ?? ""). Call to confirm before visiting.", at: r.startOfDay.at(minutes: 8 * 60), info: ["doctorID": d.id.uuidString]) {
                    list.append(n)
                }
            }
            // Visit frequency
            if Defaults.bool(Keys.notifyOverdue, true), d.status == .available, d.visitEveryDays > 0, let last = d.lastVisit {
                let due = last.date.startOfDay.adding(days: d.visitEveryDays).at(minutes: 9 * 60)
                if let n = make("due-\(d.id.uuidString)", title: "Time to see \(d.displayName)", body: "Not visited in \(d.visitEveryDays) days. Add to your plan?", at: due, info: ["doctorID": d.id.uuidString]) {
                    list.append(n)
                }
            }
            // Status check
            if Defaults.bool(Keys.notifyStatusCheck, false), d.status != .left, let checked = d.statusCheckedAt {
                let due = checked.startOfDay.adding(days: 14).at(minutes: 9 * 60 + 30)
                if let n = make("check-\(d.id.uuidString)", title: "Check \(d.displayName)'s status", body: "Status not confirmed in 2 weeks. Call the hospital?", at: due, info: ["doctorID": d.id.uuidString]) {
                    list.append(n)
                }
            }
        }

        list.sort { $0.0 < $1.0 }
        for (_, request) in list.prefix(60) {
            center.add(request, withCompletionHandler: nil)
        }

        // Weekly planning (repeats every Sunday 20:00)
        if Defaults.bool(Keys.notifyWeekly, true) {
            let content = UNMutableNotificationContent()
            content.title = "Plan your week"
            content.body = "Open the planner and pick who to visit this week."
            content.sound = .default
            content.userInfo = ["tab": AppTab.planner.rawValue]
            var comps = DateComponents()
            comps.weekday = 1
            comps.hour = 20
            comps.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            center.add(UNNotificationRequest(identifier: "weekly-plan", content: content, trigger: trigger), withCompletionHandler: nil)
        }
    }
}

// MARK: - Mileage

enum Mileage {
    static func coordinates(for day: Date, visits: [Visit], plans: [PlanItem]) -> [CLLocationCoordinate2D] {
        let cal = Calendar.current
        var hospitals: [Hospital] = visits
            .filter { cal.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date < $1.date }
            .compactMap { $0.doctor?.hospital }
        if hospitals.isEmpty {
            hospitals = plans
                .filter { cal.isDate($0.day, inSameDayAs: day) }
                .sorted { $0.startTime < $1.startTime }
                .compactMap { $0.doctor?.hospital }
        }
        var coords: [CLLocationCoordinate2D] = []
        var lastID: UUID?
        for h in hospitals where h.hasLocation && h.id != lastID {
            coords.append(h.clCoordinate)
            lastID = h.id
        }
        if coords.isEmpty { return [] }
        if Defaults.bool(Keys.includeStart, true), let start = Defaults.startCoordinate {
            coords.insert(start, at: 0)
            coords.append(start)
        }
        return coords
    }

    static func legKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) async -> Double {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
        request.transportType = .automobile
        if let response = try? await MKDirections(request: request).calculate(), let route = response.routes.first {
            return route.distance / 1000
        }
        return Geo.km(a, b) * Geo.roadFactor
    }

    static func estimateKm(_ coords: [CLLocationCoordinate2D]) async -> Double {
        guard coords.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<coords.count {
            total += await legKm(coords[i - 1], coords[i])
        }
        return (total * 10).rounded() / 10
    }
}
