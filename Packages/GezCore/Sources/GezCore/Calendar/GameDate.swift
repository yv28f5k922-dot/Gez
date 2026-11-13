/// An in-game calendar date.
///
/// Like Paradox games, the calendar has a fixed 365 days per year with no
/// leap years, so every year ticks the same number of days and dates are
/// trivially comparable.
public struct GameDate: Hashable, Comparable, CustomStringConvertible, Sendable {
    public static let daysInMonth = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    public static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]
    private static let daysBeforeMonth: [Int] = {
        var result: [Int] = []
        var total = 0
        for days in daysInMonth {
            result.append(total)
            total += days
        }
        return result
    }()

    public private(set) var year: Int
    /// 1...12
    public private(set) var month: Int
    /// 1...daysInMonth[month - 1]
    public private(set) var day: Int

    public init(year: Int, month: Int, day: Int) {
        precondition((1...12).contains(month), "month out of range")
        precondition(day >= 1 && day <= GameDate.daysInMonth[month - 1], "day out of range")
        self.year = year
        self.month = month
        self.day = day
    }

    public var isFirstOfMonth: Bool { day == 1 }
    public var isFirstOfYear: Bool { day == 1 && month == 1 }

    /// Days since 1 January of year 0. Useful for durations and ordering.
    public var ordinal: Int {
        year * 365 + GameDate.daysBeforeMonth[month - 1] + (day - 1)
    }

    public mutating func advanceOneDay() {
        day += 1
        if day > GameDate.daysInMonth[month - 1] {
            day = 1
            month += 1
            if month > 12 {
                month = 1
                year += 1
            }
        }
    }

    public func adding(days: Int) -> GameDate {
        precondition(days >= 0)
        var date = self
        for _ in 0..<days { date.advanceOneDay() }
        return date
    }

    public static func < (lhs: GameDate, rhs: GameDate) -> Bool {
        lhs.ordinal < rhs.ordinal
    }

    public var description: String {
        "\(day) \(GameDate.monthNames[month - 1]) \(year)"
    }
}
