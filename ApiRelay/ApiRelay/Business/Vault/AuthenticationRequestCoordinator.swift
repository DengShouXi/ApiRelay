import Foundation
import LocalAuthentication

/// Capability for exactly one authentication request. Cleanup code must retain
/// this value and cancel by handle; an owner is intentionally too coarse because
/// a later screen can start another request in the same owner group.
nonisolated struct AuthenticationRequestHandle: Hashable, Sendable {
    fileprivate let id: UUID
    let owner: AuthenticationRequestOwner

    fileprivate init(owner: AuthenticationRequestOwner) {
        self.id = UUID()
        self.owner = owner
    }
}

/// One page/operation-owned cancellation capability. The task-local binding lets
/// business services reach `RevealGate` without threading UI identity through
/// every service protocol. A scope is one-shot: once its page cleans up, a late
/// authentication begin is rejected instead of resurrecting the stale request.
nonisolated final class AuthenticationRequestScope: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false
    private var request: AuthenticationRequestHandle?
    private var cancelRequest: (@Sendable () -> Void)?

    func perform<T>(_ operation: () async throws -> T) async rethrows -> T {
        try await AuthenticationRequestTaskContext.$scope.withValue(self) {
            try await operation()
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        request = nil
        let cancelRequest = self.cancelRequest
        self.cancelRequest = nil
        lock.unlock()
        cancelRequest?()
    }

    fileprivate func install(
        _ request: AuthenticationRequestHandle,
        cancel: @escaping @Sendable () -> Void
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return false }
        self.request = request
        cancelRequest = cancel
        return true
    }

    fileprivate func clear(_ request: AuthenticationRequestHandle) {
        lock.lock()
        if self.request == request {
            self.request = nil
            cancelRequest = nil
        }
        lock.unlock()
    }
}

nonisolated private enum AuthenticationRequestTaskContext {
    @TaskLocal static var scope: AuthenticationRequestScope?
}

/// Owns the one system/app-password authentication request that may be active.
///
/// The coordinator is intentionally non-actor-isolated: lifecycle callbacks must
/// be able to revoke an `LAContext` synchronously while `RevealGate` is suspended.
/// Request ownership is enforced here, rather than being inferred from whichever
/// SwiftUI screen happened to send a cleanup callback.
nonisolated final class AuthenticationRequestCoordinator: @unchecked Sendable {
    private struct ActiveRequest {
        let handle: AuthenticationRequestHandle
        let scope: AuthenticationRequestScope?
        var context: LAContext?
        var cancelAction: (@Sendable () -> Void)?
    }

    private let lock = NSLock()
    private var active: ActiveRequest?

    @discardableResult
    func begin(owner: AuthenticationRequestOwner) throws -> AuthenticationRequestHandle {
        let handle = AuthenticationRequestHandle(owner: owner)
        let scope = AuthenticationRequestTaskContext.scope
        lock.lock()
        if let current = active,
           current.handle.owner != .content,
           owner == .content {
            lock.unlock()
            throw ApiRelayError.authenticationCancelled
        }
        if let scope,
           !scope.install(handle, cancel: { [weak self] in
               self?.cancel(request: handle)
           }) {
            lock.unlock()
            throw ApiRelayError.authenticationCancelled
        }
        let previousHandle = active?.handle
        let previousScope = active?.scope
        let previousContext = active?.context
        let previousCancel = active?.cancelAction
        active = ActiveRequest(
            handle: handle,
            scope: scope,
            context: nil,
            cancelAction: nil
        )
        lock.unlock()

        if let previousHandle { previousScope?.clear(previousHandle) }
        previousContext?.invalidate()
        previousCancel?()
        return handle
    }

    func setCancelAction(
        request: AuthenticationRequestHandle,
        _ action: @escaping @Sendable () -> Void
    ) {
        lock.lock()
        let valid = active?.handle == request
        if valid { active?.cancelAction = action }
        lock.unlock()
        if !valid { action() }
    }

    func replaceContext(_ next: LAContext?, request: AuthenticationRequestHandle) throws {
        lock.lock()
        guard active?.handle == request else {
            lock.unlock()
            next?.invalidate()
            throw ApiRelayError.authenticationCancelled
        }
        let previous = active?.context
        active?.context = next
        lock.unlock()
        previous?.invalidate()
    }

    func clearIfCurrent(_ request: AuthenticationRequestHandle) {
        lock.lock()
        let scope: AuthenticationRequestScope?
        if active?.handle == request {
            scope = active?.scope
            active = nil
        } else {
            scope = nil
        }
        lock.unlock()
        scope?.clear(request)
    }

    func throwIfCancelled(_ request: AuthenticationRequestHandle) throws {
        lock.lock()
        let current = active?.handle
        lock.unlock()
        guard current == request else {
            throw ApiRelayError.authenticationCancelled
        }
    }

    func isActive(owner: AuthenticationRequestOwner? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let active else { return false }
        return owner == nil || active.handle.owner == owner
    }

    func activeOwner() -> AuthenticationRequestOwner? {
        lock.lock()
        defer { lock.unlock() }
        return active?.handle.owner
    }

    func cancel(owner: AuthenticationRequestOwner) {
        lock.lock()
        guard active?.handle.owner == owner else {
            lock.unlock()
            return
        }
        let context = active?.context
        let action = active?.cancelAction
        let handle = active?.handle
        let scope = active?.scope
        active = nil
        lock.unlock()
        if let handle { scope?.clear(handle) }
        context?.invalidate()
        action?()
    }

    /// Request-scoped cleanup. A stale handle is a no-op and therefore cannot
    /// revoke the newer request that replaced it, even when owners are equal.
    func cancel(request: AuthenticationRequestHandle) {
        lock.lock()
        guard active?.handle == request else {
            lock.unlock()
            return
        }
        let context = active?.context
        let action = active?.cancelAction
        let scope = active?.scope
        active = nil
        lock.unlock()
        scope?.clear(request)
        context?.invalidate()
        action?()
    }

    func cancelAll() {
        lock.lock()
        let context = active?.context
        let action = active?.cancelAction
        let handle = active?.handle
        let scope = active?.scope
        active = nil
        lock.unlock()
        if let handle { scope?.clear(handle) }
        context?.invalidate()
        action?()
    }
}
