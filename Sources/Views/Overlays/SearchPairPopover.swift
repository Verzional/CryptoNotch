import SwiftUI

/// Popover sheet for searching coin symbols and picking from pinned favorites.
public struct SearchPairPopover: View {
    @ObservedObject var binanceService: BinanceService
    @ObservedObject var settings: SettingsModel
    @Binding var isPresented: Bool

    @State private var customSymbolText: String = ""
    @State private var draggedSymbol: String? = nil
    @State private var dragLocation: CGPoint = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var pillFrames: [String: CGRect] = [:]
    @FocusState private var isSearchFocused: Bool

    public init(
        binanceService: BinanceService,
        settings: SettingsModel,
        isPresented: Binding<Bool>
    ) {
        self.binanceService = binanceService
        self.settings = settings
        self._isPresented = isPresented
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header (clean, no duplicate search icon)
            HStack(alignment: .center) {
                Text("Switch Pair")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Spacer()

                Text("\(binanceService.currentSymbol.baseAsset)/\(binanceService.currentSymbol.effectiveQuote(for: binanceService.selectedExchange))")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(.white.opacity(0.75))
                    .clipShape(Capsule())
            }

            // Exchange Segmented Selector
            HStack(spacing: 5) {
                ForEach(CryptoExchange.allCases) { exchange in
                    let isSelected = binanceService.selectedExchange == exchange
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                            binanceService.selectExchange(exchange)
                            settings.adaptSlots(for: exchange)
                        }
                    } label: {
                        Text(exchange.displayName)
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                            .foregroundColor(isSelected ? .white : .white.opacity(0.60))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(
                                isSelected
                                    ? Color.white.opacity(0.22)
                                    : Color.white.opacity(0.06)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(
                                        isSelected
                                            ? Color.white.opacity(0.35)
                                            : Color.white.opacity(0.08),
                                        lineWidth: 0.8
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Sleek Search Input Bar
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)

                TextField("Symbol (e.g. SOL, SUI)", text: $customSymbolText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .focused($isSearchFocused)
                    .onSubmit {
                        commitCustomSymbol()
                    }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSearchFocused ? Color.white.opacity(0.3) : Color.white.opacity(0.12), lineWidth: 0.8)
            )

            if binanceService.isInvalidSymbol {
                Text("Symbol not found on \(binanceService.selectedExchange.displayName)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
                    .padding(.horizontal, 2)
                    .transition(.opacity)
            }

            // Favorites Grid (Dynamic user favorites, max 9, interactive drag-and-drop reordering)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("FAVORITES")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundColor(.gray)
                        .tracking(0.5)

                    Spacer()

                    Text("\(settings.favorites.count)/9")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.7))
                }

                if settings.favorites.isEmpty {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 28, height: 28)
                            Image(systemName: "star.fill")
                                .font(.system(size: 13))
                                .foregroundColor(Color.white.opacity(0.75))
                        }

                        VStack(spacing: 3) {
                            Text("No Favorites Yet")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))

                            Text("Click ★ on the notch to pin coins here")
                                .font(.system(size: 9.5))
                                .foregroundColor(.white.opacity(0.45))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    )
                } else {
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
                    ZStack {
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(settings.favorites, id: \.self) { favString in
                                let preset = CryptoSymbol.from(rawInput: favString, defaultExchange: binanceService.selectedExchange)
                                let isCurrent = preset.symbol == binanceService.currentSymbol.symbol
                                let isBeingDragged = draggedSymbol == favString

                                FavoritePillView(
                                    symbol: preset,
                                    isCurrent: isCurrent
                                )
                                .opacity(isBeingDragged ? 0.22 : 1.0)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: PillFramePreference.self,
                                            value: [favString: geo.frame(in: .named("FavoritesGrid"))]
                                        )
                                    }
                                )
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0, coordinateSpace: .named("FavoritesGrid"))
                                        .onChanged { value in
                                            let dist = hypot(value.translation.width, value.translation.height)
                                            if dist > 3 {
                                                if draggedSymbol == nil {
                                                    draggedSymbol = favString
                                                    let startFrame = pillFrames[favString] ?? .zero
                                                    if startFrame != .zero {
                                                        dragOffset = CGSize(
                                                            width: value.startLocation.x - startFrame.midX,
                                                            height: value.startLocation.y - startFrame.midY
                                                        )
                                                    } else {
                                                        dragOffset = .zero
                                                    }
                                                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                                                }
                                                dragLocation = value.location

                                                // Find if hovering over another pill's slot
                                                if let target = pillFrames.first(where: { $0.key != favString && $0.value.contains(value.location) })?.key,
                                                   let from = settings.favorites.firstIndex(of: favString),
                                                   let to = settings.favorites.firstIndex(of: target),
                                                   from != to {
                                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                                                        settings.moveFavorite(from: from, to: to)
                                                    }
                                                }
                                            }
                                        }
                                        .onEnded { value in
                                            let dist = hypot(value.translation.width, value.translation.height)
                                            if dist < 4 {
                                                // Quick tap without drag -> select symbol immediately
                                                binanceService.selectSymbol(preset)
                                                customSymbolText = ""
                                                isPresented = false
                                            }
                                            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                                draggedSymbol = nil
                                            }
                                        }
                                )
                            }
                        }

                        // Floating dragged pill follower
                        if let dragged = draggedSymbol {
                            let preset = CryptoSymbol.from(rawInput: dragged, defaultExchange: binanceService.selectedExchange)
                            let size = pillFrames[dragged]?.size ?? CGSize(width: 71, height: 26)
                            FavoritePillView(
                                symbol: preset,
                                isCurrent: preset.symbol == binanceService.currentSymbol.symbol
                            )
                            .frame(width: size.width, height: size.height)
                            .scaleEffect(1.08)
                            .shadow(color: Color.black.opacity(0.55), radius: 8, x: 0, y: 4)
                            .position(
                                x: dragLocation.x - dragOffset.width,
                                y: dragLocation.y - dragOffset.height
                            )
                            .allowsHitTesting(false)
                            .transition(.identity)
                        }
                    }
                    .coordinateSpace(name: "FavoritesGrid")
                    .onPreferenceChange(PillFramePreference.self) { frames in
                        self.pillFrames = frames
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 285)
        .preferredColorScheme(.dark)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
    }

    private func commitCustomSymbol() {
        guard !customSymbolText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let sym = CryptoSymbol.from(rawInput: customSymbolText, defaultExchange: binanceService.selectedExchange)
        binanceService.selectSymbol(sym)
        customSymbolText = ""
        isPresented = false
    }
}

// MARK: - PreferenceKey for tracking pill frame geometry
private struct PillFramePreference: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Favorite Pill View
private struct FavoritePillView: View {
    let symbol: CryptoSymbol
    let isCurrent: Bool

    @State private var isHovered: Bool = false

    var body: some View {
        Text(symbol.baseAsset)
            .font(.system(size: 11, weight: isCurrent ? .bold : .medium, design: .rounded))
            .foregroundColor(isCurrent ? .white : .white.opacity(isHovered ? 1.0 : 0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                isCurrent
                    ? Color.white.opacity(isHovered ? 0.26 : 0.20)
                    : Color.white.opacity(isHovered ? 0.12 : 0.07)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        isCurrent
                            ? Color.white.opacity(0.35)
                            : (isHovered ? Color.white.opacity(0.24) : Color.white.opacity(0.1)),
                        lineWidth: 0.8
                    )
            )
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
            .help("Drag to reorder • Click to switch")
    }
}
