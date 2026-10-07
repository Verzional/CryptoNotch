import SwiftUI

/// Popover sheet for customizing the 6 metrics in the stats grid, filtered to metrics available on the active exchange.
public struct CustomizationPopover: View {
    @ObservedObject var settings: SettingsModel
    public let exchange: CryptoExchange
    @State private var selectedSlotToCustomize: Int = 0
    @State private var selectedMetricCategory: MetricCategory = .all

    public init(settings: SettingsModel, exchange: CryptoExchange = .binance) {
        self.settings = settings
        self.exchange = exchange
    }

    public var body: some View {
        let slots = settings.effectiveGridSlots(for: exchange)
        VStack(alignment: .leading, spacing: 10) {
            // Header: Title + Reset Button
            HStack(alignment: .center) {
                Text("Customize Stats")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Spacer()

                Button {
                    settings.resetGridSlots(for: exchange)
                } label: {
                    Text("Reset")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            // Interactive 6-slot preview layout
            VStack(alignment: .leading, spacing: 4) {
                Text("TAP A SLOT TO EDIT")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundColor(.gray)
                    .tracking(0.5)

                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { idx in
                            slotPreviewButton(index: idx, metric: slots[idx])
                        }
                    }
                    HStack(spacing: 4) {
                        ForEach(3..<6, id: \.self) { idx in
                            slotPreviewButton(index: idx, metric: slots[idx])
                        }
                    }
                }
            }

            Divider().background(Color.white.opacity(0.10))

            // Metrics picker list filtered to metrics supported on the current exchange
            VStack(alignment: .leading, spacing: 6) {
                let alreadySelected = Set(slots)
                let availableMetrics = StatMetric.allCases.filter { metric in
                    metric.isAvailable(on: exchange) &&
                    !alreadySelected.contains(metric) &&
                    (selectedMetricCategory == .all || metric.category == selectedMetricCategory)
                }

                // Category capsules (only show categories that have supported metrics on this exchange)
                let availableCategories = MetricCategory.allCases.filter { cat in
                    cat == .all || StatMetric.allCases.contains { $0.category == cat && $0.isAvailable(on: exchange) }
                }

                HStack(spacing: 4) {
                    ForEach(availableCategories) { cat in
                        categoryFilterCapsule(cat)
                    }
                }

                if availableMetrics.isEmpty {
                    Text(selectedMetricCategory == .all ? "All available \(exchange.displayName) metrics are assigned" : "All available \(selectedMetricCategory.title) metrics are assigned")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(availableMetrics) { metric in
                                Button {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                        settings.updateGridSlot(at: selectedSlotToCustomize, to: metric)
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 5) {
                                                Text(metric.title)
                                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                    .foregroundColor(.white.opacity(0.90))

                                                if selectedMetricCategory == .all {
                                                    Text(metric.category.title)
                                                        .font(.system(size: 8, weight: .medium, design: .rounded))
                                                        .foregroundColor(.white.opacity(0.40))
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(Color.white.opacity(0.06))
                                                        .clipShape(Capsule())
                                                }
                                            }

                                            Text(metric.shortDescription)
                                                .font(.system(size: 9, weight: .regular))
                                                .foregroundColor(.white.opacity(0.5))
                                                .lineLimit(1)
                                        }

                                        Spacer()

                                        Image(systemName: "plus.circle")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.white.opacity(0.40))
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5.5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color.white.opacity(0.06))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }
        }
        .padding(12)
        .frame(width: 268)
        .preferredColorScheme(.dark)
        .onAppear {
            settings.adaptSlots(for: exchange)
        }
    }

    private func categoryFilterCapsule(_ cat: MetricCategory) -> some View {
        let isSelected = selectedMetricCategory == cat
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedMetricCategory = cat
            }
        } label: {
            Text(cat.title)
                .font(.system(size: 9.5, weight: isSelected ? .bold : .medium, design: .rounded))
                .foregroundColor(isSelected ? .white : .white.opacity(0.60))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    isSelected
                        ? Color.white.opacity(0.20)
                        : Color.white.opacity(0.06)
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected
                                ? Color.white.opacity(0.35)
                                : Color.white.opacity(0.10),
                            lineWidth: 0.8
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func slotPreviewButton(index: Int, metric: StatMetric) -> some View {
        let isSelectedSlot = selectedSlotToCustomize == index
        let isAvailable = metric.isAvailable(on: exchange)
        return Button {
            selectedSlotToCustomize = index
        } label: {
            VStack(spacing: 1.5) {
                HStack(spacing: 2) {
                    Text("Slot \(index + 1)")
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundColor(isSelectedSlot ? .white.opacity(0.9) : .gray)
                    if !isAvailable {
                        Text("• N/A")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.orange)
                    }
                }
                Text(metric.title)
                    .font(.system(size: 9.5, weight: isSelectedSlot ? .bold : .medium, design: .monospaced))
                    .foregroundColor(isAvailable ? (isSelectedSlot ? .white : .white.opacity(0.8)) : .white.opacity(0.4))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelectedSlot ? Color.white.opacity(0.20) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(
                        isSelectedSlot
                            ? Color.white.opacity(0.45)
                            : (isAvailable ? Color.white.opacity(0.12) : Color.orange.opacity(0.35)),
                        lineWidth: isSelectedSlot ? 1.2 : 0.8
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
