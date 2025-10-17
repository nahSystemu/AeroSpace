import AppKit
import Common

extension Workspace {
    @MainActor
    func layoutWorkspace() async throws {
        if isEffectivelyEmpty { return }
        let rect = workspaceMonitor.visibleRectPaddedByOuterGaps
        // If monitors are aligned vertically and the monitor below has smaller width, then macOS may not allow the
        // window on the upper monitor to take full width. rect.height - 1 resolves this problem
        // But I also faced this problem in monitors horizontal configuration. ¯\_(ツ)_/¯
        try await layoutRecursive(rect.topLeftCorner, width: rect.width, height: rect.height - 1, virtual: rect, LayoutContext(self))
    }
}

extension TreeNode {
    @MainActor
    fileprivate func layoutRecursive(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        let physicalRect = Rect(topLeftX: point.x, topLeftY: point.y, width: width, height: height)
        switch nodeCases {
            case .workspace(let workspace):
                lastAppliedLayoutPhysicalRect = physicalRect
                lastAppliedLayoutVirtualRect = virtual
                try await workspace.rootTilingContainer.layoutRecursive(point, width: width, height: height, virtual: virtual, context)
                for window in workspace.children.filterIsInstance(of: Window.self) {
                    window.lastAppliedLayoutPhysicalRect = nil
                    window.lastAppliedLayoutVirtualRect = nil
                    try await window.layoutFloatingWindow(context)
                }
            case .window(let window):
                if window.windowId != currentlyManipulatedWithMouseWindowId {
                    lastAppliedLayoutVirtualRect = virtual
                    if window.isFullscreen && window == context.workspace.rootTilingContainer.mostRecentWindowRecursive {
                        lastAppliedLayoutPhysicalRect = nil
                        window.layoutFullscreen(context)
                    } else {
                        lastAppliedLayoutPhysicalRect = physicalRect
                        window.isFullscreen = false
                        window.setAxFrame(point, CGSize(width: width, height: height))
                    }
                }
            case .tilingContainer(let container):
                lastAppliedLayoutPhysicalRect = physicalRect
                lastAppliedLayoutVirtualRect = virtual
                try await container.layout.strategy.layout(
                    container: container,
                    at: point,
                    width: width,
                    height: height,
                    virtual: virtual,
                    context: context
                )
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
                return // Nothing to do for weirdos
        }
    }
}

struct LayoutContext {
    let workspace: Workspace
    let resolvedGaps: ResolvedGaps

    @MainActor
    init(_ workspace: Workspace) {
        self.workspace = workspace
        self.resolvedGaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)
    }
}

extension Window {
    @MainActor
    fileprivate func layoutFloatingWindow(_ context: LayoutContext) async throws {
        let workspace = context.workspace
        let currentMonitor = try await getCenter()?.monitorApproximation // Probably not idempotent
        if let currentMonitor, let windowTopLeftCorner = try await getAxTopLeftCorner(), workspace != currentMonitor.activeWorkspace {
            let xProportion = (windowTopLeftCorner.x - currentMonitor.visibleRect.topLeftX) / currentMonitor.visibleRect.width
            let yProportion = (windowTopLeftCorner.y - currentMonitor.visibleRect.topLeftY) / currentMonitor.visibleRect.height

            let moveTo = workspace.workspaceMonitor
            setAxTopLeftCorner(CGPoint(
                x: moveTo.visibleRect.topLeftX + xProportion * moveTo.visibleRect.width,
                y: moveTo.visibleRect.topLeftY + yProportion * moveTo.visibleRect.height,
            ))
        }
        if isFullscreen {
            layoutFullscreen(context)
            isFullscreen = false
        }
    }

    @MainActor
    fileprivate func layoutFullscreen(_ context: LayoutContext) {
        let monitorRect = noOuterGapsInFullscreen
            ? context.workspace.workspaceMonitor.visibleRect
            : context.workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        setAxFrame(monitorRect.topLeftCorner, CGSize(width: monitorRect.width, height: monitorRect.height))
    }
}

