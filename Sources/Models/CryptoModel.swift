import Foundation

/// Supported cryptocurrency exchanges
public enum CryptoExchange: String, CaseIterable, Identifiable, Codable {
    case binance = "Binance"
    case coinbase = "Coinbase"
    case kraken = "Kraken"

    public var id: String { rawValue }
    public var displayName: String { rawValue }

    public var defaultQuoteAsset: String {
        switch self {
        case .binance: return "USDT"
        case .coinbase: return "USD"
        case .kraken: return "USD"
        }
    }

    public var iconSymbol: String {
        switch self {
        case .binance: return "b.circle.fill"
        case .coinbase: return "c.circle.fill"
        case .kraken: return "k.circle.fill"
        }
    }

    /// Formats the trading pair string for the exchange API
    public func formatSymbol(base: String, quote: String) -> String {
        let b = base.uppercased()
        let q = quote.uppercased()
        switch self {
        case .binance:
            return "\(b)\(q)"
        case .coinbase:
            return "\(b)-\(q)"
        case .kraken:
            return "\(b)/\(q)"
        }
    }
}

/// Represents a cryptocurrency trading pair.
public struct CryptoSymbol: Identifiable, Hashable, Codable {
    public var id: String { symbol }
    public let symbol: String
    public let baseAsset: String
    public let quoteAsset: String
    public let name: String
    public let iconSymbol: String

    public init(symbol: String, baseAsset: String, quoteAsset: String = "USDT", name: String, iconSymbol: String) {
        self.symbol = symbol.uppercased()
        self.baseAsset = baseAsset.uppercased()
        self.quoteAsset = quoteAsset.uppercased()
        self.name = name
        self.iconSymbol = iconSymbol
    }

    /// Returns the symbol formatted specifically for the given exchange API
    public func formattedSymbol(for exchange: CryptoExchange) -> String {
        let effectiveQuote = self.effectiveQuote(for: exchange)
        return exchange.formatSymbol(base: baseAsset, quote: effectiveQuote)
    }

    /// Returns the effective quote asset for the given exchange (e.g. USDT for Binance, USD for Coinbase/Kraken)
    public func effectiveQuote(for exchange: CryptoExchange) -> String {
        if exchange == .binance {
            return (quoteAsset == "USD") ? "USDT" : quoteAsset
        } else {
            return (quoteAsset == "USDT") ? "USD" : quoteAsset
        }
    }

    /// Common presets available out-of-the-box (Top 9 non-stablecoin cryptocurrencies)
    public static let presets: [CryptoSymbol] = [
        CryptoSymbol(symbol: "BTCUSDT", baseAsset: "BTC", name: "Bitcoin", iconSymbol: "bitcoinsign.circle.fill"),
        CryptoSymbol(symbol: "ETHUSDT", baseAsset: "ETH", name: "Ethereum", iconSymbol: "e.circle.fill"),
        CryptoSymbol(symbol: "BNBUSDT", baseAsset: "BNB", name: "BNB", iconSymbol: "b.circle.fill"),
        CryptoSymbol(symbol: "XRPUSDT", baseAsset: "XRP", name: "Ripple", iconSymbol: "x.circle.fill"),
        CryptoSymbol(symbol: "SOLUSDT", baseAsset: "SOL", name: "Solana", iconSymbol: "s.circle.fill"),
        CryptoSymbol(symbol: "TRXUSDT", baseAsset: "TRX", name: "TRON", iconSymbol: "t.circle.fill"),
        CryptoSymbol(symbol: "DOGEUSDT", baseAsset: "DOGE", name: "Dogecoin", iconSymbol: "d.circle.fill"),
        CryptoSymbol(symbol: "ADAUSDT", baseAsset: "ADA", name: "Cardano", iconSymbol: "a.circle.fill"),
        CryptoSymbol(symbol: "LINKUSDT", baseAsset: "LINK", name: "Chainlink", iconSymbol: "link.circle.fill")
    ]

