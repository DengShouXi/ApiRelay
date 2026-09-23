import Foundation
import LocalAuthentication
import OSLog
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Debug-only bounded local evidence; never records reasons, passwords or secrets.
/// Persist immediately because Xcode relaunches and SIGKILL can lose stdout buffers.
nonisolated enum AuthenticationTrace {
    private static let lock = NSLock()
    static var buildIdentity: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let raw = Bundle.main.object(forInfoDictionaryKey: "ApiRelayBuildFingerprint") as? String
        let fingerprint = raw.flatMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed.contains("$(") ? nil : trimmed
        } ?? "unlabeled"
        return "\(version)(\(build))/\(fingerprint)"
    }

    static func emit(_ event: String) {
        #if DEBUG
        guard !AppRuntime.isRunningTests else { return }
        lock.lock()
        defer { lock.unlock() }
        let line = "[Authentication U8.1] \(Date().timeIntervalSince1970) \(event)\n"
        let data = Data(line.utf8)
        FileHandle.standardOutput.write(data)
        let url = URL.cachesDirectory.appendingPathComponent("ApiRelay-auth-diagnostics.log")
        var existing = (try? Data(contentsOf: url)) ?? Data()
        if existing.count > 32_768 { existing = Data() }
        existing.append(data)
        // Diagnostics must never fail or change the authentication outcome.
        try? existing.write(to: url, options: .atomic)
        #endif
    }
}

/// System authentication may report success before its overlay has restored the
/// originating app/scene. Keep one bounded policy for every Apple platform so a
/// fix on iPhone cannot silently leave the former two-second race on macOS.
nonisolated private enum AuthenticationReturnPolicy {
    static let maximumPollCount = 200
    static let pollInterval = Duration.milliseconds(50)
}

