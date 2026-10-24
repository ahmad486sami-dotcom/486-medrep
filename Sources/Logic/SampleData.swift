import Foundation
import SwiftData

enum SampleData {
    static func load(into context: ModelContext) {
        func hospital(_ name: String, _ area: String, _ lat: Double, _ lng: Double, tips: String) -> Hospital {
            let h = Hospital(name: name, area: area)
            h.latitude = lat
            h.longitude = lng
            h.hasLocation = true
            h.tips = tips
            h.isSample = true
            context.insert(h)
            return h
        }

        func window(_ weekdays: [Int], _ start: Int, _ end: Int) -> [AvailabilityWindow] {
            weekdays.map { AvailabilityWindow(weekday: $0, startMinutes: start, endMinutes: end) }
        }

        func doctor(_ name: String, _ specialty: String, at h: Hospital, priority: String, every: Int, windows: [AvailabilityWindow], products: [String], note: String) -> Doctor {
            let d = Doctor(name: name, specialty: specialty)
            d.priority = priority
            d.visitEveryDays = every
            d.availability = windows
            d.products = products
            d.generalNote = note
            d.isSample = true
            d.statusCheckedAt = Date().adding(days: -3)
            context.insert(d)
            d.hospital = h
            return d
        }

        let city = hospital("City Hospital (sample)", "Abu Dhabi", 24.4539, 54.3773, tips: "Parking B2. Rep hours 9–12. Sign in at reception.")
        let noor = hospital("Al Noor Clinic (sample)", "Abu Dhabi", 24.4870, 54.3600, tips: "Street parking only. Ask for the clinic coordinator.")
        let ain = hospital("Al Ain Medical Center (sample)", "Al Ain", 24.2075, 55.7447, tips: "Gate 2 for visitors. Security pass needed.")

        let d1 = doctor("Dr. Layla Haddad", "Cardiologist", at: city, priority: "A", every: 7,
                        windows: window([2, 4], 9 * 60, 12 * 60), products: ["Jardiance", "Pradaxa"],
                        note: "Prefers data over brochures. Short visits.")
        let d2 = doctor("Dr. Omar Khalil", "Endocrinologist", at: city, priority: "A", every: 14,
                        windows: window([2, 3, 5], 10 * 60, 13 * 60), products: ["Jardiance", "Trajenta", "Glyxambi"],
                        note: "Assistant Sara manages his schedule — call her first.")
        let d3 = doctor("Dr. Mariam Saeed", "Nephrologist", at: city, priority: "B", every: 14,
                        windows: window([3, 4], 13 * 60, 15 * 60), products: ["Jardiance"],
                        note: "")
        let d4 = doctor("Dr. Yousef Ali", "GP", at: noor, priority: "B", every: 21,
                        windows: window([2, 3, 4, 5, 6], 16 * 60, 19 * 60), products: ["Micardis", "Twynsta"],
                        note: "Evening clinic only.")
        let d5 = doctor("Dr. Hana Nasser", "Pulmonologist", at: noor, priority: "C", every: 30,
                        windows: window([4], 9 * 60, 11 * 60), products: ["Spiriva", "Spiolto"],
                        note: "")
        let d6 = doctor("Dr. Karim Mansour", "Internist", at: ain, priority: "B", every: 14,
                        windows: window([2, 5], 8 * 60, 11 * 60), products: ["Jardiance", "Synjardy"],
                        note: "")

        d1.phone = ""
        d5.status = .away
        d5.awayReason = "Conference"
        d5.returnDate = Date().adding(days: 5)

        let v1 = Visit(date: Date().adding(days: -9).at(minutes: 10 * 60))
        v1.summary = "Discussed cardio-renal outcomes. Asked for the latest study summary."
        v1.tags = ["Asked for study", "Follow-up needed"]
        v1.products = ["Jardiance"]
        context.insert(v1)
        v1.doctor = d1

        let v2 = Visit(date: Date().adding(days: -20).at(minutes: 11 * 60))
        v2.summary = "Positive on Trajenta for elderly patients. Samples given."
        v2.tags = ["Positive", "Samples given"]
        v2.products = ["Trajenta"]
        context.insert(v2)
        v2.doctor = d2

        let r = Reminder(title: "Bring the study summary", dueDate: Date().adding(days: 1).at(minutes: 9 * 60))
        context.insert(r)
        r.doctor = d1

        _ = [d3, d4, d6]
        try? context.save()
        PlanActions.add([d1, d2, d4], to: Date(), context: context)
    }

    static func remove(from context: ModelContext) {
        let hospitals = (try? context.fetch(FetchDescriptor<Hospital>())) ?? []
        for h in hospitals where h.isSample {
            VisitActions.deleteHospital(h, context: context)
        }
        try? context.save()
        Notifier.reschedule(context: context)
    }

    static func eraseAll(context: ModelContext) {
        try? context.delete(model: PlanItem.self)
        try? context.delete(model: Reminder.self)
        try? context.delete(model: Visit.self)
        try? context.delete(model: Doctor.self)
        try? context.delete(model: Hospital.self)
        try? context.delete(model: MileageEntry.self)
        try? context.delete(model: DayTarget.self)
        try? context.save()
        AudioStore.deleteAll()
        Notifier.reschedule(context: context)
    }
}