    /// Creates a symbol from user text (e.g. "BTC", "BTC/USDT", "BTC-USD", or "$SOL")
    public static func from(rawInput: String, defaultExchange: CryptoExchange = .binance) -> CryptoSymbol {
        var trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        // Strip leading currency prefixes like $ or #
        if trimmed.hasPrefix("$") || trimmed.hasPrefix("#") {
            trimmed.removeFirst()
        }

        // Filter valid alphanumeric characters
        let alphanumericOnly = trimmed.filter { $0.isLetter || $0.isNumber }
        guard !alphanumericOnly.isEmpty else {
            return CryptoSymbol(
                symbol: "INVALID\(defaultExchange.defaultQuoteAsset)",
                baseAsset: "INVALID",
                quoteAsset: defaultExchange.defaultQuoteAsset,
                name: "Unknown",
                iconSymbol: "questionmark.circle"
            )
        }

        let defaultQuote = defaultExchange.defaultQuoteAsset
        let base: String
        let quote: String
        let symbol: String

        // Check if user separated base and quote with slash, dash, or underscore (e.g. "BTC/USDT", "BTC-USD")
        let separators = CharacterSet(charactersIn: "/-_")
        let parts = trimmed.components(separatedBy: separators).filter { !$0.isEmpty }

        if parts.count >= 2 {
            let basePart = parts[0].filter { $0.isLetter || $0.isNumber }
            let quotePart = parts[1].filter { $0.isLetter || $0.isNumber }
            if !basePart.isEmpty && !quotePart.isEmpty {
                base = basePart
                quote = quotePart
                symbol = basePart + quotePart
            } else {
                base = alphanumericOnly
                quote = defaultQuote
                symbol = alphanumericOnly.hasSuffix(quote) && alphanumericOnly.count > quote.count ? alphanumericOnly : alphanumericOnly + quote
            }
        } else {
            if alphanumericOnly.hasSuffix("USDT") && alphanumericOnly.count > 4 {
                quote = "USDT"
                base = String(alphanumericOnly.dropLast(4))
                symbol = alphanumericOnly
            } else if alphanumericOnly.hasSuffix("USD") && alphanumericOnly.count > 3 {
                quote = "USD"
                base = String(alphanumericOnly.dropLast(3))
                symbol = alphanumericOnly
            } else {
                base = alphanumericOnly
                quote = defaultQuote
                symbol = alphanumericOnly + defaultQuote
            }
        }

        if let existing = presets.first(where: { $0.baseAsset == base }) {
            return existing
        }

        return CryptoSymbol(
            symbol: symbol,
            baseAsset: base,
            quoteAsset: quote,
            name: base,
            iconSymbol: "circle.fill"
        )
    }
}

/// Price change direction indicator
public enum PriceDirection: Equatable {
    case up
    case down
    case neutral
}

/// Real-time ticker data received from Binance
public struct TickerData: Equatable {
    public let symbol: String
    public let price: Double
    public let priceDecimals: Int
    public let priceChange: Double
    public let priceChangePercent: Double
    public let high24h: Double
    public let low24h: Double
    public var vwap: Double
    public let volume: Double
    public let quoteVolume: Double
    public var volume5m: Double
    public var quoteVolume5m: Double
    public var takerBuyRatio5m: Double
    public var volume15m: Double
    public var quoteVolume15m: Double
    public var takerBuyRatio15m: Double
    public var trades24h: Int
    public var trades5m: Int
    public var bidPrice: Double
    public var askPrice: Double
    public var change1h: Double
    public var change4h: Double
    public var bidDepth20: Double
    public var askDepth20: Double
    public var bookImbalance: Double
    public let lastUpdated: Date
    public var direction: PriceDirection = .neutral

    public static func standardDecimalPlaces(for price: Double) -> Int {
        if price >= 10.0 {
            return 2
        } else if price >= 1.0 {
            return 4
        } else if price >= 0.01 {
            return 4
        } else if price >= 0.0001 {
            return 6
        } else {
            return 8
        }
    }

    public init(
        symbol: String,
        price: Double,
        priceDecimals: Int? = nil,
        priceChange: Double = 0.0,
        priceChangePercent: Double = 0.0,
        high24h: Double = 0.0,
        low24h: Double = 0.0,
        vwap: Double = 0.0,
        volume: Double = 0.0,
        quoteVolume: Double = 0.0,
        volume5m: Double = 0.0,
        quoteVolume5m: Double = 0.0,
        takerBuyRatio5m: Double = 50.0,
        volume15m: Double = 0.0,
        quoteVolume15m: Double = 0.0,
        takerBuyRatio15m: Double = 50.0,
        trades24h: Int = 0,
        trades5m: Int = 0,
        bidPrice: Double = 0.0,
        askPrice: Double = 0.0,
        change1h: Double = 0.0,
        change4h: Double = 0.0,
        bidDepth20: Double = 0.0,
        askDepth20: Double = 0.0,
        bookImbalance: Double = 50.0,
        lastUpdated: Date = Date(),
        direction: PriceDirection = .neutral
    ) {
        self.symbol = symbol
        self.price = price
        self.priceDecimals = priceDecimals ?? TickerData.standardDecimalPlaces(for: price)
        self.priceChange = priceChange
        self.priceChangePercent = priceChangePercent
        self.high24h = high24h
        self.low24h = low24h
        self.vwap = vwap
        self.volume = volume
        self.quoteVolume = quoteVolume
        self.volume5m = volume5m
        self.quoteVolume5m = quoteVolume5m
        self.takerBuyRatio5m = takerBuyRatio5m
        self.volume15m = volume15m
        self.quoteVolume15m = quoteVolume15m
        self.takerBuyRatio15m = takerBuyRatio15m
        self.trades24h = trades24h
        self.trades5m = trades5m
        self.bidPrice = bidPrice
        self.askPrice = askPrice
        self.change1h = change1h
        self.change4h = change4h
        self.bidDepth20 = bidDepth20
        self.askDepth20 = askDepth20
        self.bookImbalance = bookImbalance
        self.lastUpdated = lastUpdated
        self.direction = direction
    }