/// 四档门闩实现。每次 confirm 新建 LAContext，不缓存成功态。
actor RevealGate: RevealGateServing {
    private let masterPassword: MasterPasswordServing
    /// 测试可注入：跳过真实 LA。
    private let authenticateDeviceOwner: (@Sendable (String, LAPolicy) async throws -> Void)?
    /// 测试可注入：只替换生物类型探测，不改变系统认证策略。
    private let availableBiometryOverride: (@Sendable () -> BiometryKind)?
    private let requestCoordinator = AuthenticationRequestCoordinator()
    /// 测试只替换“等待原场景恢复”这一系统边界；认证请求编排仍走生产路径。
    private let awaitAuthenticationReturnOverride: (@Sendable () async throws -> Void)?

    init(
        masterPassword: MasterPasswordServing,
        authenticateDeviceOwner: (@Sendable (String, LAPolicy) async throws -> Void)? = nil,
        availableBiometry: (@Sendable () -> BiometryKind)? = nil,
        awaitAuthenticationReturn: (@Sendable () async throws -> Void)? = nil
    ) {
        self.masterPassword = masterPassword
        self.authenticateDeviceOwner = authenticateDeviceOwner
        self.availableBiometryOverride = availableBiometry
        self.awaitAuthenticationReturnOverride = awaitAuthenticationReturn
    }

    nonisolated func cancelAuthentication(owner: AuthenticationRequestOwner) {
        AuthenticationTrace.emit(
            "cancel owner=\(owner); activeOwner=\(String(describing: requestCoordinator.activeOwner()))"
        )
        requestCoordinator.cancel(owner: owner)
    }

    nonisolated func cancelAllAuthentication() {
        AuthenticationTrace.emit(
            "cancel all; activeOwner=\(String(describing: requestCoordinator.activeOwner()))"
        )
        requestCoordinator.cancelAll()
    }

    nonisolated func isAuthenticationInProgress(owner: AuthenticationRequestOwner?) -> Bool {
        requestCoordinator.isActive(owner: owner)
    }

    nonisolated func availableBiometry() -> BiometryKind {
        if let availableBiometryOverride {
            return availableBiometryOverride()
        }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .none
        }
    }

    func confirm(reason: String, policy: RevealPolicy, purpose: AuthPurpose) async throws {
        switch policy {
        case .noVerification:
            return
        case .biometricOrPasscode:
            try await evaluate(
                reason: reason,
                policy: .deviceOwnerAuthentication,
                purpose: purpose
            )
        case .masterPassword:
            guard try await masterPassword.isSet() else {
                throw ApiRelayError.validationFailed(field: "revealPolicy", reason: "master_password_not_set")
            }
            // UI 负责采集口令并调用 verify；此处要求调用方先经 MasterPasswordPrompt。
            // KeyVault 在 masterPassword 档时改走 confirmWithMasterPassword。
            throw ApiRelayError.validationFailed(field: "revealPolicy", reason: "master_password_prompt_required")
        case .biometryOrAppPassword:
            // Let LocalAuthentication own the biometric → device-password
            // transition. Starting a second context after biometric failure makes
            // Face ID / Touch ID run again instead of entering the passcode.
            // App password remains an explicit, app-owned path in the calling UI.
            try await evaluate(
                reason: reason,
                policy: .deviceOwnerAuthentication,
                purpose: purpose
            )
        }
    }

    /// 主密码档：由 UI 传入口令，服务内校验；不经 LA。
    func confirmWithMasterPassword(
        reason: String,
        password: String,
        purpose: AuthPurpose
    ) async throws {
        _ = reason
        let request = try requestCoordinator.begin(owner: purpose.requestOwner)
        defer { requestCoordinator.clearIfCurrent(request) }
        #if canImport(UIKit) || canImport(AppKit)
        let sceneWitness: AuthenticationSceneWitness?
        if awaitAuthenticationReturnOverride != nil || AppRuntime.isRunningTests {
            sceneWitness = nil
        } else {
            sceneWitness = await AuthenticationSceneWitness()
        }
        #endif
        do {
            try await withTaskCancellationHandler {
                try requestCoordinator.throwIfCancelled(request)
                guard try await masterPassword.isSet() else {
                    throw ApiRelayError.validationFailed(
                        field: "revealPolicy",
                        reason: "master_password_not_set"
                    )
                }
                try requestCoordinator.throwIfCancelled(request)
                let ok = try await masterPassword.verify(password)
                guard ok else { throw ApiRelayError.authenticationFailed }
                #if canImport(UIKit) || canImport(AppKit)
                try await waitForAuthenticationReturn(request: request, witness: sceneWitness)
                #else
                try requestCoordinator.throwIfCancelled(request)
                #endif
            } onCancel: { [requestCoordinator] in
                requestCoordinator.cancel(request: request)
            }
        } catch is CancellationError {
            throw ApiRelayError.authenticationCancelled
        }
    }

    func confirmCombinationWithAppPassword(reason: String, password: String, purpose: AuthPurpose) async throws {
        try await confirmWithMasterPassword(reason: reason, password: password, purpose: purpose)
    }

    /// 选用主密码门闩前确认本机已设密（防策略已写、密未设的卡死态）。
    func ensureMasterPasswordConfigured() async throws {
        guard try await masterPassword.isSet() else {
            throw ApiRelayError.validationFailed(field: "revealPolicy", reason: "master_password_not_set")
        }
    }

    func isAppPasswordMaterialSet() async throws -> Bool {
        try await masterPassword.isSet()
    }

    func appPasswordMaterialStatus() async -> AppPasswordMaterialStatus {
        await masterPassword.materialStatus()
    }

    func confirmMandatory(reason: String, purpose: AuthPurpose) async throws {
        try await evaluate(reason: reason, policy: .deviceOwnerAuthentication, purpose: purpose)
    }

    private func evaluate(reason: String, policy: LAPolicy, purpose: AuthPurpose) async throws {
        let request = try requestCoordinator.begin(owner: purpose.requestOwner)
        defer { requestCoordinator.clearIfCurrent(request) }
        #if canImport(UIKit) || canImport(AppKit)
        let sceneWitness: AuthenticationSceneWitness?
        if awaitAuthenticationReturnOverride != nil || AppRuntime.isRunningTests {
            sceneWitness = nil
        } else {
            sceneWitness = await AuthenticationSceneWitness()
        }
        #endif
        let context: LAContext? = authenticateDeviceOwner == nil ? LAContext() : nil
        if let context {
            context.localizedCancelTitle = String(localized: "gate.cancel")
            // Keep Apple's device-specific fallback title. iPhone/iPad show the
            // system passcode wording while Mac correctly names its login password.
            try requestCoordinator.replaceContext(context, request: request)
        }
        do {
            try await withTaskCancellationHandler {
                do {
                    AuthenticationTrace.emit("system evaluate started owner=\(purpose.requestOwner)")
                    if let authenticateDeviceOwner {
                        try await authenticateDeviceOwner(reason, policy)
                    } else if let context {
                        let success = try await context.evaluatePolicy(policy, localizedReason: reason)
                        AuthenticationTrace.emit("system evaluate returned success=\(success)")
                        if !success { throw ApiRelayError.authenticationFailed }
                    }
                    context?.invalidate()
                    AuthenticationTrace.emit("system context invalidated before return wait")
                    #if canImport(UIKit) || canImport(AppKit)
                    try await waitForAuthenticationReturn(request: request, witness: sceneWitness)
                    #else
                    try requestCoordinator.throwIfCancelled(request)
                    #endif
                    AuthenticationTrace.emit("system authentication completed")
                } catch let error as ApiRelayError {
                    AuthenticationTrace.emit(
                        "return check rejected; requestActive=\(requestCoordinator.isActive())"
                    )
                    throw error
                } catch {
                    let diagnostic = error as NSError
                    AuthenticationTrace.emit(
                        "system error domain=\(diagnostic.domain) code=\(diagnostic.code)"
                    )
                    context?.invalidate()
                    // Do not present fallback UI while the system sheet is still closing.
                    #if canImport(UIKit) || canImport(AppKit)
                    try await waitForAuthenticationReturn(request: request, witness: sceneWitness)
                    #else
                    try requestCoordinator.throwIfCancelled(request)
                    #endif
                    throw mappedAuthenticationError(error, policy: policy)
                }
            } onCancel: { [requestCoordinator] in
                requestCoordinator.cancel(request: request)
            }
        } catch is CancellationError {
            throw ApiRelayError.authenticationCancelled
        }
    }

    #if canImport(UIKit) || canImport(AppKit)
    private func waitForAuthenticationReturn(
        request: AuthenticationRequestHandle,
        witness: AuthenticationSceneWitness?
    ) async throws {
        if let awaitAuthenticationReturnOverride {
            try await awaitAuthenticationReturnOverride()
        } else if let witness {
            try await witness.waitUntilActive { [requestCoordinator] in
                try requestCoordinator.throwIfCancelled(request)
            }
        }
        try requestCoordinator.throwIfCancelled(request)
    }
    #endif

    private func mappedAuthenticationError(_ error: Error, policy: LAPolicy) -> ApiRelayError {
        if let api = error as? ApiRelayError {
            return api
        }
        guard let la = error as? LAError else {
            return .systemAuthenticationFailed
        }
        switch la.code {
        case .userFallback:
            return .biometryUnavailable
        case .userCancel, .appCancel:
            return .authenticationCancelled
        case .systemCancel:
            return .authenticationInterrupted
        case .passcodeNotSet:
            return .devicePasscodeNotSet
        case .notInteractive:
            return .authenticationNotInteractive
        case .invalidContext:
            return .authenticationContextInvalid
        case .biometryNotAvailable, .biometryNotEnrolled:
            if policy == .deviceOwnerAuthenticationWithBiometrics {
                return .biometryUnavailable
            }
            return .systemAuthenticationFailed
        case .biometryLockout:
            if policy == .deviceOwnerAuthenticationWithBiometrics {
                return .biometryLockout
            }
            return .systemAuthenticationFailed
        default:
            return .systemAuthenticationFailed
        }
    }
}