extension TilingContainer {
    @MainActor
    func layoutTiles(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        var point = point
        var virtualPoint = virtual.topLeftCorner

        guard let delta = ((orientation == .h ? width : height) - CGFloat(children.sumOfDouble { $0.getWeight(orientation) }))
            .div(children.count) else { return }

        let lastIndex = children.indices.last
        for (i, child) in children.enumerated() {
            child.setWeight(orientation, child.getWeight(orientation) + delta)
            let rawGap = context.resolvedGaps.inner.get(orientation).toDouble()
            // Gaps. Consider 4 cases:
            // 1. Multiple children. Layout first child
            // 2. Multiple children. Layout last child
            // 3. Multiple children. Layout child in the middle
            // 4. Single child   let rawGap = gaps.inner.get(orientation).toDouble()
            let gap = rawGap - (i == 0 ? rawGap / 2 : 0) - (i == lastIndex ? rawGap / 2 : 0)
            try await child.layoutRecursive(
                i == 0 ? point : point.addingOffset(orientation, rawGap / 2),
                width: orientation == .h ? child.hWeight - gap : width,
                height: orientation == .v ? child.vWeight - gap : height,
                virtual: Rect(
                    topLeftX: virtualPoint.x,
                    topLeftY: virtualPoint.y,
                    width: orientation == .h ? child.hWeight : width,
                    height: orientation == .v ? child.vWeight : height,
                ),
                context,
            )
            virtualPoint = orientation == .h ? virtualPoint.addingXOffset(child.hWeight) : virtualPoint.addingYOffset(child.vWeight)
            point = orientation == .h ? point.addingXOffset(child.hWeight) : point.addingYOffset(child.vWeight)
        }
    }

    @MainActor
    func layoutAccordion(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        guard let mruIndex: Int = mostRecentChild?.ownIndex else { return }
        for (index, child) in children.enumerated() {
            let padding = CGFloat(config.accordionPadding)
            let (lPadding, rPadding): (CGFloat, CGFloat) = switch index {
                case 0 where children.count == 1: (0, 0)
                case 0:                           (0, padding)
                case children.indices.last:       (padding, 0)
                case mruIndex - 1:                (0, 2 * padding)
                case mruIndex + 1:                (2 * padding, 0)
                default:                          (padding, padding)
            }
            switch orientation {
                case .h:
                    try await child.layoutRecursive(
                        point + CGPoint(x: lPadding, y: 0),
                        width: width - rPadding - lPadding,
                        height: height,
                        virtual: virtual,
                        context,
                    )
                case .v:
                    try await child.layoutRecursive(
                        point + CGPoint(x: 0, y: lPadding),
                        width: width,
                        height: height - lPadding - rPadding,
                        virtual: virtual,
                        context,
                    )
            }
            }
    }
}

extension TilingContainer {
    @MainActor
    func layoutHyprland(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        let rect = Rect(topLeftX: point.x, topLeftY: point.y, width: width, height: height)
        try await hyprlandLayout(
            childrenSlice: children[...],
            rect: rect,
            virtualRect: virtual,
            orientation: orientation,
            context: context
        )
    }

    @MainActor
    private func hyprlandLayout(
        childrenSlice: ArraySlice<TreeNode>,
        rect: Rect,
        virtualRect: Rect,
        orientation: Orientation,
        context: LayoutContext
    ) async throws {
        guard let first = childrenSlice.first else { return }

        if childrenSlice.count == 1 {
            try await first.layoutRecursive(
                rect.topLeftCorner,
                width: rect.width,
                height: rect.height,
                virtual: virtualRect,
                context
            )
            return
        }

        let restSlice = childrenSlice.dropFirst()
        let gap = restSlice.isEmpty ? CGFloat.zero : CGFloat(context.resolvedGaps.inner.get(orientation).toDouble())
        let primaryRatio = hyprlandPrimarySplitRatio

        switch orientation {
            case .h:
                try await hyprlandSplitAlongHorizontal(
                    first: first,
                    restSlice: restSlice,
                    rect: rect,
                    virtualRect: virtualRect,
                    gap: gap,
                    ratio: primaryRatio,
                    nextOrientation: orientation.opposite,
                    context: context
                )
            case .v:
                try await hyprlandSplitAlongVertical(
                    first: first,
                    restSlice: restSlice,
                    rect: rect,
                    virtualRect: virtualRect,
                    gap: gap,
                    ratio: primaryRatio,
                    nextOrientation: orientation.opposite,
                    context: context
                )
        }
    }

