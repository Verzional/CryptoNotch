import XCTest
@testable import CryptoNotch

final class CryptoModelTests: XCTestCase {
    func testCryptoSymbolFromRawInput() {
        let btc = CryptoSymbol.from(rawInput: "btc")
        XCTAssertEqual(btc.symbol, "BTCUSDT")
        XCTAssertEqual(btc.baseAsset, "BTC")
        XCTAssertEqual(btc.quoteAsset, "USDT")
        XCTAssertEqual(btc.name, "Bitcoin")

        let ethusdt = CryptoSymbol.from(rawInput: "ETHUSDT")
        XCTAssertEqual(ethusdt.symbol, "ETHUSDT")
        XCTAssertEqual(ethusdt.baseAsset, "ETH")

        let custom = CryptoSymbol.from(rawInput: "sol")
        XCTAssertEqual(custom.symbol, "SOLUSDT")
        XCTAssertEqual(custom.baseAsset, "SOL")

        // Input with slash separator
        let slashInput = CryptoSymbol.from(rawInput: "BTC/USDT")
        XCTAssertEqual(slashInput.symbol, "BTCUSDT")
        XCTAssertEqual(slashInput.baseAsset, "BTC")
        XCTAssertEqual(slashInput.quoteAsset, "USDT")

        // Input with currency symbol prefix
        let prefixInput = CryptoSymbol.from(rawInput: "$SOL")
        XCTAssertEqual(prefixInput.symbol, "SOLUSDT")
        XCTAssertEqual(prefixInput.baseAsset, "SOL")

        // Input with dash separator
        let dashInput = CryptoSymbol.from(rawInput: "eth-usdt")
        XCTAssertEqual(dashInput.symbol, "ETHUSDT")
        XCTAssertEqual(dashInput.baseAsset, "ETH")

        // Purely symbols input safely defaults to invalid token
        let invalidSymbols = CryptoSymbol.from(rawInput: "///")
        XCTAssertEqual(invalidSymbols.symbol, "INVALIDUSDT")
        XCTAssertEqual(invalidSymbols.baseAsset, "INVALID")
    }

    func testPriceFormattingStandard() {
        let ticker = TickerData(
            symbol: "BTCUSDT",
            price: 63250.75,
            priceChange: 1250.50,
            priceChangePercent: 2.02
        )
        XCTAssertEqual(ticker.formattedPrice, "$63,250.75")
        XCTAssertEqual(ticker.formattedChangePercent, "+2.02%")
    }

    func testPriceFormattingMicroCap() {
        let ticker = TickerData(
            symbol: "PEPEUSDT",
            price: 0.00000854,
            priceChange: -0.00000012,
            priceChangePercent: -1.38
        )
        XCTAssertEqual(ticker.formattedPrice, "$0.00000854")
        XCTAssertEqual(ticker.formattedChangePercent, "-1.38%")
    }

    func testVolumeFormattingBinanceStyle() {
        let ticker = TickerData(
            symbol: "BTCUSDT",
            price: 60000,
            quoteVolume: 186693.456,
            quoteVolume5m: 1234567.89,
            quoteVolume15m: 2500000000.0
        )
        XCTAssertEqual(ticker.formattedQuoteVolume, "186.693K")
        XCTAssertEqual(ticker.formattedQuoteVolume5m, "1.235M")
        XCTAssertEqual(ticker.formattedQuoteVolume15m, "2.500B")
    }

    @MainActor
    func testSettingsFavoritesTogglingAndCap() {
        let settings = SettingsModel()
        settings.favorites = []

        settings.toggleFavorite("BTC")
        XCTAssertTrue(settings.isFavorite("BTCUSDT"))
        XCTAssertEqual(settings.favorites.count, 1)

        settings.toggleFavorite("BTCUSDT")
        XCTAssertFalse(settings.isFavorite("BTCUSDT"))
        XCTAssertEqual(settings.favorites.count, 0)

        // Test max 9 favorites cap (no auto-discard)
        for i in 1...9 {
            let res = settings.toggleFavorite("COIN\(i)")
            XCTAssertTrue(res)
        }
        XCTAssertEqual(settings.favorites.count, 9)
        XCTAssertTrue(settings.isFavorite("COIN1USDT"))

        // Attempting to add 10th coin should be rejected and not discard COIN1
        let rejected = settings.toggleFavorite("COIN10")
        XCTAssertFalse(rejected)
        XCTAssertEqual(settings.favorites.count, 9)
        XCTAssertTrue(settings.isFavorite("COIN1USDT"))
        XCTAssertFalse(settings.isFavorite("COIN10USDT"))
    }

