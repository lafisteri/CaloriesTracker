import Foundation

/// Presentation-only numeric formatting for nutrition and food amounts.
///
/// Values passed here remain untouched; rounding is applied only to the
/// rendered string using the user's current locale.
enum NutritionFormatting {
    static func calories(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        number(value, maximumFractionDigits: 0, locale: locale)
    }

    static func macro(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        number(value, maximumFractionDigits: 1, locale: locale)
    }

    static func amount(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        number(value, maximumFractionDigits: 1, locale: locale)
    }

    static func preciseNutrition(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        number(value, maximumFractionDigits: 2, locale: locale)
    }

    static func preciseAmount(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        number(value, maximumFractionDigits: 2, locale: locale)
    }

    static func percentage(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        number(value, maximumFractionDigits: 2, locale: locale)
    }

    static func editable(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        preciseAmount(value, locale: locale)
    }

    private static func number(
        _ value: Double,
        maximumFractionDigits: Int,
        locale: Locale,
    ) -> String {
        guard value.isFinite else {
            return "—"
        }

        return value.formatted(
            .number
                .locale(locale)
                .grouping(.never)
                .precision(.fractionLength(0 ... maximumFractionDigits)),
        )
    }
}
