import AppKit
import Common

@MainActor
protocol LayoutStrategy {
    func layout(
        container: TilingContainer,
        at point: CGPoint,
        width: CGFloat,
        height: CGFloat,
        virtual: Rect,
        context: LayoutContext
    ) async throws
}

struct TilesLayoutStrategy: LayoutStrategy {
    func layout(
        container: TilingContainer,
        at point: CGPoint,
        width: CGFloat,
        height: CGFloat,
        virtual: Rect,
        context: LayoutContext
    ) async throws {
        try await container.layoutTiles(point, width: width, height: height, virtual: virtual, context)
    }
}

struct AccordionLayoutStrategy: LayoutStrategy {
    func layout(
        container: TilingContainer,
        at point: CGPoint,
        width: CGFloat,
        height: CGFloat,
        virtual: Rect,
        context: LayoutContext
    ) async throws {
        try await container.layoutAccordion(point, width: width, height: height, virtual: virtual, context)
    }
}

struct HyprlandLayoutStrategy: LayoutStrategy {
    func layout(
        container: TilingContainer,
        at point: CGPoint,
        width: CGFloat,
        height: CGFloat,
        virtual: Rect,
        context: LayoutContext
    ) async throws {
        try await container.layoutHyprland(point, width: width, height: height, virtual: virtual, context)
    }
}

extension Layout {
    var strategy: any LayoutStrategy {
        switch self {
            case .tiles: TilesLayoutStrategy()
            case .accordion: AccordionLayoutStrategy()
            case .hyprland: HyprlandLayoutStrategy()
        }
    }
}
