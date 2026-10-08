import Foundation

/// Pure functional parser for Binance REST and WebSocket JSON payloads.
public enum BinanceDataParser {

    public static func decimalPlaces(from priceString: String?, knownDecimals: Int? = nil) -> Int? {
        if let known = knownDecimals {
            return known
        }
        guard let priceString = priceString, let price = Double(priceString) else {
            return nil
        }
        var trimmed = priceString
        while trimmed.hasSuffix("0") && trimmed.contains(".") {
            trimmed.removeLast()
        }
        if trimmed.hasSuffix(".") {
            trimmed.removeLast()
        }
        let trimmedDecimals: Int
        if let dot = trimmed.firstIndex(of: ".") {
            trimmedDecimals = trimmed.distance(from: dot, to: trimmed.endIndex) - 1
        } else {
            trimmedDecimals = 0
        }
        return max(TickerData.standardDecimalPlaces(for: price), trimmedDecimals)
    }

    public static func parseRestTicker(
        _ json: [String: Any],
        symbol: CryptoSymbol,
        existing: TickerData?,
        knownDecimals: Int? = nil
    ) -> TickerData? {
        guard let lastPriceStr = json["lastPrice"] as? String,
              let lastPrice = Double(lastPriceStr) else { return nil }

        let priceChange = Double(json["priceChange"] as? String ?? "0") ?? 0
        let priceChangePercent = Double(json["priceChangePercent"] as? String ?? "0") ?? 0
        let high = Double(json["highPrice"] as? String ?? "0") ?? 0
        let low = Double(json["lowPrice"] as? String ?? "0") ?? 0
        let vwap = Double(json["weightedAvgPrice"] as? String ?? "0") ?? 0
        let volume = Double(json["volume"] as? String ?? "0") ?? 0
        let quoteVolume = Double(json["quoteVolume"] as? String ?? "0") ?? 0
        let trades24h = json["count"] as? Int ?? 0
        let bidPrice = Double(json["bidPrice"] as? String ?? "0") ?? 0
        let askPrice = Double(json["askPrice"] as? String ?? "0") ?? 0

        let currentChange1h = existing?.change1h ?? 0
        let currentChange4h = existing?.change4h ?? 0
        let currentBidDepth20 = existing?.bidDepth20 ?? 0
        let currentAskDepth20 = existing?.askDepth20 ?? 0
        let currentBookImbalance = existing?.bookImbalance ?? 50.0

        return TickerData(
            symbol: symbol.symbol,
            price: lastPrice,
            priceDecimals: knownDecimals ?? existing?.priceDecimals ?? decimalPlaces(from: lastPriceStr),
            priceChange: priceChange,
            priceChangePercent: priceChangePercent,
            high24h: high,
            low24h: low,
            vwap: vwap,
            volume: volume,
            quoteVolume: quoteVolume,
            trades24h: trades24h,
            bidPrice: bidPrice,
            askPrice: askPrice,
            change1h: currentChange1h,
            change4h: currentChange4h,
            bidDepth20: currentBidDepth20,
            askDepth20: currentAskDepth20,
            bookImbalance: currentBookImbalance,
            lastUpdated: Date(),
            direction: .neutral
        )
    }