#if canImport(UIKit)
@MainActor
final class AuthenticationSceneWitness {
    private let readSignals: @MainActor () -> ScenePresenceSignals?
    private static let logger = Logger(subsystem: "com.apirelay.ApiRelay", category: "AuthenticationReturn")

    static func originIndex(_ signals: [ScenePresenceSignals]) -> Int? {
        let foreground = signals.indices.filter {
            signals[$0].sceneIsForegroundActive.knownValue == true ||
            signals[$0].sceneIsForegroundInactive.knownValue == true
        }
        if let key = foreground.first(where: { signals[$0].isKeyWindow.knownValue == true }) { return key }
        if let active = foreground.first(where: { signals[$0].activeAppearanceIsActive.knownValue == true }) { return active }
        // A single foreground phone scene remains identifiable during a system transition.
        return foreground.count == 1 ? foreground[0] : nil
    }

    init() {
        let candidates = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let signals = candidates.map {
            AppPrivacyController.liveSignals(for: $0, applicationIsActive: UIApplication.shared.applicationState == .active,
                                             authenticationInProgress: false)
        }
        let scene = Self.originIndex(signals).map { candidates[$0] }
        readSignals = { [weak scene] in
            guard let scene else { return nil }
            return AppPrivacyController.liveSignals(
                for: scene,
                applicationIsActive: UIApplication.shared.applicationState == .active,
                authenticationInProgress: false
            )
        }
    }

