import Foundation
import Combine

/// Clean facade orchestrating Binance, Coinbase, and Kraken REST and WebSocket streams for the UI.
@MainActor
public final class BinanceService: ObservableObject {
    @Published public var selectedExchange: CryptoExchange {
        didSet {
            if oldValue != selectedExchange {
                UserDefaults.standard.set(selectedExchange.rawValue, forKey: "CryptoNotch_SelectedExchange")
                restartConnection()
            }
        }
    }

    @Published public var currentSymbol: CryptoSymbol {
        didSet {
            if oldValue.symbol != currentSymbol.symbol {
                restartConnection()
            }
        }
    }
    
    @Published public private(set) var ticker: TickerData? {
        didSet {
            if let t = ticker {
                AlertManager.shared.evaluatePrice(symbol: t.symbol, exchange: selectedExchange, price: t.price)
            }
        }
    }
    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var flashDirection: PriceDirection?
    @Published public private(set) var isInvalidSymbol: Bool = false
    private var lastValidSymbol: CryptoSymbol

    private let restClient: BinanceRestClient
    private let streamManager: BinanceStreamManager
    private var fetchTickerTask: Task<Void, Never>?
    private var reconnectTimer: Timer?
    private var flashResetWorkItem: DispatchWorkItem?

    public init(
        initialSymbol: CryptoSymbol? = nil,
        initialExchange: CryptoExchange? = nil,
        restClient: BinanceRestClient = .shared,
        streamManager: BinanceStreamManager = BinanceStreamManager()
    ) {
        let savedExchangeRaw = UserDefaults.standard.string(forKey: "CryptoNotch_SelectedExchange")
        let exchange = initialExchange ?? savedExchangeRaw.flatMap { CryptoExchange(rawValue: $0) } ?? .binance
        self.selectedExchange = exchange

        let saved = UserDefaults.standard.string(forKey: "CryptoNotch_SelectedSymbol")
            ?? UserDefaults.standard.string(forKey: "CryptoAtoll_SelectedSymbol")
            ?? UserDefaults.standard.string(forKey: "CryptoIsland_SelectedSymbol")
            ?? "BTCUSDT"
        let symbol = initialSymbol ?? CryptoSymbol.from(rawInput: saved, defaultExchange: exchange)
        self.currentSymbol = symbol
        self.lastValidSymbol = symbol
        self.restClient = restClient
        self.streamManager = streamManager

        start()
    }

    deinit {
        streamManager.disconnect()
        reconnectTimer?.invalidate()
    }

    public func selectExchange(_ exchange: CryptoExchange) {
        guard exchange != selectedExchange else { return }
        selectedExchange = exchange
    }

    public func selectSymbol(_ symbol: CryptoSymbol) {
        guard symbol.symbol != currentSymbol.symbol else { return }
        if !isInvalidSymbol && (ticker != nil || CryptoSymbol.presets.contains(where: { $0.symbol == currentSymbol.symbol })) {
            lastValidSymbol = currentSymbol
        }
        isInvalidSymbol = false
        errorMessage = nil
        currentSymbol = symbol
    }

    public func revertToLastValidSymbol() {
        let target: CryptoSymbol
        if lastValidSymbol.symbol != currentSymbol.symbol {
            target = lastValidSymbol
        } else if let fallback = CryptoSymbol.presets.first(where: { $0.symbol != currentSymbol.symbol }) {
            target = fallback
        } else {
            target = CryptoSymbol.presets[0]
        }
        selectSymbol(target)
    }

    public func start() {
        fetchInitialSnapshot()
        connectWebSocket()
    }

    public func restartConnection() {
        fetchTickerTask?.cancel()
        fetchTickerTask = nil
        streamManager.disconnect()
        reconnectTimer?.invalidate()
        isConnected = false
        ticker = nil
        isInvalidSymbol = false
        errorMessage = nil
        
        fetchInitialSnapshot()
        connectWebSocket()
    }

    private func saveSelectedSymbol() {
        UserDefaults.standard.set(currentSymbol.symbol, forKey: "CryptoNotch_SelectedSymbol")
    }

