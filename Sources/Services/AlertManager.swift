import Foundation
import Combine
import UserNotifications

/// Manages local threshold price alerts and native macOS notifications.
@MainActor
public final class AlertManager: NSObject, ObservableObject {
    public static let shared = AlertManager()

    @Published public private(set) var alerts: [PriceAlert] = []

    private let storageKey = "CryptoNotch_PriceAlerts"
    private var pollerTask: Task<Void, Never>?
    private var notificationDelegate: AlertNotificationDelegate?

    public override init() {
        super.init()
        loadAlerts()
        setupNotifications()
        startBackgroundPoller()
    }

    public var onNotificationFired: ((PriceAlert, Double) -> Void)?

    private var isRunningInTestEnvironment: Bool {
        NSClassFromString("XCTest") != nil || Bundle.main.bundleIdentifier == nil || Bundle.main.bundleIdentifier == "com.apple.dt.xctest.tool"
    }

    // MARK: - Notifications Setup

    private func setupNotifications() {
        guard !isRunningInTestEnvironment else { return }

        let delegate = AlertNotificationDelegate()
        self.notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Persistence

    private func loadAlerts() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([PriceAlert].self, from: data)
            self.alerts = decoded
        } catch {
            print("Failed to decode price alerts: \(error)")
        }
    }

    private func saveAlerts() {
        do {
            let data = try JSONEncoder().encode(alerts)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to encode price alerts: \(error)")
        }
    }

    // MARK: - Alert Management

    @discardableResult
    public func addAlert(
        symbol: String,
        exchange: CryptoExchange = .binance,
        targetPrice: Double,
        direction: AlertDirection
    ) -> PriceAlert {
        let cleanSymbol = CryptoSymbol.from(rawInput: symbol, defaultExchange: exchange).symbol
        let alert = PriceAlert(
            symbol: cleanSymbol,
            exchange: exchange,
            targetPrice: targetPrice,
            direction: direction
        )
        alerts.insert(alert, at: 0)
        saveAlerts()
        return alert
    }

    public func removeAlert(id: UUID) {
        alerts.removeAll { $0.id == id }
        saveAlerts()
    }

    public func clearTriggeredAlerts() {
        alerts.removeAll { $0.isTriggered }
        saveAlerts()
    }

    public func hasActiveAlert(for symbol: String) -> Bool {
        let cleanSymbol = CryptoSymbol.from(rawInput: symbol).symbol
        return alerts.contains { $0.symbol == cleanSymbol && !$0.isTriggered }
    }

    public func activeAlerts(for symbol: String) -> [PriceAlert] {
        let cleanSymbol = CryptoSymbol.from(rawInput: symbol).symbol
        return alerts.filter { $0.symbol == cleanSymbol && !$0.isTriggered }
    }

    public func allAlerts(for symbol: String) -> [PriceAlert] {
        let cleanSymbol = CryptoSymbol.from(rawInput: symbol).symbol
        return alerts.filter { $0.symbol == cleanSymbol }
    }

    // MARK: - Price Evaluation

    public func evaluatePrice(symbol: String, exchange: CryptoExchange, price: Double) {
        let cleanSymbol = CryptoSymbol.from(rawInput: symbol, defaultExchange: exchange).symbol
        var triggeredAny = false

        for index in alerts.indices {
            var alert = alerts[index]
            guard alert.symbol == cleanSymbol && !alert.isTriggered else { continue }

            let shouldTrigger: Bool
            switch alert.direction {
            case .above:
                shouldTrigger = price >= alert.targetPrice
            case .below:
                shouldTrigger = price <= alert.targetPrice
            }

            if shouldTrigger {
                alert.isTriggered = true
                alert.triggeredAt = Date()
                alerts[index] = alert
                triggeredAny = true
                fireNotification(for: alert, currentPrice: price)
            }
        }

        if triggeredAny {
            saveAlerts()
        }
    }

    private func fireNotification(for alert: PriceAlert, currentPrice: Double) {
        onNotificationFired?(alert, currentPrice)
        guard !isRunningInTestEnvironment else { return }

        let content = UNMutableNotificationContent()
        let dirEmoji = alert.direction == .above ? "🚀" : "📉"
        content.title = "\(dirEmoji) \(alert.symbol) Price Alert"

        let formattedCurrent = PriceFormatterCache.shared.format(currentPrice)

        content.body = "\(alert.symbol) crossed \(alert.direction.title) \(alert.formattedTargetPrice) (Now: \(formattedCurrent))"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: alert.id.uuidString,
            content: content,
            trigger: nil // Immediate delivery
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to deliver price alert notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Background Polling for Inactive Symbols

    private func startBackgroundPoller() {
        pollerTask?.cancel()
        pollerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
                guard let self = self else { break }
                await self.pollPendingAlerts()
            }
        }
    }

    private func pollPendingAlerts() async {
        let pending = alerts.filter { !$0.isTriggered }
        guard !pending.isEmpty else { return }

        // Deduplicate pairs to poll
        var pairsToPoll = Set<String>()
        var exchangeMap: [String: CryptoExchange] = [:]
        for alert in pending {
            pairsToPoll.insert(alert.symbol)
            exchangeMap[alert.symbol] = alert.exchange
        }

        for symbol in pairsToPoll {
            guard !Task.isCancelled else { break }
            let exchange = exchangeMap[symbol] ?? .binance
            if let price = await BinanceRestClient.shared.fetchCurrentPrice(symbol: symbol, exchange: exchange) {
                self.evaluatePrice(symbol: symbol, exchange: exchange, price: price)
            }
        }
    }
}

/// Allows notification banners to appear while CryptoNotch is active and frontmost.
final class AlertNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(macOS 14.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }
}