    /// Formats price intelligently depending on magnitude
    public var formattedPrice: String {
        formatPriceValue(price)
    }

    public var formattedChangePercent: String {
        let prefix = priceChangePercent >= 0 ? "+" : ""
        return String(format: "%@%.2f%%", prefix, priceChangePercent)
    }

    public var formattedHigh: String {
        formatPriceValue(high24h)
    }

    public var formattedLow: String {
        formatPriceValue(low24h)
    }

    public var formattedVWAP: String {
        formatPriceValue(vwap)
    }

    public var formattedTakerBuyRatio5m: String {
        guard quoteVolume5m > 0 else { return "--" }
        return String(format: "%.0f%%", takerBuyRatio5m)
    }

    public var formattedQuoteVolume: String {
        formatVolumeValue(quoteVolume)
    }

    public var formattedQuoteVolume5m: String {
        formatVolumeValue(quoteVolume5m)
    }

    public var formattedQuoteVolume15m: String {
        formatVolumeValue(quoteVolume15m)
    }

    private func formatVolumeValue(_ value: Double) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.3fB", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%.3fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.3fK", value / 1_000)
        } else if value > 0 {
            return String(format: "%.3f", value)
        } else {
            return "--"
        }
    }

    private func formatPriceValue(_ value: Double) -> String {
        guard value > 0 else { return "$0.00" }
        return PriceFormatterCache.shared.format(value)
    }

    public var formattedBaseVolume: String {
        formatVolumeValue(volume)
    }

    public var formattedPriceChange: String {
        let prefix = priceChange >= 0 ? "+" : "-"
        return prefix + formatPriceValue(abs(priceChange))
    }

    public var formattedOpenPrice: String {
        let open = max(0, price - priceChange)
        return formatPriceValue(open)
    }

    public var spread: Double {
        guard askPrice > 0, bidPrice > 0, askPrice >= bidPrice else { return 0.0 }
        return askPrice - bidPrice
    }

    public var formattedSpread: String {
        guard spread > 0 else { return "--" }
        return formatPriceValue(spread)
    }

    public var formattedBid: String {
        guard bidPrice > 0 else { return "--" }
        return formatPriceValue(bidPrice)
    }

    public var formattedAsk: String {
        guard askPrice > 0 else { return "--" }
        return formatPriceValue(askPrice)
    }

    public var formattedTrades24h: String {
        guard trades24h > 0 else { return "--" }
        return formatCountValue(trades24h)
    }

    public var formattedTrades5m: String {
        guard trades5m > 0 else { return "--" }
        return formatCountValue(trades5m)
    }

    public var formattedTakerBuyRatio15m: String {
        guard quoteVolume15m > 0 else { return "--" }
        return String(format: "%.0f%%", takerBuyRatio15m)
    }

    public var formattedAvgTradeSize: String {
        guard trades24h > 0, quoteVolume > 0 else { return "--" }
        let avg = quoteVolume / Double(trades24h)
        return formatVolumeValue(avg)
    }

    public var formattedChange1h: String {
        let prefix = change1h >= 0 ? "+" : ""
        return String(format: "%@%.2f%%", prefix, change1h)
    }

    public var formattedChange4h: String {
        let prefix = change4h >= 0 ? "+" : ""
        return String(format: "%@%.2f%%", prefix, change4h)
    }

    public var formattedBidDepth20: String {
        guard bidDepth20 > 0 else { return "--" }
        return formatVolumeValue(bidDepth20)
    }

    public var formattedAskDepth20: String {
        guard askDepth20 > 0 else { return "--" }
        return formatVolumeValue(askDepth20)
    }

    public var formattedBookImbalance: String {
        guard bidDepth20 > 0 || askDepth20 > 0 else { return "--" }
        return String(format: "%.0f%% Bids", bookImbalance)
    }

    private func formatCountValue(_ count: Int) -> String {
        let val = Double(count)
        if val >= 1_000_000 {
            return String(format: "%.2fM", val / 1_000_000)
        } else if val >= 1_000 {
            return String(format: "%.1fK", val / 1_000)
        } else {
            return "\(count)"
        }
    }
}

