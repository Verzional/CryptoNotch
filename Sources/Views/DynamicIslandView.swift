import SwiftUI

/// Main orchestrator view for the Dynamic Island, hosting collapsed and expanded views with spring transitions and bezel clipping.
public struct DynamicIslandView: View {
    @ObservedObject var controller: DynamicIslandController
    @ObservedObject var binanceService: BinanceService
    @ObservedObject var settings: SettingsModel

    private var geometry: NotchGeometry {
        controller.currentGeometry
    }

    public init(
        controller: DynamicIslandController,
        binanceService: BinanceService,
        settings: SettingsModel
    ) {
        self.controller = controller
        self.binanceService = binanceService
        self.settings = settings
    }

    public var body: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                if controller.isExpanded {
                    ExpandedNotchView(
                        geometry: geometry,
                        controller: controller,
                        binanceService: binanceService,
                        settings: settings
                    )
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .scale(scale: 0.94, anchor: .top))
                                .combined(with: .offset(y: -6)),
                            removal: .opacity
                                .combined(with: .scale(scale: 0.96, anchor: .top))
                        )
                    )
                } else {
                    CollapsedNotchView(
                        geometry: geometry,
                        binanceService: binanceService,
                        controller: controller
                    )
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .scale(scale: 0.95, anchor: .center)),
                            removal: .opacity
                        )
                    )
                }
            }
            .frame(
                width: controller.isExpanded ? geometry.expandedWidth : geometry.collapsedWidth,
                height: controller.isExpanded ? geometry.expandedHeight : geometry.collapsedHeight,
                alignment: .top
            )
            .background(
                NotchShape(bottomRadius: controller.isExpanded ? 20 : (geometry.hasNotch ? 10 : 12))
                    .fill(Color.black)
            )
            .overlay(
                NotchOutline(bottomRadius: controller.isExpanded ? 20 : (geometry.hasNotch ? 10 : 12))
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .clipShape(
                NotchShape(bottomRadius: controller.isExpanded ? 20 : (geometry.hasNotch ? 10 : 12))
            )
            .shadow(color: Color.black.opacity(controller.isExpanded ? 0.35 : 0.0), radius: controller.isExpanded ? 12 : 0, x: 0, y: controller.isExpanded ? 6 : 0)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        guard !controller.isCustomInputShowing, !controller.isCustomizingGrid else { return }
                        if abs(value.translation.width) >= abs(value.translation.height) {
                            if value.translation.width < -35 {
                                controller.cycleFavorite(direction: .next)
                            } else if value.translation.width > 35 {
                                controller.cycleFavorite(direction: .previous)
                            }
                        } else {
                            if value.translation.height > 25 && !controller.isExpanded {
                                controller.toggleExpansion()
                            } else if value.translation.height < -25 && controller.isExpanded && !settings.isPinned {
                                controller.toggleExpansion()
                            }
                        }
                    }
            )
        }
        .scaleEffect(
            x: settings.isNotchDisabled ? 0.001 : 1.0,
            y: 1.0,
            anchor: .center
        )
        .opacity(
            settings.isNotchDisabled
                ? 0.0
                : ((settings.stealthMode && !controller.isExpanded && !controller.isHovered) ? 0.0 : 1.0)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: settings.isNotchDisabled)
        .animation(.easeInOut(duration: 0.2), value: binanceService.flashDirection)
        .animation(.easeInOut(duration: 0.25), value: settings.stealthMode)
        .animation(.easeInOut(duration: 0.25), value: controller.isHovered)
    }
}