    // MARK: - Initial REST Snapshot Hydration
    private func fetchInitialSnapshot() {
        fetchTickerTask?.cancel()

        let targetSymbol = currentSymbol
        let exchange = selectedExchange
        let formatted = targetSymbol.formattedSymbol(for: exchange)

        fetchTickerTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                switch exchange {
                case .binance:
                    async let precisionTask = self.restClient.fetchPrecision(symbol: formatted)
                    let json = try await self.restClient.fetch24hTicker(symbol: formatted)
                    let precision = await precisionTask
                    guard !Task.isCancelled, self.currentSymbol.symbol == targetSymbol.symbol, self.selectedExchange == exchange else { return }

                    self.isInvalidSymbol = false
                    self.errorMessage = nil
                    self.lastValidSymbol = targetSymbol
                    self.saveSelectedSymbol()

                    if let parsed = BinanceDataParser.parseRestTicker(json, symbol: targetSymbol, existing: self.ticker, knownDecimals: precision) {
                        self.ticker = parsed
                    }

                case .coinbase:
                    let (tickerJson, statsJson) = try await self.restClient.fetchCoinbaseTicker(symbol: formatted)
                    guard !Task.isCancelled, self.currentSymbol.symbol == targetSymbol.symbol, self.selectedExchange == exchange else { return }

                    self.isInvalidSymbol = false
                    self.errorMessage = nil
                    self.lastValidSymbol = targetSymbol
                    self.saveSelectedSymbol()

                    if let parsed = BinanceDataParser.parseCoinbaseRest(tickerJson: tickerJson, statsJson: statsJson, symbol: targetSymbol, existing: self.ticker) {
                        self.ticker = parsed
                    }

                case .kraken:
                    let json = try await self.restClient.fetchKrakenTicker(symbol: formatted)
                    guard !Task.isCancelled, self.currentSymbol.symbol == targetSymbol.symbol, self.selectedExchange == exchange else { return }

                    self.isInvalidSymbol = false
                    self.errorMessage = nil
                    self.lastValidSymbol = targetSymbol
                    self.saveSelectedSymbol()

                    if let parsed = BinanceDataParser.parseKrakenRest(json, symbol: targetSymbol, existing: self.ticker) {
                        self.ticker = parsed
                    }
                }
            } catch BinanceRestError.invalidSymbol {
                guard !Task.isCancelled, self.currentSymbol.symbol == targetSymbol.symbol, self.selectedExchange == exchange else { return }
                self.handleInvalidSymbol()
                return
            } catch {
                guard !Task.isCancelled, self.currentSymbol.symbol == targetSymbol.symbol, self.selectedExchange == exchange else { return }
                if (error as? URLError)?.code != .cancelled {
                    self.errorMessage = "Network connection error"
                }
            }

            guard !Task.isCancelled, !self.isInvalidSymbol, self.currentSymbol.symbol == targetSymbol.symbol, self.selectedExchange == exchange else { return }