    public static func parseWebSocketTicker(
        _ json: [String: Any],
        symbol: CryptoSymbol,
        existing: TickerData?,
        knownDecimals: Int? = nil
    ) -> (ticker: TickerData, direction: PriceDirection)? {
        guard let closePriceStr = json["c"] as? String,
              let closePrice = Double(closePriceStr) else { return nil }

        let priceChange = Double(json["p"] as? String ?? "0") ?? 0
        let priceChangePercent = Double(json["P"] as? String ?? "0") ?? 0
        let high = Double(json["h"] as? String ?? "0") ?? 0
        let low = Double(json["l"] as? String ?? "0") ?? 0
        let vwap = Double(json["w"] as? String ?? "0") ?? (existing?.vwap ?? 0)
        let volume = Double(json["v"] as? String ?? "0") ?? 0
        let quoteVolume = Double(json["q"] as? String ?? "0") ?? 0
        let trades24h = json["n"] as? Int ?? (existing?.trades24h ?? 0)
        let bidPrice = Double(json["b"] as? String ?? "0") ?? (existing?.bidPrice ?? 0)
        let askPrice = Double(json["a"] as? String ?? "0") ?? (existing?.askPrice ?? 0)

        var direction: PriceDirection = .neutral
        if let oldPrice = existing?.price {
            if closePrice > oldPrice {
                direction = .up
            } else if closePrice < oldPrice {
                direction = .down
            }
        }

        let current5m = existing?.volume5m ?? 0
        let currentQuote5m = existing?.quoteVolume5m ?? 0
        let currentTakerBuyRatio5m = existing?.takerBuyRatio5m ?? 50.0
        let currentTrades5m = existing?.trades5m ?? 0
        let current15m = existing?.volume15m ?? 0
        let currentQuote15m = existing?.quoteVolume15m ?? 0
        let currentTakerBuyRatio15m = existing?.takerBuyRatio15m ?? 50.0
        let currentChange1h = existing?.change1h ?? 0
        let currentChange4h = existing?.change4h ?? 0
        let currentBidDepth20 = existing?.bidDepth20 ?? 0
        let currentAskDepth20 = existing?.askDepth20 ?? 0
        let currentBookImbalance = existing?.bookImbalance ?? 50.0

        let ticker = TickerData(
            symbol: symbol.symbol,
            price: closePrice,
            priceDecimals: knownDecimals ?? existing?.priceDecimals ?? decimalPlaces(from: closePriceStr),
            priceChange: priceChange,
            priceChangePercent: priceChangePercent,
            high24h: high,
            low24h: low,
            vwap: vwap,
            volume: volume,
            quoteVolume: quoteVolume,
            volume5m: current5m,
            quoteVolume5m: currentQuote5m,
            takerBuyRatio5m: currentTakerBuyRatio5m,
            volume15m: current15m,
            quoteVolume15m: currentQuote15m,
            takerBuyRatio15m: currentTakerBuyRatio15m,
            trades24h: trades24h,
            trades5m: currentTrades5m,
            bidPrice: bidPrice,
            askPrice: askPrice,
            change1h: currentChange1h,
            change4h: currentChange4h,
            bidDepth20: currentBidDepth20,
            askDepth20: currentAskDepth20,
            bookImbalance: currentBookImbalance,
            lastUpdated: Date(),
            direction: direction
        )
        return (ticker, direction)
    }

    public static func applyKline(
        _ json: [String: Any],
        interval: String,
        to ticker: inout TickerData
    ) {
        guard let k = json["k"] as? [String: Any],
              let vStr = k["v"] as? String, let v = Double(vStr),
              let qStr = k["q"] as? String, let q = Double(qStr) else { return }

        let tbqStr = k["Q"] as? String
        let tbq = Double(tbqStr ?? "0") ?? 0
        let trades = k["n"] as? Int ?? 0

        if interval == "5m" {
            ticker.volume5m = v
            ticker.quoteVolume5m = q
            ticker.takerBuyRatio5m = q > 0 ? (tbq / q) * 100 : 50.0
            ticker.trades5m = trades
        } else if interval == "15m" {
            ticker.volume15m = v
            ticker.quoteVolume15m = q
            ticker.takerBuyRatio15m = q > 0 ? (tbq / q) * 100 : 50.0
        }
    }

