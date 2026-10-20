import Foundation

/// The paywall's arithmetic on App Store prices. It never holds a price of its own: every amount
/// shown comes from StoreKit, so it stays right in every storefront and after a price change.
nonisolated enum ProPriceReadout {
    /// How much cheaper `paid` is than `full`, in whole percent rounded down — so the paywall
    /// never promises more than the App Store charges. Nil when it is not cheaper.
    static func percentOff(full: Decimal, paid: Decimal) -> Int? {
        guard full > 0, paid < full else { return nil }
        let percent = NSDecimalNumber(decimal: (1 - paid / full) * 100).doubleValue
        let whole = Int(percent.rounded(.down))
        return whole > 0 ? whole : nil
    }

    /// What the yearly plan saves over twelve monthly payments (12,99 € × 12 against 99,99 € → 35).
    static func yearlySaving(monthly: Decimal, yearly: Decimal) -> Int? {
        percentOff(full: monthly * 12, paid: yearly)
    }
}