    @MainActor
    func testSettingsFavoritesReordering() {
        let settings = SettingsModel()
        settings.favorites = ["BTCUSDT", "ETHUSDT", "SOLUSDT"]

        // Move SOL (index 2) to first position (index 0)
        settings.moveFavorite(from: 2, to: 0)
        XCTAssertEqual(settings.favorites, ["SOLUSDT", "BTCUSDT", "ETHUSDT"])

        // Move SOL (index 0) to middle (index 1)
        settings.moveFavorite(from: 0, to: 1)
        XCTAssertEqual(settings.favorites, ["BTCUSDT", "SOLUSDT", "ETHUSDT"])

        // Out-of-bounds guards should be no-ops
        settings.moveFavorite(from: -1, to: 0)
        XCTAssertEqual(settings.favorites, ["BTCUSDT", "SOLUSDT", "ETHUSDT"])

        settings.moveFavorite(from: 0, to: 99)
        XCTAssertEqual(settings.favorites, ["BTCUSDT", "SOLUSDT", "ETHUSDT"])
    }

    func testCryptoSymbolPresetsCount() {
        XCTAssertEqual(CryptoSymbol.presets.count, 9)
        XCTAssertTrue(CryptoSymbol.presets.contains(where: { $0.baseAsset == "BTC" }))
        XCTAssertTrue(CryptoSymbol.presets.contains(where: { $0.baseAsset == "ETH" }))
        XCTAssertTrue(CryptoSymbol.presets.contains(where: { $0.baseAsset == "SOL" }))
    }

    @MainActor
    func testBinanceServiceRevertToLastValidSymbol() {
        let service = BinanceService(initialSymbol: CryptoSymbol.presets[0]) // BTC
        XCTAssertEqual(service.currentSymbol.baseAsset, "BTC")
        
        let eth = CryptoSymbol.presets[1] // ETH
        service.selectSymbol(eth)
        XCTAssertEqual(service.currentSymbol.baseAsset, "ETH")
        
        // When user enters an invalid coin and then reverts:
        service.selectSymbol(CryptoSymbol.from(rawInput: "NONEXISTENT"))
        XCTAssertEqual(service.currentSymbol.baseAsset, "NONEXISTENT")
        
        service.revertToLastValidSymbol()
        XCTAssertEqual(service.currentSymbol.baseAsset, "ETH")
    }

    func testStatMetricCasesAndDefaults() {
        XCTAssertEqual(StatMetric.allCases.count, 22)
        XCTAssertEqual(MetricCategory.allCases.count, 5)
        XCTAssertEqual(StatMetric.defaultSlots.count, 6)
        XCTAssertEqual(StatMetric.defaultSlots, [
            .high24h, .quoteVolume15m, .vwap,
            .low24h, .quoteVolume5m, .takerBuyRatio5m
        ])
        for metric in StatMetric.allCases {
            XCTAssertFalse(metric.title.isEmpty)
            XCTAssertFalse(metric.shortDescription.isEmpty)
            XCTAssertNotEqual(metric.category, .all)
        }
    }

    @MainActor
    func testSettingsGridSlotsCustomizationAndReset() {
        let settings = SettingsModel()
        settings.resetGridSlots()
        XCTAssertEqual(settings.gridSlots.count, 6)
        XCTAssertEqual(settings.gridSlots[0], .high24h)
        XCTAssertEqual(settings.gridSlots[1], .quoteVolume15m)
        XCTAssertEqual(settings.gridSlots[3], .low24h)
        XCTAssertEqual(settings.gridSlots[5], .takerBuyRatio5m)

        // Customizing a slot (e.g. changing slot 5 from takerBuyRatio5m to baseVolume24h)
        settings.updateGridSlot(at: 5, to: .baseVolume24h)
        XCTAssertEqual(settings.gridSlots[5], .baseVolume24h)

        // Customizing slot 0 to trades24h
        settings.updateGridSlot(at: 0, to: .trades24h)
        XCTAssertEqual(settings.gridSlots[0], .trades24h)

        // Customizing slot 2 to bookImbalance
        settings.updateGridSlot(at: 2, to: .bookImbalance)
        XCTAssertEqual(settings.gridSlots[2], .bookImbalance)

        // Out of bounds update should be ignored safely
        settings.updateGridSlot(at: 99, to: .vwap)
        settings.updateGridSlot(at: -1, to: .vwap)
        XCTAssertEqual(settings.gridSlots.count, 6)

        // Reset should restore default slots
        settings.resetGridSlots()
        XCTAssertEqual(settings.gridSlots, StatMetric.defaultSlots)
    }