    public static func applyDepth(
        _ json: [String: Any],
        to ticker: inout TickerData
    ) {
        guard let bids = json["bids"] as? [[Any]],
              let asks = json["asks"] as? [[Any]] else { return }

        var totalBidDepth: Double = 0
        for bid in bids.prefix(20) {
            guard bid.count >= 2 else { continue }
            let p = (bid[0] as? Double) ?? Double(bid[0] as? String ?? "") ?? 0
            let q = (bid[1] as? Double) ?? Double(bid[1] as? String ?? "") ?? 0
            totalBidDepth += (p * q)
        }

        var totalAskDepth: Double = 0
        for ask in asks.prefix(20) {
            guard ask.count >= 2 else { continue }
            let p = (ask[0] as? Double) ?? Double(ask[0] as? String ?? "") ?? 0
            let q = (ask[1] as? Double) ?? Double(ask[1] as? String ?? "") ?? 0
            totalAskDepth += (p * q)
        }

        ticker.bidDepth20 = totalBidDepth
        ticker.askDepth20 = totalAskDepth

        let combined = totalBidDepth + totalAskDepth
        if combined > 0 {
            ticker.bookImbalance = (totalBidDepth / combined) * 100.0
        }
    }

    // MARK: - Coinbase Parsing

    public static func parseCoinbaseRest(
        tickerJson: [String: Any],
        statsJson: [String: Any]?,
        symbol: CryptoSymbol,
        existing: TickerData?
    ) -> TickerData? {
        let priceStr = tickerJson["price"] as? String ?? statsJson?["last"] as? String
        guard let priceStr = priceStr, let lastPrice = Double(priceStr) else { return nil }

        let open = Double(statsJson?["open"] as? String ?? "") ?? (existing?.price ?? lastPrice)
        let high = Double(statsJson?["high"] as? String ?? "") ?? (existing?.high24h ?? lastPrice)
        let low = Double(statsJson?["low"] as? String ?? "") ?? (existing?.low24h ?? lastPrice)
        let volume = Double(statsJson?["volume"] as? String ?? tickerJson["volume"] as? String ?? "") ?? (existing?.volume ?? 0)
        let bidPrice = Double(tickerJson["bid"] as? String ?? "") ?? (existing?.bidPrice ?? 0)
        let askPrice = Double(tickerJson["ask"] as? String ?? "") ?? (existing?.askPrice ?? 0)

        let priceChange = lastPrice - open
        let priceChangePercent = open > 0 ? ((lastPrice - open) / open) * 100.0 : 0.0

        return TickerData(
            symbol: symbol.symbol,
            price: lastPrice,
            priceDecimals: decimalPlaces(from: priceStr),
            priceChange: priceChange,
            priceChangePercent: priceChangePercent,
            high24h: high,
            low24h: low,
            vwap: existing?.vwap ?? lastPrice,
            volume: volume,
            quoteVolume: volume * lastPrice,
            volume5m: existing?.volume5m ?? 0,
            quoteVolume5m: existing?.quoteVolume5m ?? 0,
            takerBuyRatio5m: existing?.takerBuyRatio5m ?? 50.0,
            volume15m: existing?.volume15m ?? 0,
            quoteVolume15m: existing?.quoteVolume15m ?? 0,
            takerBuyRatio15m: existing?.takerBuyRatio15m ?? 50.0,
            trades24h: existing?.trades24h ?? 0,
            trades5m: existing?.trades5m ?? 0,
            bidPrice: bidPrice,
            askPrice: askPrice,
            change1h: existing?.change1h ?? 0,
            change4h: existing?.change4h ?? 0,
            bidDepth20: existing?.bidDepth20 ?? 0,
            askDepth20: existing?.askDepth20 ?? 0,
            bookImbalance: existing?.bookImbalance ?? 50.0,
            lastUpdated: Date(),
            direction: .neutral
        )
    }

