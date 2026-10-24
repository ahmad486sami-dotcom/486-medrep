import Foundation
import CoreLocation
import SwiftData

/// One location in the day's route. Several doctors at the same hospital share one stop.
struct Stop: Identifiable {
    let id: String
    let hospital: Hospital?
    var items: [PlanItem]

    var startTime: Date { items.first?.startTime ?? Date() }
    var endTime: Date { items.last?.endTime ?? Date() }
    var title: String { hospital?.name ?? items.first?.doctor?.displayName ?? "Stop" }
}

enum Planner {

    // MARK: Grouping

    static func stops(for items: [PlanItem]) -> [Stop] {
        let sorted = items.sorted { a, b in
            if a.startTime == b.startTime { return a.order < b.order }
            return a.startTime < b.startTime
        }
        var result: [Stop] = []
        for item in sorted {
            let h = item.doctor?.hospital
            if let last = result.last, let lastHospital = last.hospital, let h, lastHospital.id == h.id {
                result[result.count - 1].items.append(item)
            } else {
                let key = (h?.id.uuidString ?? "solo") + "-" + item.id.uuidString
                result.append(Stop(id: key, hospital: h, items: [item]))
            }
        }
        return result
    }

    // MARK: Google Maps

    static func googleMapsURL(for hospitals: [Hospital]) -> URL? {
        var coords: [CLLocationCoordinate2D] = []
        var lastID: UUID?
        for h in hospitals where h.hasLocation {
            if h.id != lastID {
                coords.append(h.clCoordinate)
                lastID = h.id
            }
        }
        guard let dest = coords.last else { return nil }
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "www.google.com"
        comps.path = "/maps/dir/"
        var query = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(dest.latitude),\(dest.longitude)"),
            URLQueryItem(name: "travelmode", value: "driving")
        ]
        let middle = coords.dropLast()
        if !middle.isEmpty {
            let wp = middle.map { "\($0.latitude),\($0.longitude)" }.joined(separator: "|")
            query.append(URLQueryItem(name: "waypoints", value: wp))
        }
        comps.queryItems = query
        return comps.url
    }

    // MARK: Scheduling

    static func travelMinutes(from a: CLLocationCoordinate2D?, to b: CLLocationCoordinate2D?) -> Int {
        guard let a, let b else { return 15 }
        let km = Geo.km(a, b) * Geo.roadFactor
        if km < 0.3 { return 0 }
        let minutes = km / 35.0 * 60.0
        let rounded = Int((minutes / 5.0).rounded(.up)) * 5
        return max(10, rounded)
    }

    /// Earliest minute (>= `minutes`) at which the doctor can be seen on that weekday.
    static func nextStart(for doctor: Doctor?, weekday: Int, after minutes: Int) -> Int {
        guard let doctor else { return minutes }
        let windows = doctor.windows(on: weekday)
        if windows.isEmpty { return minutes }
        if let w = windows.first(where: { $0.endMinutes > minutes }) {
            return max(minutes, w.startMinutes)
        }
        return minutes
    }

    /// Orders the items: same-hospital doctors stacked together, each doctor inside their clinic window,
    /// and the next location chosen by whichever can start earliest (then the closest).
    static func autoSchedule(_ items: [PlanItem], day: Date, startMinutes: Int, startCoord: CLLocationCoordinate2D?) {
        guard !items.isEmpty else { return }
        let weekday = day.weekday

        var groups: [[PlanItem]] = []
        var index: [String: Int] = [:]
        for item in items {
            let key = item.doctor?.hospital?.id.uuidString ?? "solo-\(item.id.uuidString)"
            if let i = index[key] {
                groups[i].append(item)
            } else {
                index[key] = groups.count
                groups.append([item])
            }
        }

        var remaining = groups
        var current = startMinutes
        var position = startCoord
        var order = 0
        var first = true

        while !remaining.isEmpty {
            var bestIndex = 0
            var bestReady = Int.max
            var bestTravel = Int.max
            for (i, group) in remaining.enumerated() {
                let coord = group.first?.doctor?.hospital?.coordinate
                let travel = (first && position == nil) ? 0 : travelMinutes(from: position, to: coord)
                let arrive = current + travel
                let ready = group.map { nextStart(for: $0.doctor, weekday: weekday, after: arrive) }.min() ?? arrive
                if ready < bestReady || (ready == bestReady && travel < bestTravel) {
                    bestIndex = i
                    bestReady = ready
                    bestTravel = travel
                }
            }
            let group = remaining.remove(at: bestIndex)
            current += bestTravel
            let arrival = current
            let sortedGroup = group.sorted {
                nextStart(for: $0.doctor, weekday: weekday, after: arrival) < nextStart(for: $1.doctor, weekday: weekday, after: arrival)
            }
            for item in sortedGroup {
                let start = nextStart(for: item.doctor, weekday: weekday, after: current)
                item.startTime = day.startOfDay.at(minutes: start)
                item.order = order
                order += 1
                current = start + item.durationMinutes
            }
            if let c = group.first?.doctor?.hospital?.coordinate { position = c }
            first = false
        }
    }

    // MARK: Warnings

    static func warnings(for item: PlanItem, among items: [PlanItem]) -> [String] {
        var result: [String] = []
        guard let d = item.doctor else { return result }
        let day = item.day
        if d.status == .left {
            result.append("Left UAE")
        } else if d.isAway(on: day) {
            if let r = d.returnDate {
                result.append("Away until \(r.shortDate)")
            } else {
                result.append("Marked away" + (d.awayReason.isEmpty ? "" : " · \(d.awayReason)"))
            }
        }
        if !d.availability.isEmpty {
            let windows = d.windows(on: day.weekday)
            if windows.isEmpty {
                result.append("No clinic on \(Fmt.weekdayName(day.weekday))")
            } else {
                let s = item.startTime.minutesOfDay
                let e = s + item.durationMinutes
                let fits = windows.contains { s >= $0.startMinutes && e <= $0.endMinutes }
                if !fits {
                    result.append("Outside clinic time (" + windows.map { $0.timeLabel }.joined(separator: ", ") + ")")
                }
            }
        }
        let overlaps = items.contains { other in
            other.id != item.id && other.startTime < item.endTime && item.startTime < other.endTime
        }
        if overlaps { result.append("Overlaps another visit") }
        return result
    }

    // MARK: Suggestions

    static func dueScore(_ d: Doctor) -> Double {
        let days = Double(d.daysSinceLastVisit ?? 999)
        let every = Double(max(d.visitEveryDays, 1))
        let weight: Double
        switch d.priority {
        case "A": weight = 1.5
        case "C": weight = 0.7
        default: weight = 1.0
        }
        return days / every * weight
    }
}

