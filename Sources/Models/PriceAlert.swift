import Foundation

/// Direction of price threshold trigger.
public enum AlertDirection: String, Codable, CaseIterable {
    case above = "above"
    case below = "below"

    public var symbol: String {
        switch self {
        case .above: return "▲"
        case .below: return "▼"
        }
    }

    public var title: String {
        switch self {
        case .above: return "Above"
        case .below: return "Below"
        }
    }
}

/// A lightweight local price alert threshold for cryptocurrency pairs.
public struct PriceAlert: Identifiable, Codable, Equatable {
    public let id: UUID
    public let symbol: String
    public let exchange: CryptoExchange
    public let targetPrice: Double
    public let direction: AlertDirection
    public var isTriggered: Bool
    public let createdAt: Date
    public var triggeredAt: Date?

    public init(
        id: UUID = UUID(),
        symbol: String,
        exchange: CryptoExchange = .binance,
        targetPrice: Double,
        direction: AlertDirection,
        isTriggered: Bool = false,
        createdAt: Date = Date(),
        triggeredAt: Date? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.exchange = exchange
        self.targetPrice = targetPrice
        self.direction = direction
        self.isTriggered = isTriggered
        self.createdAt = createdAt
        self.triggeredAt = triggeredAt
    }

    public var formattedTargetPrice: String {
        guard targetPrice > 0 else { return "$0.00" }
        return PriceFormatterCache.shared.format(targetPrice)
    }
}
