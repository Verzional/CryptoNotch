import SwiftUI
import AppKit

/// Ultra-minimalist glass popover card for creating and managing price threshold alerts.
@MainActor
public struct PriceAlertPopover: View {
    @ObservedObject var alertManager: AlertManager
    @ObservedObject var binanceService: BinanceService
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
        let cleaned = targetPriceText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }

    private var effectiveDirection: AlertDirection {
        guard let entered = parsedEnteredPrice, currentPrice > 0 else {
            return .above
        }
        return entered >= currentPrice ? .above : .below
    }

    private func isPillSelected(_ pct: Double) -> Bool {
        guard currentPrice > 0, let entered = parsedEnteredPrice else { return false }
        let calculated = currentPrice * (1.0 + pct)
        let formatted = PriceFormatterCache.shared.format(calculated).replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
        let enteredFormatted = PriceFormatterCache.shared.format(entered).replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
        return formatted == enteredFormatted
    }

    private var pricePlaceholder: String {
        if let ticker = binanceService.ticker {
            return PriceFormatterCache.shared.format(ticker.price).replacingOccurrences(of: "$", with: "")
        }
        return "0.00"
    }

    public var body: some View {
        let symbol = binanceService.currentSymbol
        let alerts = alertManager.allAlerts(for: symbol.symbol)

        VStack(alignment: .leading, spacing: 9) {
            // Header
            HStack(alignment: .center) {
                Text("Price Alert")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
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

            // Quick Percentage Chips (1:1 replica of HUD change pill)
            if currentPrice > 0 {
                HStack(spacing: 0) {
                    let pcts = [-0.05, -0.02, 0.02, 0.05]
                    ForEach(Array(pcts.enumerated()), id: \.element) { index, pct in
                        QuickPercentagePill(
                            pct: pct,
                            isSelected: isPillSelected(pct)
                        ) {
                            let calculated = currentPrice * (1.0 + pct)
                            targetPriceText = PriceFormatterCache.shared.format(calculated).replacingOccurrences(of: "$", with: "")
                            isFieldFocused = true
                        }
                        if index < pcts.count - 1 {
                            Spacer(minLength: 2)
                        }
                    }
                }
            }

            if let err = inputError {
                Text(err)
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundColor(.red.opacity(0.9))
            }

            Divider()
                .background(Color.white.opacity(0.08))

            // Active Alerts (Always present for stable window sizing)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("ACTIVE ALERTS")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(.gray)
                        .tracking(0.5)

                    Spacer()

                    if alerts.contains(where: { $0.isTriggered }) {
                        Button {
                            alertManager.clearTriggeredAlerts()
                        } label: {
                            Text("Clear Triggered")
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if alerts.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white.opacity(0.28))

                        Text("No alerts set")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.35))

                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4.5)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
                    )
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 3) {
                            ForEach(alerts) { alert in
                                AlertRowView(alert: alert) {
                                    alertManager.removeAlert(id: alert.id)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 85)
                }
            }
        }
        .padding(11)
        .frame(width: 230)
        .preferredColorScheme(.dark)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                isFieldFocused = true
            }
        }
    }


    private func createAlert() {
        let cleaned = targetPriceText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let target = Double(cleaned), target > 0 else {
            inputError = "Enter a valid price"
            return
        }

        inputError = nil
        alertManager.addAlert(
            symbol: binanceService.currentSymbol.symbol,
            exchange: binanceService.selectedExchange,
            targetPrice: target,
            direction: effectiveDirection
        )

        targetPriceText = ""
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
                    .font(.system(size: 9, weight: .bold))
                Text(pct > 0 ? "+\(Int(pct * 100))%" : "\(Int(pct * 100))%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 6)
            .frame(height: 20)
            .fixedSize(horizontal: true, vertical: false)
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
        .buttonStyle(QuickPillButtonStyle())
        .focusable(false)
        .layoutPriority(1)
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
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)

            Spacer()

            if alert.isTriggered {
                Text("Fired")
                    .font(.system(size: 7.5, weight: .bold, design: .rounded))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(0.18))
                    .clipShape(Capsule())
            }

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
        .padding(.horizontal, 6)
        .padding(.vertical, 3.5)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(alert.isTriggered ? 0.03 : 0.06))
        )
    }
}

