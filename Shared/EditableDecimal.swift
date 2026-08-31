import Foundation
import SwiftUI

enum EditableDecimal {
    static let maximumFractionDigits = 2

    static func string(from value: Double) -> String {
        guard value.isFinite else {
            return ""
        }

        return NutritionFormatting.editable(value)
    }

    static func value(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isValidInput(trimmed) else {
            return nil
        }

        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        let numberText = normalized.hasSuffix(".") ? String(normalized.dropLast()) : normalized
        guard !numberText.isEmpty,
              let value = Double(numberText),
              value.isFinite
        else {
            return nil
        }

        return value
    }

    static func binding(_ text: Binding<String>) -> Binding<String> {
        Binding(
            get: { text.wrappedValue },
            set: { candidate in
                guard isValidInput(candidate) else {
                    return
                }
                text.wrappedValue = candidate
            },
        )
    }

    static func isValidInput(_ text: String) -> Bool {
        var separatorSeen = false
        var fractionalDigits = 0

        for character in text {
            if isASCIIDigit(character) {
                if separatorSeen {
                    fractionalDigits += 1
                    guard fractionalDigits <= maximumFractionDigits else {
                        return false
                    }
                }
            } else if character == "." || character == "," {
                guard !separatorSeen else {
                    return false
                }
                separatorSeen = true
            } else {
                return false
            }
        }

        return true
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first else {
            return false
        }
        return (48 ... 57).contains(scalar.value)
    }
}
