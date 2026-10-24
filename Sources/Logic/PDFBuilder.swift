import UIKit

struct PDFOptions {
    var contact = true
    var status = true
    var availability = true
    var history = true
    var visitNotes = true
    var privateNotes = false
    var hospitalTips = true
}

enum PDFBuilder {

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    static let css = """
    body { font-family: -apple-system, Helvetica, Arial, sans-serif; color: #1c1c1e; font-size: 11pt; }
    .brand { color: #0a7866; font-weight: 800; font-size: 26pt; margin: 0; }
    .sub { color: #6b6b70; font-size: 10pt; margin-top: 2px; margin-bottom: 18px; }
    h2 { color: #0a7866; font-size: 15pt; margin: 22px 0 6px 0; border-bottom: 2px solid #0a7866; padding-bottom: 4px; }
    h3 { font-size: 12.5pt; margin: 14px 0 4px 0; }
    .muted { color: #6b6b70; }
    .pill { display: inline-block; padding: 1px 8px; border-radius: 9px; font-size: 9pt; font-weight: 600; }
    .available { background: #dff5e6; color: #1a7f37; }
    .away { background: #fff1d6; color: #9a6200; }
    .left { background: #ececee; color: #555; }
    table { width: 100%; border-collapse: collapse; margin-top: 6px; }
    th { text-align: left; font-size: 9.5pt; color: #6b6b70; border-bottom: 1px solid #d1d1d6; padding: 4px 6px; }
    td { vertical-align: top; border-bottom: 1px solid #ececee; padding: 5px 6px; font-size: 10pt; }
    .card { border: 1px solid #e3e3e8; border-radius: 10px; padding: 8px 12px; margin: 8px 0; }
    .footer { margin-top: 26px; color: #9a9aa0; font-size: 8.5pt; }
    """

    static func document(title: String, subtitle: String, body: String) -> String {
        """
        <html><head><meta charset="utf-8"><style>\(css)</style></head><body>
        <p class="brand">486</p>
        <h1 style="font-size:18pt;margin:0;">\(esc(title))</h1>
        <p class="sub">\(esc(subtitle)) · Created \(esc(Date().formatted(date: .abbreviated, time: .shortened)))</p>
        \(body)
        <p class="footer">Shared from 486 · for internal use</p>
        </body></html>
        """
    }

    static func statusPill(_ d: Doctor) -> String {
        var text = d.status.title
        if d.status == .away {
            if !d.awayReason.isEmpty { text += " · \(d.awayReason)" }
            if let r = d.returnDate { text += " · back \(r.shortDate)" }
        }
        return "<span class=\"pill \(d.status.rawValue)\">\(esc(text))</span>"
    }

    static func doctorSection(_ d: Doctor, opts: PDFOptions, from: Date?, to: Date?, showHospital: Bool) -> String {
        var html = "<h3>\(esc(d.displayName))"
        if opts.status { html += " &nbsp;" + statusPill(d) }
        html += "</h3>"
        var line: [String] = []
        if !d.specialty.isEmpty { line.append(d.specialty) }
        if showHospital, let h = d.hospital { line.append(h.name) }
        if !d.department.isEmpty { line.append(d.department) }
        if !d.room.isEmpty { line.append("Room \(d.room)") }
        if !line.isEmpty { html += "<div class=\"muted\">\(esc(line.joined(separator: " · ")))</div>" }

        if opts.contact {
            var rows: [String] = []
            if !d.phone.isEmpty { rows.append("Phone: \(d.phone)") }
            if !d.phone2.isEmpty { rows.append("Phone 2: \(d.phone2)") }
            if !d.email.isEmpty { rows.append("Email: \(d.email)") }
            if !d.assistantName.isEmpty { rows.append("Assistant: \(d.assistantName)") }
            if !rows.isEmpty { html += "<div>\(esc(rows.joined(separator: "  ·  ")))</div>" }
        }
        if opts.status, let checked = d.statusCheckedAt {
            html += "<div class=\"muted\">Status checked \(esc(checked.shortDate))</div>"
        }
        if opts.availability {
            let windows = d.availability.sorted { ($0.weekday, $0.startMinutes) < ($1.weekday, $1.startMinutes) }
            if !windows.isEmpty {
                html += "<div><b>Clinic times:</b> \(esc(windows.map { $0.label }.joined(separator: ", ")))</div>"
            }
        }
        if opts.privateNotes, !d.generalNote.isEmpty {
            html += "<div class=\"card\"><b>Notes:</b> \(esc(d.generalNote))</div>"
        }
        if opts.history {
            let visits = d.sortedVisits.filter { v in
                (from == nil || v.date >= from!.startOfDay) && (to == nil || v.date < to!.startOfDay.adding(days: 1))
            }
            html += "<div style=\"margin-top:6px\"><b>Meetings:</b> \(visits.count)"
            if let last = d.lastVisit { html += " · last \(esc(last.date.shortDate))" }
            html += "</div>"
            if !visits.isEmpty {
                html += visitsTable(visits, opts: opts, showDoctor: false)
            }
        }
        return html
    }

