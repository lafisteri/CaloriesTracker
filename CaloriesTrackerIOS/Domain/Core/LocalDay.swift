import Foundation

struct LocalDay: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    enum ValidationError: Error, LocalizedError {
        case invalidComponents(year: Int, month: Int, day: Int)

        var errorDescription: String? {
            "Дата должна быть корректной датой григорианского календаря."
        }
    }

    enum Weekday: String, CaseIterable, Codable, Sendable {
        case monday
        case tuesday
        case wednesday
        case thursday
        case friday
        case saturday
        case sunday
    }

    let rawValue: String

    init(year: Int, month: Int, day: Int) throws {
        guard Self.isValid(year: year, month: month, day: day) else {
            throw ValidationError.invalidComponents(year: year, month: month, day: day)
        }

        rawValue = String(format: "%04d-%02d-%02d", year, month, day)
    }

    init?(rawValue: String) {
        let components = rawValue.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0].count == 4,
              components[1].count == 2,
              components[2].count == 2,
              components.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2]),
              Self.isValid(year: year, month: month, day: day)
        else {
            return nil
        }

        self.rawValue = rawValue
    }

    static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func current(in timeZone: TimeZone = .current) -> LocalDay {
        let calendar = gregorianCalendar(in: timeZone)
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        return LocalDay(
            uncheckedYear: components.year ?? 1970,
            month: components.month ?? 1,
            day: components.day ?? 1,
        )
    }

    func nextDay(in timeZone: TimeZone = .current) -> LocalDay {
        adding(days: 1, in: timeZone)
    }

    func previousDay(in timeZone: TimeZone = .current) -> LocalDay {
        adding(days: -1, in: timeZone)
    }

    func weekday(in timeZone: TimeZone = .current) -> Weekday {
        let calendar = Self.gregorianCalendar(in: timeZone)
        switch calendar.component(.weekday, from: presentationDate(in: timeZone)) {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        default: return .saturday
        }
    }

    /// A presentation-only Date at local noon. Never persist this value as a diary day.
    func presentationDate(in timeZone: TimeZone = .current) -> Date {
        let calendar = Self.gregorianCalendar(in: timeZone)
        let parts = rawValue.split(separator: "-").compactMap { Int($0) }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = timeZone
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        return calendar.date(from: components) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    private init(uncheckedYear year: Int, month: Int, day: Int) {
        rawValue = String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func adding(days: Int, in timeZone: TimeZone) -> LocalDay {
        let calendar = Self.gregorianCalendar(in: timeZone)
        let shiftedDate = calendar.date(byAdding: .day, value: days, to: presentationDate(in: timeZone))
            ?? presentationDate(in: timeZone)
        let components = calendar.dateComponents([.year, .month, .day], from: shiftedDate)
        return LocalDay(
            uncheckedYear: components.year ?? 1970,
            month: components.month ?? 1,
            day: components.day ?? 1,
        )
    }

    private static func isValid(year: Int, month: Int, day: Int) -> Bool {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else {
            return false
        }

        let calendar = gregorianCalendar(in: .gmt)
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = .gmt
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12

        guard let date = calendar.date(from: components) else {
            return false
        }

        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        return resolved.year == year && resolved.month == month && resolved.day == day
    }

    private static func gregorianCalendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }
}