    @MainActor
    private func hyprlandSplitAlongHorizontal(
        first: TreeNode,
        restSlice: ArraySlice<TreeNode>,
        rect: Rect,
        virtualRect: Rect,
        gap: CGFloat,
        ratio: CGFloat,
        nextOrientation: Orientation,
        context: LayoutContext
    ) async throws {
        let hasRest = !restSlice.isEmpty
        let gapToUse = hasRest && rect.width > gap ? gap : 0
        let availableWidth = max(0, rect.width - gapToUse)
        let clampedRatio = clampHyprlandRatio(ratio)
        let firstWidth = hasRest ? availableWidth * clampedRatio : rect.width
        let restWidth = hasRest ? max(0, availableWidth - firstWidth) : 0

        // Physical rectangles
        let firstRect = Rect(
            topLeftX: rect.topLeftX,
            topLeftY: rect.topLeftY,
            width: firstWidth,
            height: rect.height
        )
        let restRect = Rect(
            topLeftX: rect.topLeftX + firstWidth + (hasRest ? gapToUse : 0),
            topLeftY: rect.topLeftY,
            width: restWidth,
            height: rect.height
        )

        // Virtual rectangles
        let firstVirtualWidth = hasRest ? virtualRect.width * clampedRatio : virtualRect.width
        let restVirtualWidth = hasRest ? max(0, virtualRect.width - firstVirtualWidth) : 0
        let firstVirtual = Rect(
            topLeftX: virtualRect.topLeftX,
            topLeftY: virtualRect.topLeftY,
            width: firstVirtualWidth,
            height: virtualRect.height
        )
        let restVirtual = Rect(
            topLeftX: virtualRect.topLeftX + firstVirtualWidth,
            topLeftY: virtualRect.topLeftY,
            width: restVirtualWidth,
            height: virtualRect.height
        )

        try await first.layoutRecursive(
            firstRect.topLeftCorner,
            width: firstRect.width,
            height: firstRect.height,
            virtual: firstVirtual,
            context
        )

        if hasRest {
            try await hyprlandLayout(
                childrenSlice: restSlice,
                rect: restRect,
                virtualRect: restVirtual,
                orientation: nextOrientation,
                context: context
            )
        }
    }

    @MainActor
    private func hyprlandSplitAlongVertical(
        first: TreeNode,
        restSlice: ArraySlice<TreeNode>,
        rect: Rect,
        virtualRect: Rect,
        gap: CGFloat,
        ratio: CGFloat,
        nextOrientation: Orientation,
        context: LayoutContext
    ) async throws {
        let hasRest = !restSlice.isEmpty
        let gapToUse = hasRest && rect.height > gap ? gap : 0
        let availableHeight = max(0, rect.height - gapToUse)
        let clampedRatio = clampHyprlandRatio(ratio)
        let firstHeight = hasRest ? availableHeight * clampedRatio : rect.height
        let restHeight = hasRest ? max(0, availableHeight - firstHeight) : 0

        let firstRect = Rect(
            topLeftX: rect.topLeftX,
            topLeftY: rect.topLeftY,
            width: rect.width,
            height: firstHeight
        )
        let restRect = Rect(
            topLeftX: rect.topLeftX,
            topLeftY: rect.topLeftY + firstHeight + (hasRest ? gapToUse : 0),
            width: rect.width,
            height: restHeight
        )

        let firstVirtualHeight = hasRest ? virtualRect.height * clampedRatio : virtualRect.height
        let restVirtualHeight = hasRest ? max(0, virtualRect.height - firstVirtualHeight) : 0
        let firstVirtual = Rect(
            topLeftX: virtualRect.topLeftX,
            topLeftY: virtualRect.topLeftY,
            width: virtualRect.width,
            height: firstVirtualHeight
        )
        let restVirtual = Rect(
            topLeftX: virtualRect.topLeftX,
            topLeftY: virtualRect.topLeftY + firstVirtualHeight,
            width: virtualRect.width,
            height: restVirtualHeight
        )

        try await first.layoutRecursive(
            firstRect.topLeftCorner,
            width: firstRect.width,
            height: firstRect.height,
            virtual: firstVirtual,
            context
        )

        if hasRest {
            try await hyprlandLayout(
                childrenSlice: restSlice,
                rect: restRect,
                virtualRect: restVirtual,
                orientation: nextOrientation,
                context: context
            )
        }
    }
}

private let hyprlandPrimarySplitRatio = CGFloat(0.61803398875) // golden ratio inspired default
private let hyprlandRatioBounds: ClosedRange<CGFloat> = 0.1 ... 0.9

private func clampHyprlandRatio(_ value: CGFloat) -> CGFloat {
    min(max(value, hyprlandRatioBounds.lowerBound), hyprlandRatioBounds.upperBound)
}
