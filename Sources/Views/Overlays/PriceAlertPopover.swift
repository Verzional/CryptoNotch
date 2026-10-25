import SwiftUI
import AppKit

/// Ultra-minimalist glass popover card for creating and managing price threshold alerts.
/// Engineered with a stable frame geometry to eliminate OS-level window resize jitter.
@MainActor
public struct PriceAlertPopover: View {
    @ObservedObject var alertManager: AlertManager
    let binanceService: BinanceService
    @Binding var isPresented: Bool

    @State private var targetPriceText: String = ""
    @State private var inputError: String? = nil
    @FocusState private var isFieldFocused: Bool

    public init(
        alertManager: AlertManager? = nil,
        binanceService: BinanceService,
        isPresented: Binding<Bool>
    ) {
        self.alertManager = alertManager ?? .shared
        self.binanceService = binanceService
        self._isPresented = isPresented
    }

    private var currentPrice: Double {
        binanceService.ticker?.price ?? 0.0
    }

    private var parsedEnteredPrice: Double? {
        let trimmed = targetPriceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("%") || trimmed.hasPrefix("+") || (trimmed.hasPrefix("-") && Double(trimmed) != nil) {
            let cleaned = trimmed
                .replacingOccurrences(of: "%", with: "")
                .replacingOccurrences(of: "+", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let pctValue = Double(cleaned), currentPrice > 0 {
                let pct = pctValue / 100.0
                return roundedPrice(for: pct)
            }
        }
        let cleaned = targetPriceText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }

    private var effectiveDirection: AlertDirection {
        guard let entered = parsedEnteredPrice, currentPrice > 0 else {
            return .above
        }
        return entered >= currentPrice ? .above : .below
    }

    private var priceDecimals: Int {
        binanceService.ticker?.priceDecimals ?? TickerData.standardDecimalPlaces(for: currentPrice)
    }

    private func roundedPrice(for pct: Double) -> Double {
        guard currentPrice > 0 else { return 0 }
        let calculated = currentPrice * (1.0 + pct)
        let factor = pow(10.0, Double(priceDecimals))
        return (calculated * factor).rounded() / factor
    }

    private func formattedCalculatedPrice(for pct: Double) -> String {
        let rounded = roundedPrice(for: pct)
        return PriceFormatterCache.shared.format(rounded, decimals: priceDecimals)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
    }

    private func isPillSelected(_ pct: Double) -> Bool {
        guard currentPrice > 0, let entered = parsedEnteredPrice else { return false }
        let rounded = roundedPrice(for: pct)
        let factor = pow(10.0, Double(priceDecimals))
        return abs(entered - rounded) < (1.0 / (factor * 2.0))
    }

    private var pricePlaceholder: String {
        if let ticker = binanceService.ticker {
            return PriceFormatterCache.shared.format(ticker.price, decimals: priceDecimals)
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")
        }
        return "0.00"
    }

    public var body: some View {
        let symbol = binanceService.currentSymbol
        let alerts = alertManager.allAlerts(for: symbol.symbol)

        VStack(alignment: .leading, spacing: 10) {
            // Top Controls Section (Protected from vertical compression during window resize)
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(alignment: .center) {
                    Text("Price Alert")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            alertManager.removeAllAlerts(for: symbol.symbol)
                        }
                    } label: {
                        Text("Clear")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .contentTransition(.identity)
                            .foregroundColor(alerts.isEmpty ? .white.opacity(0.35) : .white.opacity(0.7))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(alerts.isEmpty ? 0.05 : 0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(alerts.isEmpty)
                }

                // Input Bar (Exact 1:1 match to SearchPairPopover)
                HStack(spacing: 7) {
                    Text("$")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)

                    TextField(pricePlaceholder, text: $targetPriceText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .focused($isFieldFocused)
                        .onSubmit {
                            createAlert()
                        }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isFieldFocused ? Color.white.opacity(0.3) : Color.white.opacity(0.12), lineWidth: 0.8)
                )

                // Quick Percentage Chips (4 full-width segmented chips)
                if currentPrice > 0 {
                    HStack(spacing: 7) {
                        ForEach([-0.05, -0.02, 0.02, 0.05], id: \.self) { pct in
                            QuickPercentagePill(
                                pct: pct,
                                isSelected: isPillSelected(pct)
                            ) {
                                targetPriceText = formattedCalculatedPrice(for: pct)
                                isFieldFocused = true
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if let err = inputError {
                    Text(err)
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundColor(.red.opacity(0.9))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)

            // Dynamic Alerts Section (Hugs content: 0 alerts = zero extra height)
            if !alerts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("ACTIVE ALERTS")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundColor(.gray)
                            .tracking(0.5)

                        Spacer()

                        Text("\(alerts.count)/5")
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .contentTransition(.identity)
                            .foregroundColor(.gray.opacity(0.7))
                    }

                    VStack(spacing: 3) {
                        ForEach(alerts) { alert in
                            AlertRowView(alert: alert) {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    alertManager.removeAlert(id: alert.id)
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .identity,
                                removal: .opacity.combined(with: .scale(scale: 0.95))
                            ))
                        }
                    }
                }
                .transition(.asymmetric(
                    insertion: .identity,
                    removal: .opacity
                ))
            }
        }
        .padding(12)
        .frame(width: 285, alignment: .top)
        .preferredColorScheme(.dark)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                isFieldFocused = true
            }
        }
    }

    private func createAlert() {
        let symbol = binanceService.currentSymbol
        let alerts = alertManager.allAlerts(for: symbol.symbol)
        if alerts.count >= 5 {
            inputError = "Maximum 5 alerts"
            return
        }

        guard let target = parsedEnteredPrice, target > 0 else {
            inputError = "Enter a valid price"
            return
        }

        inputError = nil
        _ = alertManager.addAlert(
            symbol: symbol.symbol,
            exchange: binanceService.selectedExchange,
            targetPrice: target,
            direction: effectiveDirection,
            decimals: priceDecimals
        )
        targetPriceText = ""

        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }
}

// MARK: - Quick Pill Button Style
private struct QuickPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1.0)
    }
}

// MARK: - Quick Percentage Pill View
private struct QuickPercentagePill: View {
    let pct: Double
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        let tintColor: Color = pct >= 0 ? .green : .red
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: pct >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 8.5, weight: .bold))
                Text(pct > 0 ? "+\(Int(pct * 100))%" : "\(Int(pct * 100))%")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .background(
                ZStack {
                    Color.black.opacity(0.85)
                    tintColor.opacity(isHovered ? 0.35 : (isSelected ? 0.30 : 0.22))
                }
            )
            .foregroundColor(tintColor)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isSelected
                            ? tintColor.opacity(0.40)
                            : (isHovered ? tintColor.opacity(0.25) : Color.clear),
                        lineWidth: 0.8
                    )
            )
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(QuickPillButtonStyle())
        .focusable(false)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Alert Row View
private struct AlertRowView: View {
    let alert: PriceAlert
    let onDelete: () -> Void

    @State private var isDeleteHovered: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: alert.direction == .above ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(alert.direction == .above ? .green : .red)

            Text(alert.formattedTargetPrice)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundColor(isDeleteHovered ? .white : .white.opacity(0.40))
                    .frame(width: 16, height: 16)
                    .background(isDeleteHovered ? Color.white.opacity(0.15) : Color.clear)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isDeleteHovered = hovering
                }
            }
            .help("Delete alert")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        )
    }
}
