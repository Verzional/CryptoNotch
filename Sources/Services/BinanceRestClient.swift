import Foundation

public enum BinanceRestError: Error {
    case invalidSymbol
    case invalidResponse(statusCode: Int)
    case networkError(String)
}

/// Asynchronous HTTP client for Binance Spot Vision REST API.
public final class BinanceRestClient {
    public static let shared = BinanceRestClient()

    private let primaryRestBase = "https://data-api.binance.vision/api/v3"
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.waitsForConnectivity = true
            config.timeoutIntervalForRequest = 10
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.httpAdditionalHeaders = ["User-Agent": "CryptoNotch/1.1.2"]
            self.session = URLSession(configuration: config)
        }
    }

    public func fetch24hTicker(symbol: String) async throws -> [String: Any] {
        guard let encodedSymbol = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(primaryRestBase)/ticker/24hr?symbol=\(encodedSymbol)") else {
            throw BinanceRestError.invalidSymbol
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BinanceRestError.invalidSymbol
        }

        if httpResponse.statusCode >= 400 && httpResponse.statusCode < 500 {
            throw BinanceRestError.invalidSymbol
        }

        guard httpResponse.statusCode == 200 else {
            throw BinanceRestError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BinanceRestError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        if let code = json["code"] as? Int, code < 0 {
            throw BinanceRestError.invalidSymbol
        }

        return json
    }

    public func fetchKlineVolume(symbol: String, interval: String) async -> (volume: Double, quoteVolume: Double, trades: Int, takerBuyRatio: Double)? {
        guard let encodedSymbol = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(primaryRestBase)/klines?symbol=\(encodedSymbol)&interval=\(interval)&limit=1") else {
            return nil
        }

        guard let (data, _) = try? await session.data(from: url),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[Any]],
              let first = arr.first, first.count > 7 else {
            return nil
        }

        let v = Double(first[5] as? String ?? "0") ?? 0
        let q = Double(first[7] as? String ?? "0") ?? 0
        let trades = first.count > 8 ? (first[8] as? Int ?? 0) : 0
        let tbq = first.count > 10 ? (Double(first[10] as? String ?? "0") ?? 0) : 0
        let ratio = q > 0 ? (tbq / q) * 100 : 50.0

        return (v, q, trades, ratio)
    }

    public func fetchRollingChange(symbol: String, windowSize: String) async -> Double? {
        guard let encodedSymbol = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(primaryRestBase)/ticker?symbol=\(encodedSymbol)&windowSize=\(windowSize)") else {
            return nil
        }

        guard let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let pStr = json["priceChangePercent"] as? String, let p = Double(pStr) {
            return p
        }
        return nil
    }

    public func fetchDepth(symbol: String, limit: Int = 20) async -> [String: Any]? {
        guard let encodedSymbol = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(primaryRestBase)/depth?symbol=\(encodedSymbol)&limit=\(limit)") else {
            return nil
        }

        guard let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return json
    }

    // MARK: - Coinbase REST

    public func fetchCoinbaseTicker(symbol: String) async throws -> (ticker: [String: Any], stats: [String: Any]?) {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let tickerUrl = URL(string: "https://api.exchange.coinbase.com/products/\(encoded)/ticker") else {
            throw BinanceRestError.invalidSymbol
        }

        let (tickerData, tickerResp) = try await session.data(from: tickerUrl)
        guard let httpResp = tickerResp as? HTTPURLResponse else {
            throw BinanceRestError.invalidSymbol
        }
        if httpResp.statusCode == 404 {
            throw BinanceRestError.invalidSymbol
        }
        guard httpResp.statusCode == 200,
              let tickerJson = try? JSONSerialization.jsonObject(with: tickerData) as? [String: Any] else {
            throw BinanceRestError.invalidResponse(statusCode: httpResp.statusCode)
        }

        var statsJson: [String: Any]? = nil
        if let statsUrl = URL(string: "https://api.exchange.coinbase.com/products/\(encoded)/stats"),
           let (statsData, sResp) = try? await session.data(from: statsUrl),
           (sResp as? HTTPURLResponse)?.statusCode == 200 {
            statsJson = try? JSONSerialization.jsonObject(with: statsData) as? [String: Any]
        }

        return (tickerJson, statsJson)
    }

    // MARK: - Kraken REST

    public func fetchKrakenTicker(symbol: String) async throws -> [String: Any] {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.kraken.com/0/public/Ticker?pair=\(encoded)") else {
            throw BinanceRestError.invalidSymbol
        }

        let (data, resp) = try await session.data(from: url)
        guard let httpResp = resp as? HTTPURLResponse else {
            throw BinanceRestError.invalidSymbol
        }
        guard httpResp.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BinanceRestError.invalidResponse(statusCode: httpResp.statusCode)
        }

        if let errors = json["error"] as? [String], !errors.isEmpty {
            throw BinanceRestError.invalidSymbol
        }

        guard let result = json["result"] as? [String: Any], !result.isEmpty else {
            throw BinanceRestError.invalidSymbol
        }

        return json
    }

    public func fetchCoinbaseCandle(symbol: String, granularity: Int) async -> (volume: Double, quoteVolume: Double)? {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.exchange.coinbase.com/products/\(encoded)/candles?granularity=\(granularity)"),
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[Any]],
              let first = arr.first, first.count >= 6 else { return nil }

        let close = (first[4] as? Double) ?? 0
        let volume = (first[5] as? Double) ?? 0
        return (volume, volume * close)
    }

    public func fetchCoinbaseDepth(symbol: String) async -> [String: Any]? {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.exchange.coinbase.com/products/\(encoded)/book?level=2"),
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json
    }

    public func fetchCoinbase1h4hAndVWAP(symbol: String) async -> (change1h: Double?, change4h: Double?, vwap: Double?) {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return (nil, nil, nil)
        }

        async let fetch1h: [[Any]]? = {
            guard let url = URL(string: "https://api.exchange.coinbase.com/products/\(encoded)/candles?granularity=3600"),
                  let (data, resp) = try? await session.data(from: url),
                  (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [[Any]]
        }()

        async let fetch4h: [[Any]]? = {
            guard let url = URL(string: "https://api.exchange.coinbase.com/products/\(encoded)/candles?granularity=14400"),
                  let (data, resp) = try? await session.data(from: url),
                  (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [[Any]]
        }()

        let (candles1h, candles4h) = await (fetch1h, fetch4h)

        var c1h: Double? = nil
        var vwap: Double? = nil

        if let c1hArr = candles1h, !c1hArr.isEmpty {
            let first = c1hArr[0]
            if first.count >= 5 {
                let current = (first[4] as? Double) ?? Double("\(first[4])") ?? 0
                let open1h = (c1hArr.count > 1 && c1hArr[1].count >= 5)
                    ? ((c1hArr[1][4] as? Double) ?? Double("\(c1hArr[1][4])") ?? 0)
                    : ((first[3] as? Double) ?? Double("\(first[3])") ?? 0)
                if open1h > 0 && current > 0 {
                    c1h = ((current - open1h) / open1h) * 100.0
                }
            }

            let last24 = c1hArr.prefix(24)
            var totalQuote: Double = 0
            var totalVol: Double = 0
            for candle in last24 {
                if candle.count >= 6 {
                    let low = (candle[1] as? Double) ?? Double("\(candle[1])") ?? 0
                    let high = (candle[2] as? Double) ?? Double("\(candle[2])") ?? 0
                    let close = (candle[4] as? Double) ?? Double("\(candle[4])") ?? 0
                    let vol = (candle[5] as? Double) ?? Double("\(candle[5])") ?? 0
                    let typical = (low + high + close) / 3.0
                    totalQuote += (typical * vol)
                    totalVol += vol
                }
            }
            if totalVol > 0 {
                vwap = totalQuote / totalVol
            }
        }

        var c4h: Double? = nil
        if let c4hArr = candles4h, !c4hArr.isEmpty {
            let first = c4hArr[0]
            if first.count >= 5 {
                let current = (first[4] as? Double) ?? Double("\(first[4])") ?? 0
                let open4h = (c4hArr.count > 1 && c4hArr[1].count >= 5)
                    ? ((c4hArr[1][4] as? Double) ?? Double("\(c4hArr[1][4])") ?? 0)
                    : ((first[3] as? Double) ?? Double("\(first[3])") ?? 0)
                if open4h > 0 && current > 0 {
                    c4h = ((current - open4h) / open4h) * 100.0
                }
            }
        }

        return (c1h, c4h, vwap)
    }

    public func fetchKrakenOHLC(symbol: String, interval: Int) async -> (volume: Double, quoteVolume: Double, trades: Int)? {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.kraken.com/0/public/OHLC?pair=\(encoded)&interval=\(interval)"),
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let res = json["result"] as? [String: Any],
              let candles = res.values.first(where: { $0 is [[Any]] }) as? [[Any]],
              let last = candles.last, last.count >= 8 else { return nil }

        let close = Double(last[4] as? String ?? "") ?? 0
        let volume = Double(last[6] as? String ?? "") ?? 0
        let trades = (last[7] as? Int) ?? 0
        return (volume, volume * close, trades)
    }

    public func fetchKrakenDepth(symbol: String, count: Int = 20) async -> [String: Any]? {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.kraken.com/0/public/Depth?pair=\(encoded)&count=\(count)"),
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let res = json["result"] as? [String: Any] else { return nil }

        for (_, value) in res {
            if let depthDict = value as? [String: Any], depthDict["bids"] != nil && depthDict["asks"] != nil {
                return depthDict
            }
        }
        return nil
    }

    public func fetchKraken1h4h(symbol: String) async -> (change1h: Double?, change4h: Double?) {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return (nil, nil)
        }

        async let fetch1h: [[Any]]? = {
            guard let url = URL(string: "https://api.kraken.com/0/public/OHLC?pair=\(encoded)&interval=60"),
                  let (data, resp) = try? await session.data(from: url),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let res = json["result"] as? [String: Any],
                  let candles = res.values.first(where: { $0 is [[Any]] }) as? [[Any]] else { return nil }
            return candles
        }()

        async let fetch4h: [[Any]]? = {
            guard let url = URL(string: "https://api.kraken.com/0/public/OHLC?pair=\(encoded)&interval=240"),
                  let (data, resp) = try? await session.data(from: url),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let res = json["result"] as? [String: Any],
                  let candles = res.values.first(where: { $0 is [[Any]] }) as? [[Any]] else { return nil }
            return candles
        }()

        let (candles1h, candles4h) = await (fetch1h, fetch4h)

        var c1h: Double? = nil
        if let arr = candles1h, arr.count >= 2 {
            let last = arr[arr.count - 1]
            let prev = arr[arr.count - 2]
            let current = Double(last[4] as? String ?? "") ?? 0
            let prevClose = Double(prev[4] as? String ?? "") ?? Double(last[1] as? String ?? "") ?? 0
            if prevClose > 0 && current > 0 {
                c1h = ((current - prevClose) / prevClose) * 100.0
            }
        }

        var c4h: Double? = nil
        if let arr = candles4h, arr.count >= 2 {
            let last = arr[arr.count - 1]
            let prev = arr[arr.count - 2]
            let current = Double(last[4] as? String ?? "") ?? 0
            let prevClose = Double(prev[4] as? String ?? "") ?? Double(last[1] as? String ?? "") ?? 0
            if prevClose > 0 && current > 0 {
                c4h = ((current - prevClose) / prevClose) * 100.0
            }
        }

        return (c1h, c4h)
    }

    /// Fetches the latest spot price for a symbol on the specified exchange for alert evaluation.
    public func fetchCurrentPrice(symbol: String, exchange: CryptoExchange) async -> Double? {
        do {
            switch exchange {
            case .binance:
                let json = try await fetch24hTicker(symbol: symbol)
                if let priceStr = json["lastPrice"] as? String, let p = Double(priceStr) {
                    return p
                }
            case .coinbase:
                let (ticker, _) = try await fetchCoinbaseTicker(symbol: symbol)
                if let priceStr = ticker["price"] as? String, let p = Double(priceStr) {
                    return p
                }
            case .kraken:
                let json = try await fetchKrakenTicker(symbol: symbol)
                if let result = json["result"] as? [String: Any],
                   let pairData = result.values.first as? [String: Any],
                   let c = pairData["c"] as? [Any],
                   let priceStr = c.first as? String,
                   let p = Double(priceStr) {
                    return p
                }
            }
        } catch {
            return nil
        }
        return nil
    }
}
