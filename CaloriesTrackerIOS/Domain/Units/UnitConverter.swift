import Foundation

enum UnitConverterError: Error, LocalizedError {
    case invalidAmount
    case incompatibleServingUnit

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            "Количество должно быть конечным неотрицательным числом."
        case .incompatibleServingUnit:
            "Дополнительная единица несовместима с базовой единицей продукта."
        }
    }
}

enum UnitConverter {
    /// Converts an amount in a historical serving unit to the base-unit amount of its ProductVersion.
    static func baseAmount(
        from amount: Double,
        servingUnit: ServingUnit,
        expectedBaseUnit: ProductBaseUnit,
    ) throws -> Double {
        guard amount.isFinite, amount >= 0,
              servingUnit.conversionAmount.isFinite, servingUnit.conversionAmount > 0
        else {
            throw UnitConverterError.invalidAmount
        }

        guard servingUnit.conversionUnit.rawValue == expectedBaseUnit.rawValue else {
            throw UnitConverterError.incompatibleServingUnit
        }

        return amount * servingUnit.conversionAmount
    }
}
