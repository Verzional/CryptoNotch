import SwiftUI
import AppKit

/// Expanded card layout displaying detailed crypto metrics, action tools, and quick switchers.
public struct ExpandedNotchView: View {
    public let geometry: NotchGeometry
    @ObservedObject var controller: DynamicIslandController
    @ObservedObject var binanceService: BinanceService
    @ObservedObject var settings: SettingsModel
    @ObservedObject var alertManager: AlertManager = .shared

    @State private var isFavoritesFullAlertShowing: Bool = false
    @State private var starShake: CGFloat = 0
    @State private var starScale: CGFloat = 1.0
    @State private var isStarHovered: Bool = false
    @State private var dismissToastTask: Task<Void, Never>? = nil
    @State private var isAlertHovered: Bool = false
    @State private var isPencilHovered: Bool = false
    @State private var isSearchHovered: Bool = false
    @State private var isBackHovered: Bool = false
    @State private var hoveredPillSymbol: String? = nil

    public init(
        geometry: NotchGeometry,
        controller: DynamicIslandController,
        binanceService: BinanceService,
        settings: SettingsModel
    ) {
        self.geometry = geometry
        self.controller = controller
        self.binanceService = binanceService
        self.settings = settings
    }

    public var body: some View {
        VStack(spacing: 0) {
            expandedTopBar

            if binanceService.isInvalidSymbol {
                invalidSymbolErrorView
            } else {
                // Content below notch
                VStack(spacing: 8) {
                    // Price & 24h Change Row
                    HStack(alignment: .center, spacing: 8) {
                        if let ticker = binanceService.ticker {
                            Text(ticker.formattedPrice)
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundColor(flashColor)
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.28, dampingFraction: 0.8), value: ticker.price)
                                .scaleEffect(binanceService.flashDirection != nil ? 1.03 : 1.0)
                                .animation(.spring(response: 0.24, dampingFraction: 0.62), value: binanceService.flashDirection)

                            // Change Badge (Inline with price)
                            HStack(spacing: 3) {
                                Image(systemName: ticker.priceChangePercent >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.system(size: 9, weight: .bold))
                                Text(ticker.formattedChangePercent)
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .contentTransition(.numericText())
                                    .animation(.spring(response: 0.28, dampingFraction: 0.8), value: ticker.priceChangePercent)
                            }
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(
                                (ticker.priceChangePercent >= 0 ? Color.green : Color.red).opacity(0.2)
                            )
                            .foregroundColor(ticker.priceChangePercent >= 0 ? .green : .red)
                            .clipShape(Capsule())
                        } else {
                            // Price loading placeholder
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.white.opacity(0.16))
                                .frame(width: 88, height: 20)
                                .skeletonPulse()

                            // Change Badge loading placeholder
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 54, height: 20)
                                .skeletonPulse()
                        }

                        Spacer()

                        // Exchange Badge
                        Text(binanceService.selectedExchange.displayName.uppercased())
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .tracking(0.5)
                            .foregroundColor(.white.opacity(0.45))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                    }
                    .frame(height: 22)