    @MainActor
    func testEffectiveGridSlotsAndAdaptationWhenSwitchingExchanges() {
        let settings = SettingsModel()
        settings.resetGridSlots(for: .binance)

        // 1. Initial Binance slots: all 6 must be available on Binance
        let binanceSlots = settings.effectiveGridSlots(for: .binance)
        XCTAssertEqual(binanceSlots.count, 6)
        XCTAssertEqual(Set(binanceSlots).count, 6)
        for m in binanceSlots {
            XCTAssertTrue(m.isAvailable(on: .binance))
        }

        // 2. Switching to Coinbase: only takerBuyRatio5m (slot 5) is unavailable on Coinbase
        let coinbaseSlots = settings.effectiveGridSlots(for: .coinbase)
        XCTAssertEqual(coinbaseSlots.count, 6)
        XCTAssertEqual(Set(coinbaseSlots).count, 6)
        for m in coinbaseSlots {
            XCTAssertTrue(m.isAvailable(on: .coinbase), "Metric \(m.rawValue) should be available on Coinbase")
        }
        // Slots 0, 1, 2, 3, 4 should be retained as they are available on Coinbase (including VWAP)
        XCTAssertEqual(coinbaseSlots[0], .high24h)
        XCTAssertEqual(coinbaseSlots[1], .quoteVolume15m)
        XCTAssertEqual(coinbaseSlots[2], .vwap)
        XCTAssertEqual(coinbaseSlots[3], .low24h)
        XCTAssertEqual(coinbaseSlots[4], .quoteVolume5m)
        // Unavailable slot 5 (takerBuyRatio5m) defaults to Coinbase default slot 5 (bookImbalance)
        XCTAssertEqual(coinbaseSlots[5], .bookImbalance)

        // 3. Adapt slots to Coinbase
        settings.adaptSlots(for: .coinbase)
        XCTAssertEqual(settings.gridSlots, coinbaseSlots)

        // 4. Switching to Kraken: all slots in Kraken must be available on Kraken
        let krakenSlots = settings.effectiveGridSlots(for: .kraken)
        XCTAssertEqual(krakenSlots.count, 6)
        XCTAssertEqual(Set(krakenSlots).count, 6)
        for m in krakenSlots {
            XCTAssertTrue(m.isAvailable(on: .kraken), "Metric \(m.rawValue) should be available on Kraken")
        }
        XCTAssertTrue(StatMetric.bidDepth20.isAvailable(on: .kraken))
        XCTAssertTrue(StatMetric.askDepth20.isAvailable(on: .kraken))
        XCTAssertTrue(StatMetric.bookImbalance.isAvailable(on: .kraken))
        XCTAssertTrue(StatMetric.change1h.isAvailable(on: .kraken))
        XCTAssertTrue(StatMetric.change4h.isAvailable(on: .kraken))

        XCTAssertTrue(StatMetric.bidDepth20.isAvailable(on: .coinbase))
        XCTAssertTrue(StatMetric.askDepth20.isAvailable(on: .coinbase))
        XCTAssertTrue(StatMetric.bookImbalance.isAvailable(on: .coinbase))
        XCTAssertTrue(StatMetric.change1h.isAvailable(on: .coinbase))
        XCTAssertTrue(StatMetric.change4h.isAvailable(on: .coinbase))
        XCTAssertTrue(StatMetric.vwap.isAvailable(on: .coinbase))

        // 5. Adapt slots to Kraken
        settings.adaptSlots(for: .kraken)
        XCTAssertEqual(settings.gridSlots, krakenSlots)
    }