    public static func parseCoinbaseWebSocket(
        _ json: [String: Any],
        symbol: CryptoSymbol,
        existing: TickerData?
    ) -> (ticker: TickerData, direction: PriceDirection)? {
        guard let priceStr = json["price"] as? String,
              let price = Double(priceStr) else { return nil }

        let open = Double(json["open_24h"] as? String ?? "") ?? (existing?.price ?? price)
        let high = Double(json["high_24h"] as? String ?? "") ?? (existing?.high24h ?? price)
        let low = Double(json["low_24h"] as? String ?? "") ?? (existing?.low24h ?? price)
        let volume = Double(json["volume_24h"] as? String ?? "") ?? (existing?.volume ?? 0)
        let bidPrice = Double(json["best_bid"] as? String ?? "") ?? (existing?.bidPrice ?? 0)
        let askPrice = Double(json["best_ask"] as? String ?? "") ?? (existing?.askPrice ?? 0)

        let priceChange = price - open
        let priceChangePercent = open > 0 ? ((price - open) / open) * 100.0 : 0.0

        var direction: PriceDirection = .neutral
        if let oldPrice = existing?.price {
            if price > oldPrice {
                direction = .up
            } else if price < oldPrice {
                direction = .down
            }
        }

        let ticker = TickerData(
            symbol: symbol.symbol,
            price: price,
            priceDecimals: decimalPlaces(from: priceStr),
            priceChange: priceChange,
            priceChangePercent: priceChangePercent,
            high24h: high,
            low24h: low,
            vwap: existing?.vwap ?? price,
            volume: volume,
            quoteVolume: volume * price,
            volume5m: existing?.volume5m ?? 0,
            quoteVolume5m: existing?.quoteVolume5m ?? 0,
            takerBuyRatio5m: existing?.takerBuyRatio5m ?? 50.0,
            volume15m: existing?.volume15m ?? 0,
            quoteVolume15m: existing?.quoteVolume15m ?? 0,
            takerBuyRatio15m: existing?.takerBuyRatio15m ?? 50.0,
            trades24h: existing?.trades24h ?? 0,
            trades5m: existing?.trades5m ?? 0,
            bidPrice: bidPrice,
            askPrice: askPrice,
            change1h: existing?.change1h ?? 0,
            change4h: existing?.change4h ?? 0,
            bidDepth20: existing?.bidDepth20 ?? 0,
            askDepth20: existing?.askDepth20 ?? 0,
            bookImbalance: existing?.bookImbalance ?? 50.0,
            lastUpdated: Date(),
            direction: direction
        )

        return (ticker, direction)
    }

    // MARK: - Kraken Parsing

    public static func parseKrakenRest(
        _ json: [String: Any],
        symbol: CryptoSymbol,
        existing: TickerData?
    ) -> TickerData? {
        guard let result = json["result"] as? [String: Any],
              let pairData = result.values.first as? [String: Any] else { return nil }

        guard let c = pairData["c"] as? [String], let lastStr = c.first,
              let lastPrice = Double(lastStr) else { return nil }

        let open = Double(pairData["o"] as? String ?? "") ?? (existing?.price ?? lastPrice)
        let highArr = pairData["h"] as? [String]
        let high = Double(highArr?.last ?? highArr?.first ?? "") ?? (existing?.high24h ?? lastPrice)
        let lowArr = pairData["l"] as? [String]
        let low = Double(lowArr?.last ?? lowArr?.first ?? "") ?? (existing?.low24h ?? lastPrice)
        let volArr = pairData["v"] as? [String]
        let volume = Double(volArr?.last ?? volArr?.first ?? "") ?? (existing?.volume ?? 0)
        let vwapArr = pairData["p"] as? [String]
        let vwap = Double(vwapArr?.last ?? vwapArr?.first ?? "") ?? (existing?.vwap ?? lastPrice)

        let bidArr = pairData["b"] as? [String]
        let bidPrice = Double(bidArr?.first ?? "") ?? (existing?.bidPrice ?? 0)
        let askArr = pairData["a"] as? [String]
        let askPrice = Double(askArr?.first ?? "") ?? (existing?.askPrice ?? 0)

        let tradesArr = pairData["t"] as? [Int]
        let trades = tradesArr?.last ?? tradesArr?.first ?? (existing?.trades24h ?? 0)

        let priceChange = lastPrice - open
        let priceChangePercent = open > 0 ? ((lastPrice - open) / open) * 100.0 : 0.0

        return TickerData(
            symbol: symbol.symbol,
            price: lastPrice,
            priceDecimals: decimalPlaces(from: lastStr),
            priceChange: priceChange,
            priceChangePercent: priceChangePercent,
            high24h: high,
            low24h: low,
            vwap: vwap,
            volume: volume,
            quoteVolume: volume * lastPrice,
            volume5m: existing?.volume5m ?? 0,
            quoteVolume5m: existing?.quoteVolume5m ?? 0,
            takerBuyRatio5m: existing?.takerBuyRatio5m ?? 50.0,
            volume15m: existing?.volume15m ?? 0,
            quoteVolume15m: existing?.quoteVolume15m ?? 0,
            takerBuyRatio15m: existing?.takerBuyRatio15m ?? 50.0,
            trades24h: trades,
            trades5m: existing?.trades5m ?? 0,
            bidPrice: bidPrice,
            askPrice: askPrice,
            change1h: existing?.change1h ?? 0,
            change4h: existing?.change4h ?? 0,
            bidDepth20: existing?.bidDepth20 ?? 0,
            askDepth20: existing?.askDepth20 ?? 0,
            bookImbalance: existing?.bookImbalance ?? 50.0,
            lastUpdated: Date(),
            direction: .neutral
        )
    }

