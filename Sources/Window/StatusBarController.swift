import AppKit
import Combine
import ServiceManagement
import Sparkle

/// Manages the macOS menu bar status item companion.
@MainActor
public final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?
    private let islandController: DynamicIslandController
    private let binanceService: BinanceService
    private let settings: SettingsModel
    private let updaterController: SPUStandardUpdaterController
    private var cancellables = Set<AnyCancellable>()

    public init(
        islandController: DynamicIslandController,
        binanceService: BinanceService,
        settings: SettingsModel,
        updaterController: SPUStandardUpdaterController? = nil
    ) {
        self.islandController = islandController
        self.binanceService = binanceService
        self.settings = settings
        self.updaterController = updaterController ?? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        super.init()

        setupStatusItem()
        observeData()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureStatusItemIcon()
        rebuildMenu()
    }

    private func observeData() {
        binanceService.$currentSymbol
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        binanceService.$selectedExchange
            .receive(on: RunLoop.main)
            .sink { [weak self] exchange in
                self?.settings.adaptSlots(for: exchange)
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        settings.$isPinned
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        settings.$stealthMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        settings.$isNotchDisabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        settings.$favorites
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        islandController.$isExpanded
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
    }

    private func configureStatusItemIcon() {
        guard let button = statusItem?.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let symbol = NSImage(systemSymbolName: "bitcoinsign.circle", accessibilityDescription: "CryptoNotch")?.withSymbolConfiguration(config) {
            // SF Symbols carry a font baseline that causes NSStatusBarButton to offset the circle 0.5pt (1px) too high.
            // Drawing the symbol inside an exact canvas normalizes alignment to achieve a 1:1 pixel match with the Play icon.
            let icon = NSImage(size: symbol.size, flipped: false) { rect in
                var drawRect = rect
                drawRect.origin.y += 0.5
                symbol.draw(in: drawRect)
                return true
            }
            icon.isTemplate = true
            button.image = icon
            button.imagePosition = .imageOnly
        }
        button.title = ""
        button.toolTip = nil
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        // 1. Select Coin Submenu at the very top
        let coinsMenu = NSMenu()

        // User Favorites first (if any)
        if !settings.favorites.isEmpty {
            let favHeader = NSMenuItem(title: "Favorites", action: nil, keyEquivalent: "")
            favHeader.isEnabled = false
            coinsMenu.addItem(favHeader)

            for fav in settings.favorites {
                let sym = CryptoSymbol.from(rawInput: fav)
                let item = NSMenuItem(
                    title: "\(sym.baseAsset) / \(sym.quoteAsset)",
                    action: #selector(selectCoin(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = sym
                item.state = (sym.symbol == binanceService.currentSymbol.symbol) ? .on : .off
                coinsMenu.addItem(item)
            }
            coinsMenu.addItem(NSMenuItem.separator())
        }

        // Popular Presets
        let popularHeader = NSMenuItem(title: "Popular Pairs", action: nil, keyEquivalent: "")
        popularHeader.isEnabled = false
        coinsMenu.addItem(popularHeader)

        for preset in CryptoSymbol.presets {
            let item = NSMenuItem(
                title: "\(preset.baseAsset) - \(preset.name)",
                action: #selector(selectCoin(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset
            item.state = (preset.symbol == binanceService.currentSymbol.symbol) ? .on : .off
            coinsMenu.addItem(item)
        }

        let coinsMenuItem = NSMenuItem(title: "Select Coin", action: nil, keyEquivalent: "")
        coinsMenuItem.submenu = coinsMenu
        menu.addItem(coinsMenuItem)

        // Exchange Submenu
        let exchangeMenu = NSMenu()
        for exchange in CryptoExchange.allCases {
            let item = NSMenuItem(
                title: exchange.displayName,
                action: #selector(selectExchangeAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = exchange
            item.state = (exchange == binanceService.selectedExchange) ? .on : .off
            exchangeMenu.addItem(item)
        }
        let exchangeMenuItem = NSMenuItem(title: "Exchange", action: nil, keyEquivalent: "")
        exchangeMenuItem.submenu = exchangeMenu
        menu.addItem(exchangeMenuItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Toggle Notch (⌥⇧C)
        let toggleItem = NSMenuItem(
            title: islandController.isExpanded ? "Collapse Notch" : "Expand Notch",
            action: #selector(toggleIsland),
            keyEquivalent: "c"
        )
        toggleItem.keyEquivalentModifierMask = [.option, .shift]
        toggleItem.target = self
        if settings.isNotchDisabled {
            toggleItem.isEnabled = false
        }
        menu.addItem(toggleItem)

        // 3. Disable / Enable Notch Option (⌥⇧D)
        let disableItem = NSMenuItem(
            title: settings.isNotchDisabled ? "Enable Notch" : "Disable Notch",
            action: #selector(toggleDisableNotch),
            keyEquivalent: "d"
        )
        disableItem.keyEquivalentModifierMask = [.option, .shift]
        disableItem.target = self
        menu.addItem(disableItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Pin Option
        let pinItem = NSMenuItem(
            title: "Pin Notch Open",
            action: #selector(togglePin),
            keyEquivalent: ""
        )
        pinItem.target = self
        pinItem.state = settings.isPinned ? .on : .off
        if settings.isNotchDisabled {
            pinItem.isEnabled = false
        }
        menu.addItem(pinItem)

        // 5. Show Only on Hover Option (renamed from Stealth Mode)
        let stealthItem = NSMenuItem(
            title: "Show Only on Hover",
            action: #selector(toggleStealth),
            keyEquivalent: ""
        )
        stealthItem.target = self
        stealthItem.state = settings.stealthMode ? .on : .off
        if settings.isNotchDisabled {
            stealthItem.isEnabled = false
        }
        menu.addItem(stealthItem)

        // 5. Launch at Login
        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        if #available(macOS 13.0, *) {
            launchItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        } else {
            launchItem.state = .off
        }
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())

        // 6. Check for Updates
        let updateItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = updaterController
        menu.addItem(updateItem)

        // 7. Quit
        let quitItem = NSMenuItem(
            title: "Quit CryptoNotch",
            action: #selector(quitApp),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func toggleIsland() {
        islandController.toggleExpansion()
        rebuildMenu()
    }

    @objc private func selectCoin(_ sender: NSMenuItem) {
        if let symbol = sender.representedObject as? CryptoSymbol {
            binanceService.selectSymbol(symbol)
        }
    }

    @objc private func selectExchangeAction(_ sender: NSMenuItem) {
        if let exchange = sender.representedObject as? CryptoExchange {
            binanceService.selectExchange(exchange)
            settings.adaptSlots(for: exchange)
        }
    }

    @objc private func togglePin() {
        settings.isPinned.toggle()
        if settings.isPinned && !islandController.isExpanded {
            islandController.toggleExpansion()
        }
        rebuildMenu()
    }

    @objc private func toggleDisableNotch() {
        islandController.toggleDisableNotch()
        rebuildMenu()
    }

    @objc private func toggleStealth() {
        settings.stealthMode.toggle()
        rebuildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
            } catch {
                print("Failed to toggle Launch at Login: \(error)")
            }
        }
        rebuildMenu()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