/// Categories for grouping metrics in the popover customization view
public enum MetricCategory: String, CaseIterable, Identifiable, Codable {
    case all = "All"
    case price = "Price"
    case volume = "Volume"
    case depth = "Depth"
    case flow = "Flow"

    public var id: String { rawValue }
    public var title: String { rawValue }
}

/// Configurable statistic metrics for the 6-slot expanded Dynamic Island grid
public enum StatMetric: String, CaseIterable, Identifiable, Codable {
    // Price
    case high24h = "24h_high"
    case low24h = "24h_low"
    case openPrice = "open_price"
    case priceChange = "24h_change"
    case change1h = "1h_change"
    case change4h = "4h_change"
    case vwap = "vwap"

    // Volume
    case quoteVolume24h = "24h_vol_usdt"
    case baseVolume24h = "24h_vol_base"
    case quoteVolume15m = "15m_vol"
    case quoteVolume5m = "5m_vol"
    case trades24h = "24h_trades"
    case trades5m = "5m_trades"
    case avgTradeSize = "avg_trade"

    // Depth
    case bookImbalance = "book_imbalance"
    case bidDepth20 = "bid_depth_20"
    case askDepth20 = "ask_depth_20"
    case spread = "spread"
    case bestBid = "best_bid"
    case bestAsk = "best_ask"

    // Flow
    case takerBuyRatio5m = "5m_buy_ratio"
    case takerBuyRatio15m = "15m_buy_ratio"

    public var id: String { rawValue }

    public var category: MetricCategory {
        switch self {
        case .high24h, .low24h, .openPrice, .priceChange, .change1h, .change4h, .vwap:
            return .price
        case .quoteVolume24h, .baseVolume24h, .quoteVolume15m, .quoteVolume5m, .trades24h, .trades5m, .avgTradeSize:
            return .volume
        case .bookImbalance, .bidDepth20, .askDepth20, .spread, .bestBid, .bestAsk:
            return .depth
        case .takerBuyRatio5m, .takerBuyRatio15m:
            return .flow
        }
    }

    public var title: String {
        switch self {
        case .high24h: return "24h High"
        case .low24h: return "24h Low"
        case .vwap: return "VWAP"
        case .quoteVolume24h: return "24h Vol $"
        case .baseVolume24h: return "24h Vol"
        case .priceChange: return "24h Net $"
        case .openPrice: return "Open"
        case .change1h: return "1h Change"
        case .change4h: return "4h Change"
        case .quoteVolume15m: return "15m Vol"
        case .quoteVolume5m: return "5m Vol"
        case .trades24h: return "24h Trades"
        case .trades5m: return "5m Trades"
        case .avgTradeSize: return "Avg Trade $"
        case .bookImbalance: return "Imbalance"
        case .bidDepth20: return "Bids $"
        case .askDepth20: return "Asks $"
        case .spread: return "Spread"
        case .bestBid: return "Best Bid"
        case .bestAsk: return "Best Ask"
        case .takerBuyRatio5m: return "5m Buy %"
        case .takerBuyRatio15m: return "15m Buy %"
        }
    }

    public var shortDescription: String {
        switch self {
        case .high24h: return "Highest price in last 24h"
        case .low24h: return "Lowest price in last 24h"
        case .vwap: return "Volume-Weighted Average Price"
        case .quoteVolume24h: return "24h trading volume in USDT"
        case .baseVolume24h: return "24h volume in base asset tokens"
        case .priceChange: return "Net dollar change in last 24h"
        case .openPrice: return "Opening price 24 hours ago"
        case .change1h: return "1-hour rolling price change"
        case .change4h: return "4-hour rolling price change"
        case .quoteVolume15m: return "15-minute trading turnover"
        case .quoteVolume5m: return "5-minute trading turnover"
        case .trades24h: return "Total trade transactions in 24h"
        case .trades5m: return "Trade transaction count in 5m"
        case .avgTradeSize: return "Average trade size across 24h"
        case .bookImbalance: return "Top 20 bids vs asks depth ratio"
        case .bidDepth20: return "Total USDT queued on top 20 bids"
        case .askDepth20: return "Total USDT queued on top 20 asks"
        case .spread: return "Bid-Ask spread difference"
        case .bestBid: return "Top buying bid price in order book"
        case .bestAsk: return "Top selling ask price in order book"
        case .takerBuyRatio5m: return "Buyer aggression ratio (5m)"
        case .takerBuyRatio15m: return "Buyer aggression ratio (15m)"
        }
    }