    /// Tests exercise the same asynchronous return check as production, including
    /// foreground transitions and cancellation, without invoking biometric UI.
    init(readSignals: @escaping @MainActor () -> ScenePresenceSignals?) {
        self.readSignals = readSignals
    }

    func waitUntilActive(checkCancellation: @Sendable () throws -> Void) async throws {
        var lastState = "unavailable"
        // Face ID can report success several seconds before the system overlay
        // returns the originating scene to active. The former two-second budget
        // rejected successful authentication on a physical iPhone. Background
        // and explicit cancellation still revoke the request during this wait.
        for _ in 0..<AuthenticationReturnPolicy.maximumPollCount {
            try checkCancellation()
            // Allow SwiftUI's scenePhase update to settle before a write lease is checked.
            try await Task.sleep(for: AuthenticationReturnPolicy.pollInterval)
            try checkCancellation()
            guard let signals = readSignals() else { throw ApiRelayError.systemAuthenticationFailed }
            lastState = "app=\(String(describing: signals.applicationIsActive.knownValue)) scene=\(String(describing: signals.sceneIsForegroundActive.knownValue)) key=\(String(describing: signals.isKeyWindow.knownValue)) appearance=\(String(describing: signals.activeAppearanceIsActive.knownValue)) windowFocusRequired=\(signals.requiresWindowFocus)"
            if signals.applicationIsActive.knownValue == true,
               signals.sceneIsForegroundActive.knownValue == true,
               AppLockScenePresence.hostIsUserFacing(signals) { return }
        }
        Self.logger.error("Authentication return timed out: \(lastState, privacy: .public)")
        AuthenticationTrace.emit("return timeout: \(lastState)")
        throw ApiRelayError.authenticationCancelled
    }
}

#elseif canImport(AppKit)
@MainActor
private final class AuthenticationSceneWitness {
    weak var window: NSWindow?
    init() { window = NSApp.keyWindow }
    func waitUntilActive(checkCancellation: @Sendable () throws -> Void) async throws {
        for _ in 0..<AuthenticationReturnPolicy.maximumPollCount {
            try checkCancellation()
            try await Task.sleep(for: AuthenticationReturnPolicy.pollInterval)
            if NSApp.isActive, window?.isKeyWindow == true { return }
        }
        throw ApiRelayError.authenticationCancelled
    }
}

#endif
