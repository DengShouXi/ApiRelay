@preconcurrency import XCTest
@testable import ApiRelay

/// Wave 3 真值表。每新增一台 OS 行为只加一行，不改产品表。
@MainActor
final class ScenePresenceSignalTests: XCTestCase {
    func testTruthTable() {
        for row in Self.table {
            XCTAssertEqual(
                AppLockScenePresence.resolve(row.signals),
                row.expected,
                row.name
            )
        }
    }

    func testUnknownSceneIsNotOffScreen() {
        let signals = ScenePresenceSignals(
            sceneIsForegroundActive: .unknown,
            sceneIsForegroundInactive: .unknown,
            applicationIsActive: .unknown,
            isKeyWindow: .unknown,
            activeAppearanceIsActive: .unknown,
            appearsActive: .unknown,
            authenticationInProgress: false
        )
        XCTAssertNotEqual(AppLockScenePresence.resolve(signals), .offScreen)
        XCTAssertFalse(AppLockScenePresence.isDefinitelyOffScreen(signals))
    }

    func testLegacyResolveStillMapsCombinedHostFlag() {
        XCTAssertEqual(
            AppLockScenePresence.resolve(
                hasForegroundActive: true,
                hasForegroundInactive: false,
                applicationIsActive: true,
                hostHasKeyOrActiveWindow: false
            ),
            .onScreenIdle
        )
        XCTAssertEqual(
            AppLockScenePresence.resolve(
                hasForegroundActive: false,
                hasForegroundInactive: false,
                applicationIsActive: false,
                hostHasKeyOrActiveWindow: false
            ),
            .offScreen
        )
    }

    private struct Row {
        var name: String
        var signals: ScenePresenceSignals
        var expected: AppLockScenePresence
    }

    private static let table: [Row] = [
        Row(
            name: "iPadOS26 同组点 Safari：scene 仍 Active、App active、无 Key、外观 inactive → B",
            signals: .known(
                sceneIsForegroundActive: true,
                sceneIsForegroundInactive: false,
                applicationIsActive: true,
                isKeyWindow: false,
                activeAppearanceIsActive: false
            ),
            expected: .onScreenIdle
        ),
        Row(
            name: "iPadOS26 本窗操作：Key + 外观 active → A",
            signals: .known(
                sceneIsForegroundActive: true,
                sceneIsForegroundInactive: false,
                applicationIsActive: true,
                isKeyWindow: true,
                activeAppearanceIsActive: true
            ),
            expected: .userFacing
        ),
        Row(
            name: "控制中心 / Face ID：App 非 active，scene 仍 Active，Key 被抢 → 仍 A（不得当 B）",
            signals: .known(
                sceneIsForegroundActive: true,
                sceneIsForegroundInactive: false,
                applicationIsActive: false,
                isKeyWindow: false,
                activeAppearanceIsActive: true
            ),
            expected: .userFacing
        ),
        Row(
            name: "C：验证进行中抢走 Key，App 仍 active，外观未知 → 仍 A",
            signals: .known(
                sceneIsForegroundActive: true,
                sceneIsForegroundInactive: false,
                applicationIsActive: true,
                isKeyWindow: false,
                activeAppearanceIsActive: nil,
                authenticationInProgress: true
            ),
            expected: .userFacing
        ),
        Row(
            name: "B：同组失焦、无验证框、App active、无 Key → idle，不得当离屏",
            signals: .known(
                sceneIsForegroundActive: true,
                sceneIsForegroundInactive: false,
                applicationIsActive: true,
                isKeyWindow: false,
                activeAppearanceIsActive: false,
                authenticationInProgress: false
            ),
            expected: .onScreenIdle
        ),
        Row(
            name: "真离开：scene 非 Active/Inactive → 离屏",
            signals: .known(
                sceneIsForegroundActive: false,
                sceneIsForegroundInactive: false,
                applicationIsActive: false,
                isKeyWindow: false,
                activeAppearanceIsActive: false
            ),
            expected: .offScreen
        ),
        Row(
            name: "C 但 scene 已确定离屏（换组）→ 离屏",
            signals: .known(
                sceneIsForegroundActive: false,
                sceneIsForegroundInactive: false,
                applicationIsActive: false,
                isKeyWindow: false,
                activeAppearanceIsActive: false,
                authenticationInProgress: true
            ),
            expected: .offScreen
        ),
        Row(
            name: "未知 scene 激活态：不得当离屏",
            signals: ScenePresenceSignals(
                sceneIsForegroundActive: .unknown,
                sceneIsForegroundInactive: .unknown,
                applicationIsActive: .known(false),
                isKeyWindow: .unknown,
                activeAppearanceIsActive: .unknown,
                appearsActive: .unknown,
                authenticationInProgress: false
            ),
            expected: .onScreenIdle
        ),
        Row(
            name: "appearsActive 未知、有 Key、外观 unspecified → A（跟现码一致）",
            signals: .known(
                sceneIsForegroundActive: true,
                sceneIsForegroundInactive: false,
                applicationIsActive: true,
                isKeyWindow: true,
                activeAppearanceIsActive: nil,
                appearsActive: nil
            ),
            expected: .userFacing
        ),
        Row(
            name: "将来 SDK：appearsActive true 可补 Key 被抢时仍在用",
            signals: .known(
                sceneIsForegroundActive: true,
                sceneIsForegroundInactive: false,
                applicationIsActive: true,
                isKeyWindow: false,
                activeAppearanceIsActive: nil,
                appearsActive: true
            ),
            expected: .userFacing
        ),
        Row(
            name: "将来 SDK：appearsActive false 且无 Key → B",
            signals: .known(
                sceneIsForegroundActive: true,
                sceneIsForegroundInactive: false,
                applicationIsActive: true,
                isKeyWindow: false,
                activeAppearanceIsActive: nil,
                appearsActive: false
            ),
            expected: .onScreenIdle
        ),
        Row(
            name: "Mac 同组失焦：App active、foregroundInactive、无 Key → B",
            signals: .known(
                sceneIsForegroundActive: false,
                sceneIsForegroundInactive: true,
                applicationIsActive: true,
                isKeyWindow: false,
                activeAppearanceIsActive: false
            ),
            expected: .onScreenIdle
        )
    ]
}