    func testAdditionalTickerDataFormatters() {
        let ticker = TickerData(
            symbol: "BTCUSDT",
            price: 65000.0,
            priceChange: -1250.0,
            volume: 12500.5,
            quoteVolume: 812500000.0,
            volume15m: 100.0,
            quoteVolume15m: 6500000.0,
            takerBuyRatio15m: 58.4,
            trades24h: 1250000,
            trades5m: 4320,
            bidPrice: 64999.50,
            askPrice: 65000.10,
            change1h: 1.45,
            change4h: -2.30,
            bidDepth20: 3200000.0,
            askDepth20: 2100000.0,
            bookImbalance: 60.38
        )
        XCTAssertEqual(ticker.formattedBaseVolume, "12.501K")
        XCTAssertEqual(ticker.formattedPriceChange, "-$1,250.00")
        XCTAssertEqual(ticker.formattedOpenPrice, "$66,250.00")
        XCTAssertEqual(ticker.formattedTrades24h, "1.25M")
        XCTAssertEqual(ticker.formattedTrades5m, "4.3K")
        XCTAssertEqual(ticker.formattedTakerBuyRatio15m, "58%")
        XCTAssertEqual(ticker.formattedBid, "$64,999.50")
        XCTAssertEqual(ticker.formattedAsk, "$65,000.10")
        XCTAssertEqual(ticker.formattedSpread, "$0.60")
        XCTAssertEqual(ticker.formattedAvgTradeSize, "650.000")
        XCTAssertEqual(ticker.formattedChange1h, "+1.45%")
        XCTAssertEqual(ticker.formattedChange4h, "-2.30%")
        XCTAssertEqual(ticker.formattedBidDepth20, "3.200M")
        XCTAssertEqual(ticker.formattedAskDepth20, "2.100M")
        XCTAssertEqual(ticker.formattedBookImbalance, "60% Bids")
    }

    @MainActor
    func testCyclingSymbolsFavoritesFallback() {
        let settings = SettingsModel()
        let binanceService = BinanceService(initialSymbol: CryptoSymbol.presets[0])
        let controller = DynamicIslandController(binanceService: binanceService, settings: settings)

        // Case 1: Empty favorites -> should fallback to presets
        settings.favorites = []
        XCTAssertEqual(controller.cyclingSymbols().map(\.symbol), CryptoSymbol.presets.map(\.symbol))

        // Case 2: Only 1 favorite -> should still fallback to presets so cycling is possible
        settings.favorites = ["SOLUSDT"]
        XCTAssertEqual(controller.cyclingSymbols().map(\.symbol), CryptoSymbol.presets.map(\.symbol))

        // Case 3: 2 or more favorites -> should use curated favorites
        settings.favorites = ["SOLUSDT", "ETHUSDT", "DOGEUSDT"]
        let symbols = controller.cyclingSymbols().map(\.symbol)
        XCTAssertEqual(symbols, ["SOLUSDT", "ETHUSDT", "DOGEUSDT"])
    }

    @MainActor
    func testCycleFavoriteDirectionNextAndPrevious() {
        let settings = SettingsModel()
        settings.favorites = ["BTCUSDT", "ETHUSDT", "SOLUSDT"]
        let binanceService = BinanceService(initialSymbol: CryptoSymbol.presets[0]) // BTCUSDT
        let controller = DynamicIslandController(binanceService: binanceService, settings: settings)

        // Start at BTC
        XCTAssertEqual(binanceService.currentSymbol.symbol, "BTCUSDT")

        // Cycle next -> ETH
        controller.cycleFavorite(direction: .next)
        XCTAssertEqual(binanceService.currentSymbol.symbol, "ETHUSDT")
        XCTAssertEqual(controller.cycleDirection, .next)

        // Cycle next -> SOL
        controller.cycleFavorite(direction: .next)
        XCTAssertEqual(binanceService.currentSymbol.symbol, "SOLUSDT")
        XCTAssertEqual(controller.cycleDirection, .next)

        // Cycle next -> wrap around to BTC
        controller.cycleFavorite(direction: .next)
        XCTAssertEqual(binanceService.currentSymbol.symbol, "BTCUSDT")
        XCTAssertEqual(controller.cycleDirection, .next)

        // Cycle previous -> wrap around backwards to SOL
        controller.cycleFavorite(direction: .previous)
        XCTAssertEqual(binanceService.currentSymbol.symbol, "SOLUSDT")
        XCTAssertEqual(controller.cycleDirection, .previous)

        // Cycle previous -> ETH
        controller.cycleFavorite(direction: .previous)
        XCTAssertEqual(binanceService.currentSymbol.symbol, "ETHUSDT")
        XCTAssertEqual(controller.cycleDirection, .previous)
    }

    @MainActor
    func testJumpToFavoriteIndex() {
        let settings = SettingsModel()
        settings.favorites = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "DOGEUSDT"]
        let binanceService = BinanceService(initialSymbol: CryptoSymbol.presets[0]) // BTCUSDT (index 0)
        let controller = DynamicIslandController(binanceService: binanceService, settings: settings)