// MARK: - Actions on the plan

enum PlanActions {
    static func items(on day: Date, context: ModelContext) -> [PlanItem] {
        let all = (try? context.fetch(FetchDescriptor<PlanItem>())) ?? []
        return all.filter { Calendar.current.isDate($0.day, inSameDayAs: day) }
    }

    static func isPlanned(_ doctor: Doctor, on day: Date) -> Bool {
        doctor.planItems.contains { Calendar.current.isDate($0.day, inSameDayAs: day) }
    }

    static func add(_ doctors: [Doctor], to day: Date, context: ModelContext) {
        let dayStart = day.startOfDay
        let existing = items(on: dayStart, context: context)
        let existingIDs = Set(existing.compactMap { $0.doctor?.id })
        let duration = Defaults.visitMinutes
        for d in doctors where !existingIDs.contains(d.id) {
            let item = PlanItem(day: dayStart, start: dayStart.at(minutes: Defaults.workStart), duration: duration)
            context.insert(item)
            item.doctor = d
        }
        try? context.save()
        arrange(day: dayStart, context: context)
    }

    static func arrange(day: Date, context: ModelContext) {
        let all = items(on: day, context: context)
        let done = all.filter { $0.isDone }.sorted { $0.startTime < $1.startTime }
        let pending = all.filter { !$0.isDone }
        var start = Defaults.workStart
        if let lastEnd = done.map({ $0.endTime.minutesOfDay }).max() { start = max(start, lastEnd) }
        if Calendar.current.isDateInToday(day) {
            let now = Date().minutesOfDay
            let rounded = Int((Double(now) / 5.0).rounded(.up)) * 5
            start = max(start, rounded)
        }
        let startCoord = done.last?.doctor?.hospital?.coordinate ?? Defaults.startCoordinate
        Planner.autoSchedule(pending, day: day, startMinutes: start, startCoord: startCoord)
        try? context.save()
        Notifier.reschedule(context: context)
    }

    static func remove(_ item: PlanItem, context: ModelContext) {
        context.delete(item)
        try? context.save()
        Notifier.reschedule(context: context)
    }
}

// MARK: - Visit actions

enum VisitActions {
    @discardableResult
    static func markVisited(_ doctor: Doctor, context: ModelContext) -> Visit {
        let v = Visit(date: Date())
        v.isQuick = true
        context.insert(v)
        v.doctor = doctor
        markPlanDone(for: doctor, on: Date())
        try? context.save()
        return v
    }

    /// Removes quick "marked visited" records in the period. Returns false if real debriefs exist.
    static func unmarkVisited(_ doctor: Doctor, since start: Date, context: ModelContext) -> Bool {
        let inPeriod = doctor.visits.filter { $0.date >= start }
        if inPeriod.contains(where: { $0.hasContent }) { return false }
        for v in inPeriod { context.delete(v) }
        for p in doctor.planItems where p.isDone && p.day >= start.startOfDay { p.isDone = false }
        try? context.save()
        return true
    }

    static func markPlanDone(for doctor: Doctor, on date: Date) {
        for p in doctor.planItems where Calendar.current.isDate(p.day, inSameDayAs: date) {
            p.isDone = true
        }
    }

    static func delete(_ visit: Visit, context: ModelContext) {
        AudioStore.delete(visit.audioFileName)
        context.delete(visit)
        try? context.save()
    }

    static func deleteDoctor(_ doctor: Doctor, context: ModelContext) {
        for v in doctor.visits { AudioStore.delete(v.audioFileName) }
        context.delete(doctor)
        try? context.save()
        Notifier.reschedule(context: context)
    }

    static func deleteHospital(_ hospital: Hospital, context: ModelContext) {
        for d in hospital.doctors {
            for v in d.visits { AudioStore.delete(v.audioFileName) }
        }
        context.delete(hospital)
        try? context.save()
        Notifier.reschedule(context: context)
    }
}