    public static func parseKrakenWebSocket(
        _ json: [String: Any],
        symbol: CryptoSymbol,
        existing: TickerData?
    ) -> (ticker: TickerData, direction: PriceDirection)? {
        guard let dataArr = json["data"] as? [[String: Any]],
              let first = dataArr.first else { return nil }

        let price = (first["last"] as? Double) ?? (existing?.price ?? 0)
        guard price > 0 else { return nil }

        let high = (first["high"] as? Double) ?? (existing?.high24h ?? price)
        let low = (first["low"] as? Double) ?? (existing?.low24h ?? price)
        let volume = (first["volume"] as? Double) ?? (existing?.volume ?? 0)
        let vwap = (first["vwap"] as? Double) ?? (existing?.vwap ?? price)
        let bidPrice = (first["bid"] as? Double) ?? (existing?.bidPrice ?? 0)
        let askPrice = (first["ask"] as? Double) ?? (existing?.askPrice ?? 0)

        let priceChange = (first["change"] as? Double) ?? (existing?.priceChange ?? 0)
        let priceChangePercent = (first["change_pct"] as? Double) ?? (existing?.priceChangePercent ?? 0)

        var direction: PriceDirection = .neutral
        if let oldPrice = existing?.price {
            if price > oldPrice {
                direction = .up
            } else if price < oldPrice {
                direction = .down
            }
        }

        let ticker = TickerData(
            symbol: symbol.symbol,
            price: price,
            priceDecimals: existing?.priceDecimals,
            priceChange: priceChange,
            priceChangePercent: priceChangePercent,
            high24h: high,
            low24h: low,
            vwap: vwap,
            volume: volume,
            quoteVolume: volume * price,
            volume5m: existing?.volume5m ?? 0,
            quoteVolume5m: existing?.quoteVolume5m ?? 0,
            takerBuyRatio5m: existing?.takerBuyRatio5m ?? 50.0,
            volume15m: existing?.volume15m ?? 0,
            quoteVolume15m: existing?.quoteVolume15m ?? 0,
            takerBuyRatio15m: existing?.takerBuyRatio15m ?? 50.0,
            trades24h: existing?.trades24h ?? 0,
            trades5m: existing?.trades5m ?? 0,
            bidPrice: bidPrice,
            askPrice: askPrice,
            change1h: existing?.change1h ?? 0,
            change4h: existing?.change4h ?? 0,
            bidDepth20: existing?.bidDepth20 ?? 0,
            askDepth20: existing?.askDepth20 ?? 0,
            bookImbalance: existing?.bookImbalance ?? 50.0,
            lastUpdated: Date(),
            direction: direction
        )

        return (ticker, direction)
    }
}