        // Jump forward to index 2 (SOL)
        controller.jumpToFavorite(index: 2)
        XCTAssertEqual(binanceService.currentSymbol.symbol, "SOLUSDT")
        XCTAssertEqual(controller.cycleDirection, .next)

        // Jump backwards to index 1 (ETH)
        controller.jumpToFavorite(index: 1)
        XCTAssertEqual(binanceService.currentSymbol.symbol, "ETHUSDT")
        XCTAssertEqual(controller.cycleDirection, .previous)

        // Jump to same index -> no-op
        controller.jumpToFavorite(index: 1)
        XCTAssertEqual(binanceService.currentSymbol.symbol, "ETHUSDT")

        // Jump to out of bounds -> no-op
        controller.jumpToFavorite(index: 99)
        XCTAssertEqual(binanceService.currentSymbol.symbol, "ETHUSDT")
    }

    @MainActor
    func testNotchDisabledToggleAndControllerBehavior() {
        let settings = SettingsModel()
        settings.isNotchDisabled = false
        let binanceService = BinanceService(initialSymbol: CryptoSymbol.presets[0])
        let controller = DynamicIslandController(binanceService: binanceService, settings: settings)

        XCTAssertFalse(settings.isNotchDisabled)
        XCTAssertFalse(controller.panel.ignoresMouseEvents)

        // Toggle disable via controller
        controller.toggleDisableNotch()
        XCTAssertTrue(settings.isNotchDisabled)
        XCTAssertTrue(controller.panel.ignoresMouseEvents)

        // When disabled, toggleExpansion() should be guarded
        controller.toggleExpansion()
        XCTAssertFalse(controller.isExpanded)

        // Re-enable
        controller.toggleDisableNotch()
        XCTAssertFalse(settings.isNotchDisabled)
        XCTAssertFalse(controller.panel.ignoresMouseEvents)
    }

    @MainActor
    func testTargetDisplaySettingsAndResolution() {
        let settings = SettingsModel()
        settings.targetDisplay = "automatic"
        XCTAssertEqual(settings.targetDisplay, "automatic")

        let binanceService = BinanceService(initialSymbol: CryptoSymbol.presets[0])
        let controller = DynamicIslandController(binanceService: binanceService, settings: settings)

        // Automatic resolution returns a valid connected screen
        let autoScreen = controller.resolveTargetScreen()
        XCTAssertFalse(NSScreen.screens.isEmpty)
        XCTAssertTrue(NSScreen.screens.contains(autoScreen))

        // If multiple screens exist, verify selecting a specific screen by UUID or localizedName
        if let firstScreen = NSScreen.screens.first {
            if let uuid = firstScreen.displayUUIDString {
                settings.targetDisplay = uuid
                let resolved = controller.resolveTargetScreen()
                XCTAssertEqual(resolved.displayUUIDString, uuid)
            } else {
                settings.targetDisplay = firstScreen.localizedName
                let resolved = controller.resolveTargetScreen()
                XCTAssertEqual(resolved.localizedName, firstScreen.localizedName)
            }
        }

        // Graceful fallback for non-existent display ID
        settings.targetDisplay = "NonExistentDisplay_9999"
        let fallbackScreen = controller.resolveTargetScreen()
        XCTAssertTrue(NSScreen.screens.contains(fallbackScreen))

        // Reset to automatic
        settings.targetDisplay = "automatic"
        XCTAssertEqual(controller.resolveTargetScreen(), autoScreen)
    }

    func testPriceAlertModelAndFormatting() {
        let alertHigh = PriceAlert(
            symbol: "BTCUSDT",
            exchange: .binance,
            targetPrice: 65000.50,
            direction: .above
        )
        XCTAssertEqual(alertHigh.symbol, "BTCUSDT")
        XCTAssertEqual(alertHigh.direction, .above)
        XCTAssertEqual(alertHigh.direction.symbol, "▲")
        XCTAssertEqual(alertHigh.direction.title, "Above")
        XCTAssertEqual(alertHigh.formattedTargetPrice, "$65,000.50")
        XCTAssertFalse(alertHigh.isTriggered)
        XCTAssertNil(alertHigh.triggeredAt)

        let alertLow = PriceAlert(
            symbol: "DOGEUSDT",
            exchange: .binance,
            targetPrice: 0.1234,
            direction: .below
        )
        XCTAssertEqual(alertLow.direction, .below)
        XCTAssertEqual(alertLow.direction.symbol, "▼")
        XCTAssertEqual(alertLow.direction.title, "Below")
        XCTAssertEqual(alertLow.formattedTargetPrice, "$0.1234")

        let alertMicro = PriceAlert(
            symbol: "PEPEUSDT",
            exchange: .binance,
            targetPrice: 0.0000085,
            direction: .above
        )
        XCTAssertEqual(alertMicro.formattedTargetPrice, "$0.0000085")
    }

    @MainActor
    func testAlertManagerAddEvaluateAndDisarm() {
        let manager = AlertManager.shared
        // Clear any leftover alerts
        for alert in manager.alerts {
            manager.removeAlert(id: alert.id)
        }
        XCTAssertEqual(manager.alerts.count, 0)

        // Add 'above' alert for BTC at 70,000
        let btcAlert = manager.addAlert(
            symbol: "BTC",
            exchange: .binance,
            targetPrice: 70000,
            direction: .above
        )
        XCTAssertEqual(btcAlert.symbol, "BTCUSDT")
        XCTAssertTrue(manager.hasActiveAlert(for: "BTC"))
        XCTAssertTrue(manager.hasActiveAlert(for: "BTCUSDT"))
        XCTAssertFalse(manager.hasActiveAlert(for: "ETH"))

        // Add 'below' alert for ETH at 3,000
        _ = manager.addAlert(
            symbol: "ETH",
            exchange: .binance,
            targetPrice: 3000,
            direction: .below
        )
        XCTAssertTrue(manager.hasActiveAlert(for: "ETH"))

        // Price below threshold: BTC at 69,500 should NOT trigger
        manager.evaluatePrice(symbol: "BTCUSDT", exchange: .binance, price: 69500)
        XCTAssertTrue(manager.hasActiveAlert(for: "BTCUSDT"))
        XCTAssertEqual(manager.activeAlerts(for: "BTCUSDT").count, 1)

        var notifiedAlert: PriceAlert?
        var notifiedPrice: Double?
        manager.onNotificationFired = { alert, price in
            notifiedAlert = alert
            notifiedPrice = price
        }

        // Price hits threshold: BTC at 70,050 triggers and auto-disarms
        manager.evaluatePrice(symbol: "BTCUSDT", exchange: .binance, price: 70050)
        XCTAssertFalse(manager.hasActiveAlert(for: "BTCUSDT"))
        XCTAssertEqual(manager.allAlerts(for: "BTCUSDT").count, 0)
        XCTAssertEqual(notifiedAlert?.symbol, "BTCUSDT")
        XCTAssertEqual(notifiedPrice, 70050)

        // Price moves even higher: should NOT re-trigger or duplicate
        notifiedAlert = nil
        manager.evaluatePrice(symbol: "BTCUSDT", exchange: .binance, price: 75000)
        XCTAssertNil(notifiedAlert)
        XCTAssertEqual(manager.allAlerts(for: "BTCUSDT").count, 0)

        // ETH at 3,050: should NOT trigger 'below' alert
        manager.evaluatePrice(symbol: "ETHUSDT", exchange: .binance, price: 3050)
        XCTAssertTrue(manager.hasActiveAlert(for: "ETH"))

        // ETH drops to 2,990: triggers and auto-disarms
        manager.evaluatePrice(symbol: "ETHUSDT", exchange: .binance, price: 2990)
        XCTAssertFalse(manager.hasActiveAlert(for: "ETH"))
        XCTAssertEqual(manager.activeAlerts(for: "ETHUSDT").count, 0)
        XCTAssertEqual(manager.alerts.count, 0)
    }

    @MainActor
    func testAlertManagerRemovalAndQueries() {
        let manager = AlertManager.shared
        for alert in manager.alerts {
            manager.removeAlert(id: alert.id)
        }

        let alert1 = manager.addAlert(symbol: "SOL", exchange: .binance, targetPrice: 150, direction: .above)
        let alert2 = manager.addAlert(symbol: "SOL", exchange: .binance, targetPrice: 120, direction: .below)
        XCTAssertEqual(manager.activeAlerts(for: "SOL").count, 2)

        // Remove single alert
        manager.removeAlert(id: alert1.id)
        XCTAssertEqual(manager.activeAlerts(for: "SOL").count, 1)
        XCTAssertEqual(manager.activeAlerts(for: "SOL")[0].id, alert2.id)

        // Clean up
        manager.removeAlert(id: alert2.id)
        XCTAssertEqual(manager.alerts.count, 0)
    }
}