            // Concurrent auxiliary hydration: 5m/15m volume, rolling changes, depth
            if exchange == .binance {
                async let kline5m = self.restClient.fetchKlineVolume(symbol: formatted, interval: "5m")
                async let kline15m = self.restClient.fetchKlineVolume(symbol: formatted, interval: "15m")
                async let change1h = self.restClient.fetchRollingChange(symbol: formatted, windowSize: "1h")
                async let change4h = self.restClient.fetchRollingChange(symbol: formatted, windowSize: "4h")
                async let depth = self.restClient.fetchDepth(symbol: formatted, limit: 20)

                let (k5, k15, c1, c4, d) = await (kline5m, kline15m, change1h, change4h, depth)
                guard !Task.isCancelled, self.currentSymbol.symbol == targetSymbol.symbol, self.selectedExchange == exchange else { return }

                if let k5 = k5 {
                    self.ticker?.volume5m = k5.volume
                    self.ticker?.quoteVolume5m = k5.quoteVolume
                    self.ticker?.trades5m = k5.trades
                    self.ticker?.takerBuyRatio5m = k5.takerBuyRatio
                }
                if let k15 = k15 {
                    self.ticker?.volume15m = k15.volume
                    self.ticker?.quoteVolume15m = k15.quoteVolume
                    self.ticker?.takerBuyRatio15m = k15.takerBuyRatio
                }
                if let c1 = c1 { self.ticker?.change1h = c1 }
                if let c4 = c4 { self.ticker?.change4h = c4 }
                if let d = d, var current = self.ticker {
                    BinanceDataParser.applyDepth(d, to: &current)
                    self.ticker = current
                }
            } else if exchange == .coinbase {
                async let c5m = self.restClient.fetchCoinbaseCandle(symbol: formatted, granularity: 300)
                async let c15m = self.restClient.fetchCoinbaseCandle(symbol: formatted, granularity: 900)
                async let depthTask = self.restClient.fetchCoinbaseDepth(symbol: formatted)
                async let rollingAndVWAPTask = self.restClient.fetchCoinbase1h4hAndVWAP(symbol: formatted)
                let (c5, c15, depthJson, rolling) = await (c5m, c15m, depthTask, rollingAndVWAPTask)
                guard !Task.isCancelled, self.currentSymbol.symbol == targetSymbol.symbol, self.selectedExchange == exchange else { return }

                if let c5 = c5 {
                    self.ticker?.volume5m = c5.volume
                    self.ticker?.quoteVolume5m = c5.quoteVolume
                }
                if let c15 = c15 {
                    self.ticker?.volume15m = c15.volume
                    self.ticker?.quoteVolume15m = c15.quoteVolume
                }
                if let c1 = rolling.change1h { self.ticker?.change1h = c1 }
                if let c4 = rolling.change4h { self.ticker?.change4h = c4 }
                if let v = rolling.vwap { self.ticker?.vwap = v }
                if let d = depthJson, var current = self.ticker {
                    BinanceDataParser.applyDepth(d, to: &current)
                    self.ticker = current
                }
            } else if exchange == .kraken {
                async let o5m = self.restClient.fetchKrakenOHLC(symbol: formatted, interval: 5)
                async let o15m = self.restClient.fetchKrakenOHLC(symbol: formatted, interval: 15)
                async let depthTask = self.restClient.fetchKrakenDepth(symbol: formatted, count: 20)
                async let rollingTask = self.restClient.fetchKraken1h4h(symbol: formatted)
                let (o5, o15, depthJson, rolling) = await (o5m, o15m, depthTask, rollingTask)
                guard !Task.isCancelled, self.currentSymbol.symbol == targetSymbol.symbol, self.selectedExchange == exchange else { return }

                if let o5 = o5 {
                    self.ticker?.volume5m = o5.volume
                    self.ticker?.quoteVolume5m = o5.quoteVolume
                    self.ticker?.trades5m = o5.trades
                }
                if let o15 = o15 {
                    self.ticker?.volume15m = o15.volume
                    self.ticker?.quoteVolume15m = o15.quoteVolume
                }
                if let c1 = rolling.change1h { self.ticker?.change1h = c1 }
                if let c4 = rolling.change4h { self.ticker?.change4h = c4 }
                if let d = depthJson, var current = self.ticker {
                    BinanceDataParser.applyDepth(d, to: &current)
                    self.ticker = current
                }
            }
        }
    }

    private func handleInvalidSymbol() {
        self.isInvalidSymbol = true
        self.errorMessage = "Coin not found on \(selectedExchange.displayName)"
        self.ticker = nil
        self.isConnected = false
        self.streamManager.disconnect()
        self.reconnectTimer?.invalidate()
    }

    // MARK: - WebSocket Streaming
    private func connectWebSocket() {
        guard !isInvalidSymbol else { return }
        reconnectTimer?.invalidate()

        let formatted = currentSymbol.formattedSymbol(for: selectedExchange)

        streamManager.connect(
            symbol: formatted,
            exchange: selectedExchange,
            onConnected: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self, !self.isConnected else { return }
                    self.isConnected = true
                    self.errorMessage = nil
                }
            },
            onMessage: { [weak self] payloadText in
                Task { @MainActor [weak self] in
                    self?.handleWebSocketMessage(payloadText)
                }
            },
            onError: { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.isConnected = false
                    if !self.isInvalidSymbol {
                        if (error as? URLError)?.code != .cancelled && !error.localizedDescription.contains("cancelled") {
                            self.errorMessage = error.localizedDescription
                            self.scheduleReconnect()
                        }
                    }
                }
            }
        )
    }

    private func handleWebSocketMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        switch selectedExchange {
        case .coinbase:
            guard let msgType = json["type"] as? String else { return }
            if msgType == "ticker" {
                if let (newTicker, dir) = BinanceDataParser.parseCoinbaseWebSocket(json, symbol: currentSymbol, existing: self.ticker) {
                    self.ticker = newTicker
                    if dir != .neutral {
                        triggerFlash(dir)
                    }
                }
            }

        case .kraken:
            guard let channel = json["channel"] as? String else { return }
            if channel == "ticker" {
                if let (newTicker, dir) = BinanceDataParser.parseKrakenWebSocket(json, symbol: currentSymbol, existing: self.ticker) {
                    self.ticker = newTicker
                    if dir != .neutral {
                        triggerFlash(dir)
                    }
                }
            }

        case .binance:
            let payload = (json["data"] as? [String: Any]) ?? json
            let stream = (json["stream"] as? String) ?? ""

            if stream.contains("@ticker_1h") {
                if let pStr = payload["P"] as? String, let p = Double(pStr) {
                    self.ticker?.change1h = p
                }
            } else if stream.contains("@ticker_4h") {
                if let pStr = payload["P"] as? String, let p = Double(pStr) {
                    self.ticker?.change4h = p
                }
            } else if stream.contains("@depth20") {
                if var current = self.ticker {
                    BinanceDataParser.applyDepth(payload, to: &current)
                    self.ticker = current
                }
            } else if stream.contains("@ticker") || stream.isEmpty {
                let precision = self.restClient.cachedPrecision(for: currentSymbol.symbol)
                if let (newTicker, dir) = BinanceDataParser.parseWebSocketTicker(payload, symbol: currentSymbol, existing: self.ticker, knownDecimals: precision) {
                    self.ticker = newTicker
                    if dir != .neutral {
                        triggerFlash(dir)
                    }
                }
            } else if stream.contains("@kline_5m") {
                if var current = self.ticker {
                    BinanceDataParser.applyKline(payload, interval: "5m", to: &current)
                    self.ticker = current
                }
            } else if stream.contains("@kline_15m") {
                if var current = self.ticker {
                    BinanceDataParser.applyKline(payload, interval: "15m", to: &current)
                    self.ticker = current
                }
            }
        }
    }

    private func triggerFlash(_ direction: PriceDirection) {
        flashResetWorkItem?.cancel()
        flashDirection = direction

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.flashDirection = nil
            }
        }
        flashResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: workItem)
    }

    private func scheduleReconnect() {
        guard !isInvalidSymbol else { return }
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, !self.isInvalidSymbol else { return }
                self.connectWebSocket()
            }
        }
    }
}
