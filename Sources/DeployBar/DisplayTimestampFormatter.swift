import Foundation

enum DisplayTimestampFormatter {
    static func string(
        from date: Date,
        now: Date = Date(),
        calendar baseCalendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        var calendar = baseCalendar
        calendar.locale = locale

        if calendar.isDate(date, inSameDayAs: now) {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }

        let isSameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(isSameYear ? "Mdjmm" : "yMdjmm")
        return formatter.string(from: date)
    }
}
