@testable import AppBundle
import Common
import XCTest

@MainActor
final class LayoutCommandHyprlandTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
    }

    func testSwitchToHyprlandLayout() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
    assertEquals(TestWindow.new(id: 1, parent: root).focusWindow(), true)

        let command = LayoutCommand(args: LayoutCmdArgs(rawArgs: [], toggleBetween: [.hyprland]))
        let result = try await command.run(.defaultEnv, .emptyStdin)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.isEmpty)
        XCTAssertEqual(root.layout, .hyprland)
        XCTAssertEqual(root.layoutDescription, .hyprland(root.orientation, [.window(1)]))
    }

    func testToggleHyprlandBackToTiles() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
    assertEquals(TestWindow.new(id: 1, parent: root).focusWindow(), true)

        XCTAssertEqual(root.layout, .tiles)

        _ = try await LayoutCommand(args: LayoutCmdArgs(rawArgs: [], toggleBetween: [.hyprland, .tiles])).run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(root.layout, .hyprland)

        _ = try await LayoutCommand(args: LayoutCmdArgs(rawArgs: [], toggleBetween: [.hyprland, .tiles])).run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(root.layout, .tiles)
    }
}
