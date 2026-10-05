import AppKit
import SwiftUI
import Combine

/// Custom NSPanel configured to float above full-screen windows (e.g. YouTube in full-screen)
/// and anchor to the macOS camera notch or top bezel.
public final class DynamicIslandPanel: NSPanel {
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .screenSaver
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.acceptsMouseMovedEvents = true
    }

    override public var canBecomeKey: Bool {
        return true
    }

    override public var canBecomeMain: Bool {
        return false
    }

    override public func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

/// Represents geometry for the display notch and Dynamic Island dimensions.
public struct NotchGeometry: Equatable {
    public let hasNotch: Bool
    public let notchWidth: CGFloat
    public let notchHeight: CGFloat
    public let notchCenter: CGFloat
    public let earWidth: CGFloat

    public init(
        hasNotch: Bool,
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        notchCenter: CGFloat,
        earWidth: CGFloat = 110
    ) {
        self.hasNotch = hasNotch
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.notchCenter = notchCenter
        self.earWidth = earWidth
    }

    public var collapsedWidth: CGFloat {
        if hasNotch {
            return notchWidth + (earWidth * 2)
        } else {
            return 240
        }
    }

    public var collapsedHeight: CGFloat {
        if hasNotch {
            return notchHeight + 1
        } else {
            return 33
        }
    }

    public var expandedWidth: CGFloat {
        return max(collapsedWidth, 420)
    }

    public var expandedHeight: CGFloat {
        return collapsedHeight + 126
    }

    public static func current(for screen: NSScreen? = nil) -> NotchGeometry {
        let targetScreen = screen ?? NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil }) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = targetScreen else {
            return NotchGeometry(hasNotch: false, notchWidth: 0, notchHeight: 32, notchCenter: 756)
        }

        let frame = screen.frame
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           left.width > 0, right.width > 0 {
            let width = right.minX - left.maxX
            let height = max(left.height, screen.safeAreaInsets.top)
            let center = (left.maxX + right.minX) / 2.0
            return NotchGeometry(
                hasNotch: true,
                notchWidth: width,
                notchHeight: height,
                notchCenter: center,
                earWidth: 110
            )
        } else {
            return NotchGeometry(
                hasNotch: false,
                notchWidth: 0,
                notchHeight: 32,
                notchCenter: frame.midX,
                earWidth: 110
            )
        }
    }
}

/// Direction of transition animation when cycling through favorite cryptocurrency pairs.
public enum CycleDirection: String, CaseIterable, Equatable {
    case next
    case previous
}

