@preconcurrency import XCTest
@testable import ApiRelay

final class SecurityPolicyChangeTests: XCTestCase {
    func testTurningOffAppLockIsWeakening() {
        let current = PreferencesDTO.fakeDefault().applying(PreferencesPatch(appLockEnabled: true))
        XCTAssertTrue(SecurityPolicyChange.weakens(PreferencesPatch(appLockEnabled: false), relativeTo: current))
        XCTAssertFalse(SecurityPolicyChange.weakens(PreferencesPatch(appLockEnabled: true), relativeTo: current))
    }

    func testLongerAutoLockIsWeakening() {
        let current = PreferencesDTO.fakeDefault().applying(
            PreferencesPatch(appLockEnabled: true, autoLockSeconds: 30)
        )
        XCTAssertTrue(SecurityPolicyChange.weakens(PreferencesPatch(autoLockSeconds: 120), relativeTo: current))
        XCTAssertFalse(SecurityPolicyChange.weakens(PreferencesPatch(autoLockSeconds: 0), relativeTo: current))
    }

    func testNoVerificationIsWeakerThanBiometric() {
        let current = PreferencesDTO.fakeDefault().applying(
            PreferencesPatch(revealPolicy: .biometricOrPasscode)
        )
        XCTAssertTrue(SecurityPolicyChange.weakens(PreferencesPatch(revealPolicy: .noVerification), relativeTo: current))
        XCTAssertFalse(
            SecurityPolicyChange.weakens(PreferencesPatch(revealPolicy: .masterPassword), relativeTo: current)
        )
    }

    func testHideAndClipboardClearOffAreWeakening() {
        let current = PreferencesDTO.fakeDefault().applying(
            PreferencesPatch(clipboardClearEnabled: true, hideInAppSwitcher: true)
        )
        XCTAssertTrue(SecurityPolicyChange.weakens(PreferencesPatch(hideInAppSwitcher: false), relativeTo: current))
        XCTAssertTrue(SecurityPolicyChange.weakens(PreferencesPatch(clipboardClearEnabled: false), relativeTo: current))
    }
}