                    // 2-Row Stats Grid: Configurable 6-Slot Grid
                    VStack(spacing: 5) {
                        let slots = settings.effectiveGridSlots(for: binanceService.selectedExchange)
                        // Row 1
                        HStack(spacing: 8) {
                            MetricCellView(slotIndex: 0, metric: slots[0], ticker: binanceService.ticker)
                            Divider().frame(height: 18).background(Color.white.opacity(0.12))
                            MetricCellView(slotIndex: 1, metric: slots[1], ticker: binanceService.ticker)
                            Divider().frame(height: 18).background(Color.white.opacity(0.12))
                            MetricCellView(slotIndex: 2, metric: slots[2], ticker: binanceService.ticker)
                        }

                        Divider().background(Color.white.opacity(0.08))

                        // Row 2
                        HStack(spacing: 8) {
                            MetricCellView(slotIndex: 3, metric: slots[3], ticker: binanceService.ticker)
                            Divider().frame(height: 18).background(Color.white.opacity(0.12))
                            MetricCellView(slotIndex: 4, metric: slots[4], ticker: binanceService.ticker)
                            Divider().frame(height: 18).background(Color.white.opacity(0.12))
                            MetricCellView(slotIndex: 5, metric: slots[5], ticker: binanceService.ticker)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
                }
                .id(binanceService.currentSymbol.symbol + "_expanded_content")
                .transition(.opacity)
                .padding(.top, 4)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .overlay(alignment: .top) {
            if isFavoritesFullAlertShowing {
                favoritesFullToast
                    .padding(.top, geometry.collapsedHeight + 5)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.94).combined(with: .opacity)
                    ))
            }
        }
        .onAppear {
            settings.adaptSlots(for: binanceService.selectedExchange)
        }
        .onChange(of: binanceService.selectedExchange) { newExchange in
            settings.adaptSlots(for: newExchange)
        }
    }

    // MARK: - Top Bar
    private var expandedTopBar: some View {
        Group {
            if geometry.hasNotch {
                HStack(spacing: 0) {
                    // Left Ear: Coin Title + Favorite Star
                    HStack(alignment: .center, spacing: 5) {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(binanceService.currentSymbol.baseAsset)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("/ " + binanceService.currentSymbol.effectiveQuote(for: binanceService.selectedExchange))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(.gray)
                        }
                        .id(binanceService.currentSymbol.symbol + "_top_sym")
                        .transition(.opacity)
                        if !binanceService.isInvalidSymbol {
                            favoriteStarButton
                        }
                    }
                    .padding(.leading, 14)
                    .frame(width: (geometry.expandedWidth - geometry.notchWidth) / 2, height: 22, alignment: .leading)
                    .offset(y: 2)

                    // Center: Gap matching physical camera notch
                    Color.clear
                        .frame(width: geometry.notchWidth, height: geometry.collapsedHeight)

                    // Right Ear: Action Tools
                    HStack(spacing: 6) {
                        if !binanceService.isInvalidSymbol {
                            alertButton
                        }
                        customizeGridButton
                        searchButton
                    }
                    .padding(.trailing, 14)
                    .frame(width: (geometry.expandedWidth - geometry.notchWidth) / 2, height: 22, alignment: .trailing)
                }
                .frame(height: geometry.collapsedHeight)
            } else {
                HStack(alignment: .center) {
                    HStack(alignment: .center, spacing: 5) {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(binanceService.currentSymbol.baseAsset)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("/ " + binanceService.currentSymbol.effectiveQuote(for: binanceService.selectedExchange))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(.gray)
                        }
                        .id(binanceService.currentSymbol.symbol + "_top_sym_nonnotch")
                        .transition(.opacity)
                        if !binanceService.isInvalidSymbol {
                            favoriteStarButton
                        }
                    }
                    .padding(.leading, 14)
                    .offset(y: 2)

                    Spacer()

                    HStack(spacing: 6) {
                        if !binanceService.isInvalidSymbol {
                            alertButton
                        }
                        customizeGridButton
                        searchButton
                    }
                    .padding(.trailing, 14)
                }
                .frame(height: geometry.collapsedHeight)
            }
        }
    }

    private var favoriteStarButton: some View {
        let isFav = settings.isFavorite(binanceService.currentSymbol.symbol)
        return Button {
            if isFav {
                _ = withAnimation(.spring(response: 0.25, dampingFraction: 0.72)) {
                    settings.toggleFavorite(binanceService.currentSymbol.symbol)
                }
                withAnimation(.spring(response: 0.16, dampingFraction: 0.70)) {
                    starScale = 0.90
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.75)) {
                        starScale = 1.0
                    }
                }
            } else {
                let success = settings.toggleFavorite(binanceService.currentSymbol.symbol)
                if success {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.65)) {
                        starScale = 1.16
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.72)) {
                            starScale = 1.0
                        }
                    }
                } else {
                    triggerFavoritesFullFeedback()
                }
            }
        } label: {
            Image(systemName: isFav ? "star.fill" : "star")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(isFav ? .white : (isStarHovered ? .white.opacity(0.70) : .white.opacity(0.35)))
                .scaleEffect(starScale)
                .offset(x: starShake)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isStarHovered = hovering
            }
        }
        .help(isFav ? "Remove from Favorites" : "Add to Favorites (Max 9)")
    }

    private func triggerFavoritesFullFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)

        withAnimation(.easeInOut(duration: 0.045).repeatCount(3, autoreverses: true)) {
            starShake = 2.5
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            starShake = 0
        }

        dismissToastTask?.cancel()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            isFavoritesFullAlertShowing = true
        }
        dismissToastTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                isFavoritesFullAlertShowing = false
            }
        }
    }

    private var alertButton: some View {
        let hasAlert = alertManager.hasActiveAlert(for: binanceService.currentSymbol.symbol)
        return Button {
            if !controller.isAlertShowing {
                controller.isCustomizingGrid = false
                controller.isCustomInputShowing = false
            }
            controller.isAlertShowing.toggle()
        } label: {
            Image(systemName: hasAlert ? "bell.badge.fill" : "bell.fill")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(.white.opacity(isAlertHovered || controller.isAlertShowing ? 1.0 : 0.8))
                .frame(width: 22, height: 22)
                .background(
                    LinearGradient(
                        colors: controller.isAlertShowing
                            ? [Color.white.opacity(0.24), Color.white.opacity(0.15)]
                            : isAlertHovered
                                ? [Color.white.opacity(0.18), Color.white.opacity(0.10)]
                                : [Color.white.opacity(0.12), Color.white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            controller.isAlertShowing
                                ? Color.white.opacity(0.35)
                                : isAlertHovered
                                    ? Color.white.opacity(0.25)
                                    : Color.white.opacity(0.15),
                            lineWidth: 0.8
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isAlertHovered = hovering
            }
        }
        .help(hasAlert ? "Manage Price Alerts (Active)" : "Set Price Alert")
        .popover(isPresented: $controller.isAlertShowing, arrowEdge: .bottom) {
            PriceAlertPopover(
                alertManager: alertManager,
                binanceService: binanceService,
                isPresented: $controller.isAlertShowing
            )
        }
    }

    private var customizeGridButton: some View {
        Button {
            if !controller.isCustomizingGrid {
                controller.isCustomInputShowing = false
                controller.isAlertShowing = false
            }
            controller.isCustomizingGrid.toggle()
        } label: {
            Image(systemName: "pencil")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(.white.opacity(isPencilHovered || controller.isCustomizingGrid ? 1.0 : 0.8))
                .frame(width: 22, height: 22)
                .background(
                    LinearGradient(
                        colors: controller.isCustomizingGrid
                            ? [Color.white.opacity(0.24), Color.white.opacity(0.15)]
                            : isPencilHovered
                                ? [Color.white.opacity(0.18), Color.white.opacity(0.10)]
                                : [Color.white.opacity(0.12), Color.white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            controller.isCustomizingGrid
                                ? Color.white.opacity(0.35)
                                : isPencilHovered
                                    ? Color.white.opacity(0.25)
                                    : Color.white.opacity(0.15),
                            lineWidth: 0.8
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isPencilHovered = hovering
            }
        }
        .help("Customize Stats Grid")
        .popover(isPresented: $controller.isCustomizingGrid, arrowEdge: .bottom) {
            CustomizationPopover(settings: settings, exchange: binanceService.selectedExchange)
        }
    }

    private var searchButton: some View {
        Button {
            if !controller.isCustomInputShowing {
                controller.isCustomizingGrid = false
                controller.isAlertShowing = false
            }
            controller.isCustomInputShowing.toggle()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(.white.opacity(isSearchHovered || controller.isCustomInputShowing ? 1.0 : 0.8))
                .frame(width: 22, height: 22)
                .background(
                    LinearGradient(
                        colors: controller.isCustomInputShowing
                            ? [Color.white.opacity(0.24), Color.white.opacity(0.15)]
                            : isSearchHovered
                                ? [Color.white.opacity(0.18), Color.white.opacity(0.10)]
                                : [Color.white.opacity(0.12), Color.white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            controller.isCustomInputShowing
                                ? Color.white.opacity(0.35)
                                : isSearchHovered
                                    ? Color.white.opacity(0.25)
                                    : Color.white.opacity(0.15),
                            lineWidth: 0.8
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isSearchHovered = hovering
            }
        }
        .help("Search & Switch Pair")
        .popover(isPresented: $controller.isCustomInputShowing, arrowEdge: .bottom) {
            SearchPairPopover(
                binanceService: binanceService,
                settings: settings,
                isPresented: $controller.isCustomInputShowing
            )
        }
    }

    // MARK: - Invalid Symbol Error View
    private var invalidSymbolErrorView: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 4)

            // 1. Error Announcement
            VStack(spacing: 3) {
                Text("Pair Not Found")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text("\"\(binanceService.currentSymbol.baseAsset)/\(binanceService.currentSymbol.effectiveQuote(for: binanceService.selectedExchange))\" is not listed on \(binanceService.selectedExchange.displayName)")
                    .font(.system(size: 10.5, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }

            // 2. Unified Action Shelf: [ ⤺ Back ] │ [ ARB ] [ PUMP ] [ NEAR ] ...
            HStack(spacing: 7) {
                // Back Button
                Button {
                    binanceService.revertToLastValidSymbol()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 9, weight: .bold))
                        Text("Back")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(
                        LinearGradient(
                            colors: isBackHovered
                                ? [Color.white.opacity(0.25), Color.white.opacity(0.16)]
                                : [Color.white.opacity(0.16), Color.white.opacity(0.09)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(
                                isBackHovered
                                    ? Color.white.opacity(0.35)
                                    : Color.white.opacity(0.18),
                                lineWidth: 0.8
                            )
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isBackHovered = hovering
                    }
                }

                // Subtle separator
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, 1)

                // Favorite / Popular Coin Pills
                ForEach(quickSwitchSymbols, id: \.self) { sym in
                    Button {
                        binanceService.selectSymbol(sym)
                    } label: {
                        Text(sym.baseAsset)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(
                                hoveredPillSymbol == sym.symbol
                                    ? Color.white.opacity(0.20)
                                    : Color.white.opacity(0.08)
                            )
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(
                                        hoveredPillSymbol == sym.symbol
                                            ? Color.white.opacity(0.32)
                                            : Color.white.opacity(0.12),
                                        lineWidth: 0.8
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.12)) {
                            hoveredPillSymbol = hovering ? sym.symbol : nil
                        }
                    }
                }
            }

            Spacer(minLength: 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .transition(.opacity)
    }

    private var quickSwitchSymbols: [CryptoSymbol] {
        let favs = settings.favorites.compactMap { fav in
            CryptoSymbol.presets.first(where: { $0.symbol == fav }) ?? CryptoSymbol.from(rawInput: fav, defaultExchange: binanceService.selectedExchange)
        }.filter { $0.symbol != binanceService.currentSymbol.symbol }

        if !favs.isEmpty {
            return Array(favs.prefix(6))
        } else {
            return Array(CryptoSymbol.presets.filter { $0.symbol != binanceService.currentSymbol.symbol }.prefix(5))
        }
    }

    private var flashColor: Color {
        if let direction = binanceService.flashDirection {
            return direction == .up ? Color.green : Color.red
        }
        return .white
    }

    private var favoritesFullToast: some View {
        Text("Favorites Full (9/9)")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .tracking(0.3)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color(white: 0.12).opacity(0.96))
                    .shadow(color: .black.opacity(0.60), radius: 10, y: 4)
            )
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.32), Color.white.opacity(0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            )
    }
}
