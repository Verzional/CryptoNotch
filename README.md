# CryptoNotch

[![Release](https://img.shields.io/github/v/release/Verzional/CryptoNotch?style=flat-square&color=34C759&label=Release)](https://github.com/Verzional/CryptoNotch/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-13.0%2B-black.svg?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Security](https://img.shields.io/badge/Apple-Notarized-success.svg?style=flat-square&logo=apple)](https://github.com/Verzional/CryptoNotch/releases)
[![Updates](https://img.shields.io/badge/Sparkle%202-Auto--Update-blueviolet.svg?style=flat-square)](https://sparkle-project.org)
[![Homebrew](https://img.shields.io/badge/Homebrew-verzional%2Ftap-blue.svg?style=flat-square&logo=homebrew)](https://github.com/Verzional/Homebrew-Tap)
[![License](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)

<p align="center">
  <img src="assets/demo.gif" width="765" alt="CryptoNotch Live Demonstration">
</p>

CryptoNotch is a native macOS Dynamic Island utility that displays live cryptocurrency market intelligence directly from **Binance** and **Hyperliquid**. Engineered to fit seamlessly into the physical MacBook display notch, it also provides automatic Dynamic Island rendering for external monitors and non-notch displays.

The application operates as a lightweight floating accessory above full-screen windows and spaces without stealing keyboard focus or interrupting media playback.

---

## Installation

### Download DMG
Download the latest notarized disk image from [GitHub Releases](https://github.com/Verzional/CryptoNotch/releases):
1. Download `CryptoNotch.dmg`.
2. Open the disk image and drag `CryptoNotch.app` to your `/Applications` folder.
3. Launch CryptoNotch from Applications or Spotlight.

### Homebrew
Install directly via the official tap:
```bash
brew install --cask verzional/tap/cryptonotch
```

Or add the tap first:
```bash
brew tap verzional/tap
brew install --cask cryptonotch
```

### Build from Source
Requirements: macOS 13.0+, Xcode 15.0+ or Swift 5.9 toolchain.

```bash
git clone https://github.com/Verzional/CryptoNotch.git
cd CryptoNotch
swift build -c release
```

To build and run directly with Xcode:
```bash
open Package.swift
```

---

## Features

### Display and Notch Integration
- **Hardware Notch Alignment:** Hugs MacBook display notches using native `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` screen metrics.
- **External Monitor Fallback:** Automatically switches to a pill-shaped Dynamic Island on displays without a physical camera notch.
- **Target Display Selector:** Pin the Dynamic Island to your MacBook display or any connected external monitor, with automatic fallback when disconnecting displays.
- **Cursor Pass-Through:** Collapsed state uses non-interfering coordinate hit-testing so clicks, text selections, and drag gestures pass through to underlying applications.
- **Interactive Spring Motion:** Fluid physics-based expansion on cursor hover with debounced auto-collapse.
- **Full-Screen Space Overlay:** Runs as a non-activating `NSPanel` at the `.screenSaver` window level with `[.canJoinAllSpaces, .fullScreenAuxiliary]` collection behavior.

### Live Market Feeds & Multi-Exchange
- **Binance & Hyperliquid Support:** Stream real-time spot and perpetual contract data across multiple premier crypto exchanges.
- **Sub-Second WebSocket Feeds:** Connects directly to Binance Vision streams (`data-stream.binance.vision:9443`) and Hyperliquid endpoints with automatic reconnection.
- **Tick Direction Indicators:** Subtle flash transitions indicating upward and downward price movements with percentage change badges.
- **Authoritative Tick Precision:** Queries exchange `PRICE_FILTER` tick sizes to preserve exact coin decimals (e.g., 3 decimals for INJ, 6 for PUMP) down to 8-decimal micro-caps.

### Real-Time Price Alerts
- **Notch Action Button:** Click the bell icon in the expanded notch to set price thresholds with auto-focus keyboard input.
- **Quick Percentage Chips:** One-tap calculation chips (`-5%`, `-2%`, `+2%`, `+5%`) computed from live market price and rounded to coin tick precision.
- **Active Alerts List:** Manage up to 3 concurrent alerts per pair with persistent capacity tracking (`0/3`).
- **Native macOS Notifications:** Triggers immediate system alerts with sound, banner, and Notification Center delivery via `UNUserNotificationCenter`.
- **Auto-Disarm:** Automatically marks triggered alerts and archives them without repetitive alerts.

### Customizable 6-Slot Grid
The expanded view features a 2x3 statistics grid. Clicking the pencil icon opens an interactive customization popover where any slot can be assigned to one of 22 real-time metrics organized into four semantic categories:

```
[ All ]   [ Price ]   [ Volume ]   [ Depth ]   [ Flow ]
```

Active metrics in your grid are automatically hidden from the selection list to prevent duplicate assignments, and metrics adapt automatically based on the active exchange.

| Category | Metric | Identifier | Description |
| :--- | :--- | :--- | :--- |
| **Price** | 24h High | `24h_high` | Highest traded price in the last 24 hours |
| **Price** | 24h Low | `24h_low` | Lowest traded price in the last 24 hours |
| **Price** | VWAP | `vwap` | Volume-Weighted Average Price |
| **Price** | Open Price | `open_price` | Price at the start of the 24-hour window |
| **Price** | 24h Net $ | `24h_change` | Absolute dollar change in the last 24 hours |
| **Price** | 1h Change | `1h_change` | 1-hour rolling price change percentage |
| **Price** | 4h Change | `4h_change` | 4-hour rolling price change percentage |
| **Volume** | 24h Vol $ | `24h_vol_usdt` | 24-hour total quote turnover (USDT) |
| **Volume** | 24h Vol | `24h_vol_base` | 24-hour total volume in base asset tokens |
| **Volume** | 15m Vol | `15m_vol` | 15-minute rolling trading turnover |
| **Volume** | 5m Vol | `5m_vol` | 5-minute rolling trading turnover |
| **Volume** | 24h Trades | `24h_trades` | Total trade transaction count across 24 hours |
| **Volume** | 5m Trades | `5m_trades` | Trade transaction count in the last 5 minutes |
| **Volume** | Avg Trade $ | `avg_trade` | Average transaction size across 24 hours |
| **Depth** | Book Imbalance | `book_imbalance` | Ratio of queued bids vs asks across top 20 order book levels |
| **Depth** | Bids $ | `bid_depth_20` | Cumulative USDT value of top 20 buy orders |
| **Depth** | Asks $ | `ask_depth_20` | Cumulative USDT value of top 20 sell orders |
| **Depth** | Spread | `spread` | Difference between lowest ask and highest bid |
| **Depth** | Best Bid | `best_bid` | Highest active buy order price |
| **Depth** | Best Ask | `best_ask` | Lowest active sell order price |
| **Flow** | 5m Buy % | `5m_buy_ratio` | Percentage of aggressive taker buy volume over 5 minutes |
| **Flow** | 15m Buy % | `15m_buy_ratio` | Percentage of aggressive taker buy volume over 15 minutes |

### Search, Favorites, and Pair Management
- **Search Popover:** Keyboard-first search interface with auto-focus. Type any ticker (e.g., `ETH`, `SOL`, `BTC`) and press `Return` to switch pairs. Omitting the quote asset automatically defaults to `USDT`.
- **Exchange Switcher:** Toggle between Binance and Hyperliquid directly inside the search header.
- **Interactive Drag-and-Drop Favorites:** Pin up to 9 favorite coins and reorder them by dragging chips across the favorites shelf with real-time spring animation.
- **Fluid Coin Cycling:** Swipe horizontally across the notch with two fingers on your trackpad to cycle through favorite pairs. Discrete per-gesture latching guarantees one swipe switches exactly one coin without momentum skipping.
- **Directional Elastic Pop:** Toggling coins triggers an energetic micro-scale and directional spring transition with a subtle liquid capsule stretch response.
- **Unlisted Recovery Shelf:** If an unlisted ticker is entered, the UI provides an instant one-click recovery back to the previously active symbol alongside favorite shortcuts.

### Menu Bar Companion and Settings
- **Status Bar Companion:** Menu bar item providing coin selection, exchange switching, display target management, and price alert controls.
- **Launch at Login:** Native support via macOS `SMAppService`.
- **Pin Mode:** Keeps the Dynamic Island permanently expanded for dedicated monitoring.
- **Stealth Mode:** Hides the collapsed notch indicator completely until the cursor hovers over the camera notch.
- **Disable Notch Mode:** Hide the island overlay entirely (`⌥⇧D`) and use CryptoNotch strictly via hotkeys or the menu bar.
- **Global Hotkey:** Press `Option + Shift + C` (`⌥⇧C`) anywhere to toggle the island state.

---

## Controls and Shortcuts

| Action | Trigger |
| :--- | :--- |
| **Expand / Collapse Island** | Hover cursor over notch, click collapsed island, or press `Option + Shift + C` (`⌥⇧C`) |
| **Enable / Disable Island** | Press `Option + Shift + D` (`⌥⇧D`) or toggle via the menu bar companion |
| **Cycle Next Favorite** | Two-finger swipe left over notch, drag left, or press `→` |
| **Cycle Previous Favorite** | Two-finger swipe right over notch, drag right, or press `←` |
| **Direct Favorite Jump** | Press number keys `1`–`9` |
| **Search & Switch Pairs** | Click magnifying glass icon in expanded header |
| **Set Price Alert** | Click bell icon in expanded header |
| **Customize Grid** | Click pencil icon in expanded header |
| **Favorite / Unfavorite** | Click star icon beside symbol name |
| **Reorder Favorites** | Drag and drop coin chips in the search popover |
| **Dismiss Popovers** | Press `Escape` or click outside popover boundary |
| **Reset Grid to Defaults** | Click `Reset` inside the customization popover |

---

## Architecture

| Layer | Technology | Description |
| :--- | :--- | :--- |
| **UI Presentation** | SwiftUI & AppKit | Declarative layouts wrapped in custom `NSHostingView` containers |
| **Window Subsystem** | `NSPanel` | Floating accessory window with customized hit testing and window levels |
| **Networking** | `URLSessionWebSocketTask` | Multi-stream WebSocket multiplexer for Binance & Hyperliquid feeds |
| **Notifications** | `UserNotifications` | Native macOS notification center delivery for price threshold alerts |
| **State Flow** | Combine & `@Published` | Unidirectional state management binding network models to views |
| **Persistence** | `UserDefaults` | Stores user favorites, price alerts, custom grid slot mappings, and display preferences |
| **Auto-Updates** | Sparkle 2 | Secure, automated app updates with signed EdDSA appcasts |

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
