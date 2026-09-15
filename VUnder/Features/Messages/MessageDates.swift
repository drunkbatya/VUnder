import Foundation

enum MessageDates {
    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    private static let full: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func short(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return time.string(from: date)
        }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            return day.string(from: date)
        }
        return full.string(from: date)
    }

    static func timeOnly(_ date: Date) -> String {
        time.string(from: date)
    }

    static func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        return full.string(from: date)
    }
}