    /// Returns true if this metric is available on the specified exchange
    public func isAvailable(on exchange: CryptoExchange) -> Bool {
        switch exchange {
        case .binance:
            return true
        case .coinbase:
            switch self {
            case .high24h, .low24h, .openPrice, .priceChange, .vwap,
                 .change1h, .change4h,
                 .quoteVolume24h, .baseVolume24h, .quoteVolume15m, .quoteVolume5m,
                 .bestBid, .bestAsk, .spread,
                 .bookImbalance, .bidDepth20, .askDepth20:
                return true
            case .trades24h, .trades5m, .avgTradeSize,
                 .takerBuyRatio5m, .takerBuyRatio15m:
                return false
            }
        case .kraken:
            switch self {
            case .high24h, .low24h, .openPrice, .priceChange, .vwap,
                 .change1h, .change4h,
                 .quoteVolume24h, .baseVolume24h, .quoteVolume15m, .quoteVolume5m,
                 .trades24h, .trades5m, .avgTradeSize,
                 .bestBid, .bestAsk, .spread,
                 .bookImbalance, .bidDepth20, .askDepth20:
                return true
            case .takerBuyRatio5m, .takerBuyRatio15m:
                return false
            }
        }
    }

    public static func availableMetrics(for exchange: CryptoExchange) -> [StatMetric] {
        allCases.filter { $0.isAvailable(on: exchange) }
    }

    public static var defaultSlots: [StatMetric] {
        defaultSlots(for: .binance)
    }

    public static func defaultSlots(for exchange: CryptoExchange) -> [StatMetric] {
        switch exchange {
        case .binance:
            return [
                .high24h, .quoteVolume15m, .vwap,
                .low24h, .quoteVolume5m, .takerBuyRatio5m
            ]
        case .coinbase:
            return [
                .high24h, .quoteVolume15m, .vwap,
                .low24h, .quoteVolume5m, .bookImbalance
            ]
        case .kraken:
            return [
                .high24h, .quoteVolume15m, .vwap,
                .low24h, .quoteVolume5m, .bookImbalance
            ]
        }
    }
}

// MARK: - Price Formatter Cache
final class PriceFormatterCache: @unchecked Sendable {
    static let shared = PriceFormatterCache()
    private let lock = NSLock()

    private let largeFormatter: NumberFormatter
    private let mediumFormatter: NumberFormatter
    private let smallFormatter: NumberFormatter
    private let microFormatter: NumberFormatter
    private var customFormatters: [Int: NumberFormatter] = [:]

    private init() {
        func makeFormatter(minFrac: Int, maxFrac: Int) -> NumberFormatter {
            let f = NumberFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.numberStyle = .decimal
            f.usesGroupingSeparator = true
            f.minimumFractionDigits = minFrac
            f.maximumFractionDigits = maxFrac
            return f
        }
        self.largeFormatter = makeFormatter(minFrac: 2, maxFrac: 2)
        self.mediumFormatter = makeFormatter(minFrac: 2, maxFrac: 4)
        self.smallFormatter = makeFormatter(minFrac: 2, maxFrac: 4)
        self.microFormatter = makeFormatter(minFrac: 2, maxFrac: 8)
    }

    func format(_ value: Double, decimals: Int? = nil) -> String {
        lock.lock()
        defer { lock.unlock() }

        if let dec = decimals {
            let formatter: NumberFormatter
            if let cached = customFormatters[dec] {
                formatter = cached
            } else {
                let f = NumberFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.numberStyle = .decimal
                f.usesGroupingSeparator = true
                f.minimumFractionDigits = dec
                f.maximumFractionDigits = dec
                customFormatters[dec] = f
                formatter = f
            }
            if let str = formatter.string(from: NSNumber(value: value)) {
                return "$" + str
            }
            return String(format: "$%.*f", dec, value)
        }

        let formatter: NumberFormatter
        if value >= 1000 {
            formatter = largeFormatter
        } else if value >= 1 {
            formatter = mediumFormatter
        } else if value >= 0.01 {
            formatter = smallFormatter
        } else {
            formatter = microFormatter
        }

        if let str = formatter.string(from: NSNumber(value: value)) {
            return "$" + str
        } else {
            return String(format: "$%.8f", value)
        }
    }
}
