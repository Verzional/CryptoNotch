import SwiftUI

/// Compact ear-to-ear notch layout when the dynamic island is collapsed.
public struct CollapsedNotchView: View {
    public let geometry: NotchGeometry
    @ObservedObject var binanceService: BinanceService
    @ObservedObject var controller: DynamicIslandController

    public init(
        geometry: NotchGeometry,
        binanceService: BinanceService,
        controller: DynamicIslandController
    ) {
        self.geometry = geometry
        self.binanceService = binanceService
        self.controller = controller
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Left Ear: Symbol
            HStack {
                Text(binanceService.currentSymbol.baseAsset)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .id(binanceService.currentSymbol.symbol + "_collapsed_sym")
                    .transition(.opacity)
            }
            .frame(width: geometry.earWidth, alignment: .center)

            // Center: Gap matching physical camera notch
            if geometry.hasNotch {
                Color.clear
                    .frame(width: geometry.notchWidth, height: geometry.collapsedHeight)
            } else {
                Spacer(minLength: 8)
            }

            // Right Ear: Price or Error State
            HStack(spacing: 4) {
                if binanceService.isInvalidSymbol {
                    Text("Not Found")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                } else if let ticker = binanceService.ticker {
                    Text(ticker.formattedPrice)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(flashColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: ticker.price)
                } else {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 52, height: 13)
                        .skeletonPulse()
                }
            }
            .id(binanceService.currentSymbol.symbol + "_collapsed_price")
            .transition(.opacity)
            .frame(width: geometry.earWidth, alignment: .center)
        }
        .frame(width: geometry.collapsedWidth, height: geometry.collapsedHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            controller.toggleExpansion()
        }
    }

    private var flashColor: Color {
        if let direction = binanceService.flashDirection {
            return direction == .up ? Color.green : Color.red
        }
        return .white
    }
}