    static func visitsTable(_ visits: [Visit], opts: PDFOptions, showDoctor: Bool) -> String {
        var html = "<table><tr><th style=\"width:18%\">Date</th>"
        if showDoctor { html += "<th style=\"width:22%\">Doctor</th>" }
        html += "<th>Details</th></tr>"
        for v in visits {
            html += "<tr><td>\(esc(v.date.formatted(date: .abbreviated, time: .shortened)))</td>"
            if showDoctor {
                let who = v.doctor?.displayName ?? "—"
                let place = v.doctor?.hospital?.name ?? ""
                html += "<td>\(esc(who))<br><span class=\"muted\">\(esc(place))</span></td>"
            }
            var parts: [String] = []
            if opts.visitNotes {
                if !v.summary.isEmpty { parts.append(esc(v.summary)) }
                if !v.note.isEmpty { parts.append("<i>\(esc(v.note))</i>") }
            }
            if !v.products.isEmpty { parts.append("<span class=\"muted\">Products: \(esc(v.products.joined(separator: ", ")))</span>") }
            if !v.tags.isEmpty { parts.append("<span class=\"muted\">Tags: \(esc(v.tags.joined(separator: ", ")))</span>") }
            if parts.isEmpty { parts.append(v.isQuick ? "Visited" : "—") }
            html += "<td>\(parts.joined(separator: "<br>"))</td></tr>"
        }
        html += "</table>"
        return html
    }

    static func hospitalHeader(_ h: Hospital, opts: PDFOptions) -> String {
        var html = "<h2>\(esc(h.name))</h2>"
        var line: [String] = []
        if !h.area.isEmpty { line.append(h.area) }
        if !h.address.isEmpty { line.append(h.address) }
        if !line.isEmpty { html += "<div class=\"muted\">\(esc(line.joined(separator: " · ")))</div>" }
        if opts.contact, !h.phones.isEmpty {
            html += "<div>" + esc(h.phones.map { "\($0.label): \($0.number)" }.joined(separator: "  ·  ")) + "</div>"
        }
        if opts.hospitalTips, !h.tips.isEmpty {
            html += "<div class=\"card\"><b>Tips:</b> \(esc(h.tips))</div>"
        }
        return html
    }

    static func hospitalSection(_ h: Hospital, opts: PDFOptions, from: Date?, to: Date?) -> String {
        var html = hospitalHeader(h, opts: opts)
        for d in h.activeDoctors {
            html += doctorSection(d, opts: opts, from: from, to: to, showHospital: false)
        }
        return html
    }

    static func planSection(_ items: [PlanItem], from: Date) -> String {
        var html = ""
        let cal = Calendar.current
        for i in 0..<7 {
            let day = from.startOfDay.adding(days: i)
            let dayItems = items.filter { cal.isDate($0.day, inSameDayAs: day) }
            guard !dayItems.isEmpty else { continue }
            html += "<h2>\(esc(day.dayTitle))</h2><table><tr><th style=\"width:16%\">Time</th><th style=\"width:34%\">Location</th><th>Doctor</th></tr>"
            for stop in Planner.stops(for: dayItems) {
                for item in stop.items {
                    let who = item.doctor.map { "\($0.displayName) · \($0.specialty)" } ?? "—"
                    html += "<tr><td>\(esc(item.startTime.shortTime))</td><td>\(esc(stop.title))</td><td>\(esc(who))\(item.isDone ? " ✓" : "")</td></tr>"
                }
            }
            html += "</table>"
        }
        if html.isEmpty { html = "<p class=\"muted\">No visits planned this week.</p>" }
        return html
    }

    static func mileageSection(_ entries: [MileageEntry]) -> String {
        let total = entries.reduce(0) { $0 + $1.km }
        var html = "<h2>Mileage</h2><p><b>Total: \(esc(Fmt.km(total)))</b> over \(entries.count) day\(entries.count == 1 ? "" : "s")</p>"
        html += "<table><tr><th>Date</th><th>Km</th><th>Odometer</th><th>Note</th></tr>"
        for e in entries.sorted(by: { $0.day < $1.day }) {
            let odo = (e.odometerStart > 0 && e.odometerEnd > 0) ? "\(Int(e.odometerStart)) → \(Int(e.odometerEnd))" : ""
            html += "<tr><td>\(esc(e.day.formatted(date: .abbreviated, time: .omitted)))</td><td>\(esc(Fmt.km(e.km)))</td><td>\(esc(odo))</td><td>\(esc(e.note))</td></tr>"
        }
        html += "</table>"
        return html
    }

    /// Renders HTML into an A4 PDF file and returns its URL.
    static func render(html: String, fileName: String) -> URL? {
        let formatter = UIMarkupTextPrintFormatter(markupText: html)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        let paper = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let printable = paper.insetBy(dx: 36, dy: 40)
        renderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: printable), forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        let bounds = UIGraphicsGetPDFContextBounds()
        for i in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: bounds)
        }
        UIGraphicsEndPDFContext()

        let safeName = fileName.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