/// Hosting view that allows mouse events outside the active Dynamic Island area to pass through to underlying windows.
final class DynamicIslandHostingView<Content: View>: NSHostingView<Content> {
    var isExpandedProvider: () -> Bool = { false }
    var isCollapsingProvider: () -> Bool = { false }
    var isHoveredProvider: () -> Bool = { false }
    var isCustomInputShowingProvider: () -> Bool = { false }
    var isCustomizingGridProvider: () -> Bool = { false }
    var isNotchDisabledProvider: () -> Bool = { false }
    var onHoverChanged: ((Bool) -> Void)?
    var onSwipeGesture: ((CycleDirection) -> Void)?
    var onJumpToFavorite: ((Int) -> Void)?
    var onEscape: (() -> Void)?
    private var trackingAreaRef: NSTrackingArea?
    private var hasTriggeredInCurrentSwipe: Bool = false
    private var accumulatedDeltaX: CGFloat = 0
    private var lastSwipeTriggerTime: TimeInterval = 0

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeAlways,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingAreaRef = area
    }

    func activeRect() -> NSRect {
        guard let window = self.window, let screen = window.screen else {
            let geometry = NotchGeometry.current()
            let isExpanded = isExpandedProvider() || isCollapsingProvider()
            let width = isExpanded ? geometry.expandedWidth : geometry.collapsedWidth
            let height = isExpanded ? geometry.expandedHeight : geometry.collapsedHeight
            let minX = (bounds.width - width) / 2
            let slopX: CGFloat = isExpanded ? 0 : 8
            let slopY: CGFloat = isExpanded ? 0 : 10
            return NSRect(x: minX - slopX, y: 0, width: width + (slopX * 2), height: height + slopY)
        }
        let geometry = NotchGeometry.current(for: screen)
        let isExpanded = isExpandedProvider() || isCollapsingProvider()
        let width = isExpanded ? geometry.expandedWidth : geometry.collapsedWidth
        let height = isExpanded ? geometry.expandedHeight : geometry.collapsedHeight
        let minX = (bounds.width - width) / 2
        let slopX: CGFloat = isExpanded ? 0 : 8
        let slopY: CGFloat = isExpanded ? 0 : 10
        return NSRect(x: minX - slopX, y: 0, width: width + (slopX * 2), height: height + slopY)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if isNotchDisabledProvider() {
            return nil
        }
        let localPoint = convert(point, from: superview)
        if !activeRect().contains(localPoint) {
            return nil
        }
        return super.hitTest(point) ?? self
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        checkHover(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        checkHover(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHovered(false)
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        if activeRect().contains(localPoint), let window = self.window, !window.isKeyWindow {
            window.makeKey()
            window.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard !isCustomInputShowingProvider(), !isCustomizingGridProvider() else {
            super.scrollWheel(with: event)
            return
        }

        let localPoint = convert(event.locationInWindow, from: nil)
        guard activeRect().contains(localPoint) else {
            super.scrollWheel(with: event)
            return
        }

        // Drop inertia/momentum scroll events entirely to ensure one swipe strictly equals one coin
        if !event.momentumPhase.isEmpty {
            return
        }

        if event.phase.contains(.began) {
            hasTriggeredInCurrentSwipe = false
            accumulatedDeltaX = 0
        }

        if event.phase.contains(.changed) {
            accumulatedDeltaX += event.scrollingDeltaX
            if !hasTriggeredInCurrentSwipe && abs(accumulatedDeltaX) >= 22.0 {
                hasTriggeredInCurrentSwipe = true
                let direction: CycleDirection = accumulatedDeltaX < 0 ? .next : .previous
                onSwipeGesture?(direction)
            }
            return
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            hasTriggeredInCurrentSwipe = false
            accumulatedDeltaX = 0
            return
        }

        // Fallback for non-trackpad scroll wheels (phase is empty)
        if event.phase.isEmpty && event.momentumPhase.isEmpty {
            let delta = event.scrollingDeltaX
            let now = ProcessInfo.processInfo.systemUptime
            if abs(delta) > 4.0 && now - lastSwipeTriggerTime > 0.40 {
                lastSwipeTriggerTime = now
                let direction: CycleDirection = delta < 0 ? .next : .previous
                onSwipeGesture?(direction)
                return
            }
        }

        super.scrollWheel(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if isCustomInputShowingProvider() {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 123: // Left arrow
            onSwipeGesture?(.previous)
            return
        case 124: // Right arrow
            onSwipeGesture?(.next)
            return
        case 53: // Escape
            onEscape?()
            return
        default:
            break
        }

        if let chars = event.charactersIgnoringModifiers,
           let num = Int(chars),
           (1...9).contains(num) {
            onJumpToFavorite?(num - 1)
            return
        }

        super.keyDown(with: event)
    }

    private func checkHover(with event: NSEvent) {
        if isNotchDisabledProvider() {
            setHovered(false)
            return
        }
        let localPoint = convert(event.locationInWindow, from: nil)
        let inside = activeRect().contains(localPoint)
        setHovered(inside)
    }

    private func setHovered(_ hovered: Bool) {
        let current = isHoveredProvider()
        guard hovered != current else { return }
        onHoverChanged?(hovered)
    }
}

/// Controller responsible for managing the Dynamic Island panel lifecycle,
/// positioning around the notch/screen edge, and sizing updates.
@MainActor
public final class DynamicIslandController: NSObject, ObservableObject {
    public let panel: DynamicIslandPanel
    public let binanceService: BinanceService
    public let settings: SettingsModel

    @Published public var isExpanded: Bool = false
    @Published public var isHovered: Bool = false
    @Published public var isCustomInputShowing: Bool = false
    @Published public var isCustomizingGrid: Bool = false
    @Published public var cycleDirection: CycleDirection = .next
    @Published public var cyclePulse: Bool = false
    public var isCollapsing: Bool = false

    private var hostingView: DynamicIslandHostingView<AnyView>?
    private var screenChangeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var collapseWorkItem: DispatchWorkItem?

    public static let expandAnimation = Animation.spring(response: 0.30, dampingFraction: 0.72)
    public static let collapseAnimation = Animation.spring(response: 0.20, dampingFraction: 0.88)

    public init(binanceService: BinanceService, settings: SettingsModel) {
        self.binanceService = binanceService
        self.settings = settings
        self.panel = DynamicIslandPanel(contentRect: .zero)
        self.isExpanded = settings.isPinned

        super.init()

        setupHostingView()
        updatePanelFrame()
        panel.orderFrontRegardless()

        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePanelFrame()
            }
        }

        if settings.isNotchDisabled {
            self.panel.ignoresMouseEvents = true
        }

        settings.$isPinned
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] pinned in
                guard let self = self else { return }
                if pinned && !self.isExpanded {
                    withAnimation(Self.expandAnimation) {
                        self.isExpanded = true
                    }
                } else if !pinned && !self.isHovered && !self.isCustomInputShowing && !self.isCustomizingGrid && self.isExpanded {
                    withAnimation(Self.collapseAnimation) {
                        self.isExpanded = false
                    }
                }
            }
            .store(in: &cancellables)

        settings.$isNotchDisabled
            .dropFirst()
            .sink { [weak self] disabled in
                guard let self = self else { return }
                if disabled {
                    if self.isExpanded {
                        withAnimation(Self.collapseAnimation) {
                            self.isExpanded = false
                        }
                    }
                    self.isCustomInputShowing = false
                    self.isCustomizingGrid = false
                    self.isHovered = false
                    self.panel.ignoresMouseEvents = true
                } else {
                    self.panel.ignoresMouseEvents = false
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest($isCustomInputShowing, $isCustomizingGrid)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] isCustomShowing, isCustomizing in
                guard let self = self else { return }
                if !isCustomShowing && !isCustomizing && !self.isHovered && !self.settings.isPinned && self.isExpanded {
                    self.handleHover(false)
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupHostingView() {
        let rootView = DynamicIslandView(
            controller: self,
            binanceService: binanceService,
            settings: settings
        )

        let host = DynamicIslandHostingView(rootView: AnyView(rootView))
        host.isExpandedProvider = { [weak self] in self?.isExpanded ?? false }
        host.isCollapsingProvider = { [weak self] in self?.isCollapsing ?? false }
        host.isHoveredProvider = { [weak self] in self?.isHovered ?? false }
        host.isCustomInputShowingProvider = { [weak self] in self?.isCustomInputShowing ?? false }
        host.isCustomizingGridProvider = { [weak self] in self?.isCustomizingGrid ?? false }
        host.isNotchDisabledProvider = { [weak self] in self?.settings.isNotchDisabled ?? false }
        host.onHoverChanged = { [weak self] hovered in
            self?.handleHover(hovered)
        }
        host.onSwipeGesture = { [weak self] direction in
            self?.cycleFavorite(direction: direction)
        }
        host.onJumpToFavorite = { [weak self] index in
            self?.jumpToFavorite(index: index)
        }
        host.onEscape = { [weak self] in
            guard let self = self else { return }
            if self.isCustomizingGrid {
                self.isCustomizingGrid = false
            } else if self.isExpanded && !self.settings.isPinned {
                withAnimation(Self.collapseAnimation) {
                    self.isExpanded = false
                }
            }
        }
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        self.hostingView = host
    }

    public func cyclingSymbols() -> [CryptoSymbol] {
        if settings.favorites.count >= 2 {
            return settings.favorites.map { fav in
                CryptoSymbol.presets.first(where: { $0.symbol == fav })
                    ?? CryptoSymbol.from(rawInput: fav, defaultExchange: binanceService.selectedExchange)
            }
        } else {
            return CryptoSymbol.presets
        }
    }

    public func cycleFavorite(direction: CycleDirection) {
        let list = cyclingSymbols()
        guard list.count >= 2 else { return }

        let current = binanceService.currentSymbol.symbol
        let currentIndex = list.firstIndex(where: { $0.symbol == current })

        let nextIndex: Int
        switch direction {
        case .next:
            if let idx = currentIndex {
                nextIndex = (idx + 1) % list.count
            } else {
                nextIndex = 0
            }
        case .previous:
            if let idx = currentIndex {
                nextIndex = (idx - 1 + list.count) % list.count
            } else {
                nextIndex = list.count - 1
            }
        }

        self.cycleDirection = direction
        withAnimation(.easeOut(duration: 0.15)) {
            binanceService.selectSymbol(list[nextIndex])
        }
    }

    public func jumpToFavorite(index: Int) {
        let list = cyclingSymbols()
        guard index >= 0, index < list.count else { return }

        let current = binanceService.currentSymbol.symbol
        let currentIndex = list.firstIndex(where: { $0.symbol == current }) ?? 0
        if index == currentIndex { return }

        let direction: CycleDirection = index > currentIndex ? .next : .previous
        self.cycleDirection = direction
        withAnimation(.easeOut(duration: 0.15)) {
            binanceService.selectSymbol(list[index])
        }
    }

    public func handleHover(_ hovering: Bool) {
        guard !settings.isNotchDisabled else { return }
        isHovered = hovering
        if hovering {
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
            isCollapsing = false

            if !isExpanded {
                withAnimation(Self.expandAnimation) {
                    isExpanded = true
                }
                panel.makeKey()
                if let host = hostingView {
                    panel.makeFirstResponder(host)
                }
            }
        } else {
            guard isExpanded, !settings.isPinned, !isCustomInputShowing, !isCustomizingGrid else { return }

            collapseWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                guard !self.isHovered, !self.settings.isPinned, !self.isCustomInputShowing, !self.isCustomizingGrid, self.isExpanded else { return }
                self.isCollapsing = true
                withAnimation(Self.collapseAnimation) {
                    self.isExpanded = false
                }
                self.panel.makeFirstResponder(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                    guard let self = self else { return }
                    if !self.isExpanded {
                        self.isCollapsing = false
                    }
                }
            }
            collapseWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: work)
        }
    }

    public func toggleExpansion() {
        guard !settings.isNotchDisabled else { return }
        let anim = !isExpanded ? Self.expandAnimation : Self.collapseAnimation
        withAnimation(anim) {
            isExpanded.toggle()
        }
        if isExpanded {
            panel.makeKey()
            if let host = hostingView {
                panel.makeFirstResponder(host)
            }
        }
    }

    public func toggleDisableNotch() {
        withAnimation(.spring(response: 0.44, dampingFraction: 0.84)) {
            settings.isNotchDisabled.toggle()
        }
    }

    /// Positions the island window centered at the top edge of the screen, hugging the notch.
    public func updatePanelFrame(animated: Bool = false) {
        guard let screen = NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil }) ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let screenFrame = screen.frame
        let geometry = NotchGeometry.current(for: screen)

        let width = geometry.expandedWidth
        let height = geometry.expandedHeight

        let x = geometry.notchCenter - (width / 2)
        let y = screenFrame.maxY - height

        let targetFrame = NSRect(x: x, y: y, width: width, height: height)
        if panel.frame != targetFrame {
            panel.setFrame(targetFrame, display: true)
        }
    }
}
