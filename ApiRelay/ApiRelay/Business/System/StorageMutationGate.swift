import Foundation

extension Notification.Name {
    nonisolated static let crossStoreRecoveryStateDidChange = Notification.Name(
        "com.apirelay.crossStoreRecoveryStateDidChange"
    )
}

/// An unforgeable, erase-generation-scoped capability.
///
/// Only `StorageMutationGate` can construct one, and only while that exact gate
/// is sealed. Services that deliberately bypass the normal write fence during
/// a committed full erase must require this type instead of a Boolean escape
/// hatch. Reopening the gate permanently invalidates every token from that
/// erase generation.
nonisolated final class CommittedEraseToken: @unchecked Sendable {
    fileprivate let gate: StorageMutationGate
    fileprivate let generation: UUID

    fileprivate nonisolated init(
        gate: StorageMutationGate,
        generation: UUID
    ) {
        self.gate = gate
        self.generation = generation
    }

    /// Stores that do not themselves own the process mutation gate (for
    /// example, the durable integrity-quarantine marker) can still prove that
    /// the issuing gate remains sealed for this exact erase generation.
    nonisolated func validate(operation: String) throws {
        try gate.validateCommittedEraseToken(self, operation: operation)
    }
}

/// Process-wide write fence shared by every service that can mutate protected
/// application storage.
///
/// Normal operations hold a short-lived permit for the complete transaction.
/// An authenticated full erase seals the gate synchronously with its durable
/// journal marker, then asynchronously waits for already-started transactions
/// to finish before deleting anything. No lock is held across storage I/O or an
/// `await`, so the fence cannot deadlock Swift actors or Keychain callbacks.
nonisolated final class StorageMutationGate: @unchecked Sendable {
    private struct ExclusiveRequest {
        let id: UUID
        let operation: String
        let continuation: CheckedContinuation<StorageExclusiveMutationPermit, Error>
    }

    private let lock = NSLock()
    private var eraseSealed: Bool
    private var eraseGeneration: UUID?
    /// A crash-durable cross-store journal exists and must be replayed before
    /// ordinary storage can be observed or changed.
    private var crossStoreRecoverySealed: Bool
    private var activeNormalMutations = 0
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []
    private var exclusiveActive = false
    private var exclusiveRequests: [ExclusiveRequest] = []

    nonisolated init(
        erasePending: Bool = false,
        crossStoreRecoveryPending: Bool = false
    ) {
        self.eraseSealed = erasePending
        self.eraseGeneration = erasePending ? UUID() : nil
        self.crossStoreRecoverySealed = crossStoreRecoveryPending
    }

    /// Starts one normal write transaction. A pending/interrupted erase is
    /// fail-closed: callers must not touch any repository or Keychain item.
    nonisolated func beginNormal(operation: String) throws -> StorageMutationPermit {
        lock.lock()
        defer { lock.unlock() }
        guard !eraseSealed,
              !crossStoreRecoverySealed,
              !exclusiveActive,
              exclusiveRequests.isEmpty else {
            throw ApiRelayError.storageRecoveryFailed(
                operation: operation,
                detail: gateClosedDetailLocked()
            )
        }
        activeNormalMutations += 1
        return StorageMutationPermit(gate: self)
    }

    /// Acquires the process-wide cross-store transaction permit.
    ///
    /// Registration is synchronous under the same lock as `beginNormal`: from
    /// that instant new ordinary mutations fail closed. The request then waits
    /// for every already-admitted mutation to finish before it becomes active.
    /// Queued exclusive requests are FIFO, so an import and a key creation can
    /// never compensate over one another's committed state.
    nonisolated func beginExclusive(
        operation: String
    ) async throws -> StorageExclusiveMutationPermit {
        let requestID = UUID()
        let permit = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                var immediateFailure: Error?
                var activated: ExclusiveRequest?
                lock.lock()
                if Task.isCancelled {
                    immediateFailure = CancellationError()
                } else if eraseSealed || crossStoreRecoverySealed {
                    immediateFailure = ApiRelayError.storageRecoveryFailed(
                        operation: operation,
                        detail: gateClosedDetailLocked()
                    )
                } else {
                    exclusiveRequests.append(ExclusiveRequest(
                        id: requestID,
                        operation: operation,
                        continuation: continuation
                    ))
                    activated = activateNextExclusiveLocked()
                }
                lock.unlock()

                if let immediateFailure {
                    continuation.resume(throwing: immediateFailure)
                } else if let activated {
                    activated.continuation.resume(
                        returning: StorageExclusiveMutationPermit(gate: self)
                    )
                }
            }
        } onCancel: {
            self.cancelExclusiveRequest(requestID)
        }
        do {
            try Task.checkCancellation()
            return permit
        } catch {
            permit.finish()
            throw error
        }
    }

    /// Startup-only entry for replaying an already durable cross-store marker.
    /// Normal exclusive acquisition deliberately rejects this state.
    nonisolated func beginCrossStoreRecoveryExclusive(
        operation: String
    ) async throws -> StorageExclusiveMutationPermit {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            guard crossStoreRecoverySealed,
                  !eraseSealed,
                  !exclusiveActive,
                  exclusiveRequests.isEmpty,
                  activeNormalMutations == 0 else {
                let detail = gateClosedDetailLocked()
                lock.unlock()
                continuation.resume(throwing: ApiRelayError.storageRecoveryFailed(
                    operation: operation,
                    detail: detail
                ))
                return
            }
            exclusiveActive = true
            lock.unlock()
            continuation.resume(returning: StorageExclusiveMutationPermit(gate: self))
        }
    }

    /// If compensation or journal finalization becomes uncertain, keep the
    /// process sealed after the current exclusive permit is released. The same
    /// durable marker will drive idempotent startup recovery on the next launch.
    nonisolated func sealForCrossStoreRecovery() {
        let failed: [ExclusiveRequest]
        lock.lock()
        crossStoreRecoverySealed = true
        failed = exclusiveRequests
        exclusiveRequests.removeAll(keepingCapacity: false)
        lock.unlock()
        for request in failed {
            request.continuation.resume(throwing: ApiRelayError.storageRecoveryFailed(
                operation: request.operation,
                detail: "cross_store_recovery_pending"
            ))
        }
        NotificationCenter.default.post(
            name: .crossStoreRecoveryStateDidChange,
            object: nil
        )
    }

    /// Reopens ordinary writes only after the durable cross-store marker has
    /// been removed and the recovery permit itself has been released.
    nonisolated func completeCrossStoreRecoveryAndReopen() throws {
        lock.lock()
        guard crossStoreRecoverySealed,
              !eraseSealed,
              !exclusiveActive,
              exclusiveRequests.isEmpty,
              activeNormalMutations == 0 else {
            lock.unlock()
            throw ApiRelayError.storageRecoveryFailed(
                operation: "cross_store_recovery_complete",
                detail: "invalid_state"
            )
        }
        crossStoreRecoverySealed = false
        lock.unlock()
        NotificationCenter.default.post(
            name: .crossStoreRecoveryStateDidChange,
            object: nil
        )
    }

    /// Called inside the same synchronous session-authorization commit as the
    /// first durable erase marker. Returns true only when this call created the
    /// seal, allowing the caller to reopen if journal persistence fails.
    nonisolated func sealForErase(resumingInterruptedErase: Bool) throws -> Bool {
        let failed: [ExclusiveRequest]
        lock.lock()
        if eraseSealed {
            guard resumingInterruptedErase else {
                lock.unlock()
                throw ApiRelayError.storageRecoveryFailed(
                    operation: "erase_all_user_data",
                    detail: "erase_already_in_progress"
                )
            }
            precondition(eraseGeneration != nil, "sealed erase gate has no generation")
            lock.unlock()
            return false
        }
        guard !crossStoreRecoverySealed || resumingInterruptedErase else {
            lock.unlock()
            throw ApiRelayError.storageRecoveryFailed(
                operation: "erase_all_user_data",
                detail: "cross_store_recovery_pending"
            )
        }
        eraseSealed = true
        eraseGeneration = UUID()
        // When device-owner recovery explicitly supersedes an unreplayable
        // cross-store marker, retain that seal until the committed erase has
        // purged every store and discarded the marker. New ordinary work stays
        // fail-closed throughout the transition.
        failed = exclusiveRequests
        exclusiveRequests.removeAll(keepingCapacity: false)
        lock.unlock()
        for request in failed {
            request.continuation.resume(throwing: ApiRelayError.storageRecoveryFailed(
                operation: request.operation,
                detail: "erase_in_progress"
            ))
        }
        return true
    }

    /// Mints the only capability accepted by committed-erase bypass paths.
    /// A caller cannot obtain one before the gate's irreversible seal.
    nonisolated func mintCommittedEraseToken() throws -> CommittedEraseToken {
        lock.lock()
        defer { lock.unlock() }
        guard eraseSealed, let eraseGeneration else {
            throw ApiRelayError.storageRecoveryFailed(
                operation: "erase_capability_issue",
                detail: "erase_not_sealed"
            )
        }
        return CommittedEraseToken(gate: self, generation: eraseGeneration)
    }

    /// Validates both object identity and erase generation. A token from a
    /// different (even currently sealed) gate is never accepted.
    nonisolated func validateCommittedEraseToken(
        _ token: CommittedEraseToken,
        operation: String
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard eraseSealed,
              token.gate === self,
              let eraseGeneration,
              token.generation == eraseGeneration else {
            throw ApiRelayError.storageRecoveryFailed(
                operation: operation,
                detail: "invalid_committed_erase_capability"
            )
        }
    }

    /// Only valid when the first durable marker failed. Once any erase marker
    /// exists, the gate intentionally remains sealed until authenticated replay
    /// has completed the whole idempotent transaction.
    nonisolated func abortNewSealAfterJournalFailure(_ createdSeal: Bool) {
        guard createdSeal else { return }
        lock.lock()
        eraseSealed = false
        eraseGeneration = nil
        lock.unlock()
    }

    /// Waits without blocking a thread until every transaction that won before
    /// the erase seal has either committed or completed its compensation.
    nonisolated func waitUntilNormalMutationsDrain() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if activeNormalMutations == 0, !exclusiveActive {
                lock.unlock()
                continuation.resume()
            } else {
                drainWaiters.append(continuation)
                lock.unlock()
            }
        }
    }

    /// Reopens normal writes only after all data is gone and the durable erase
    /// journal has itself been cleared.
    nonisolated func completeEraseAndReopen() throws {
        lock.lock()
        guard eraseSealed,
              activeNormalMutations == 0,
              !exclusiveActive,
              exclusiveRequests.isEmpty else {
            lock.unlock()
            throw ApiRelayError.storageRecoveryFailed(
                operation: "erase_gate_complete",
                detail: "invalid_state"
            )
        }
        eraseSealed = false
        eraseGeneration = nil
        // A committed full erase supersedes any interrupted provisional
        // transaction. Its durable marker must already have been discarded by
        // DataLifecycleService before this combined seal is reopened.
        crossStoreRecoverySealed = false
        lock.unlock()
        NotificationCenter.default.post(
            name: .crossStoreRecoveryStateDidChange,
            object: nil
        )
    }

    nonisolated func isEraseSealed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return eraseSealed
    }

    nonisolated func isCrossStoreRecoverySealed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return crossStoreRecoverySealed
    }

    nonisolated func isCrossStoreExclusivePendingOrActive() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return exclusiveActive || !exclusiveRequests.isEmpty
    }

    fileprivate nonisolated func finishNormalMutation() {
        let ready: [CheckedContinuation<Void, Never>]
        lock.lock()
        precondition(activeNormalMutations > 0, "unbalanced StorageMutationPermit")
        activeNormalMutations -= 1
        let activated = activateNextExclusiveLocked()
        if activeNormalMutations == 0, !exclusiveActive {
            ready = drainWaiters
            drainWaiters.removeAll(keepingCapacity: false)
        } else {
            ready = []
        }
        lock.unlock()
        ready.forEach { $0.resume() }
        if let activated {
            activated.continuation.resume(
                returning: StorageExclusiveMutationPermit(gate: self)
            )
        }
    }

    fileprivate nonisolated func finishExclusiveMutation() {
        let ready: [CheckedContinuation<Void, Never>]
        let activated: ExclusiveRequest?
        lock.lock()
        precondition(exclusiveActive, "unbalanced StorageExclusiveMutationPermit")
        exclusiveActive = false
        activated = activateNextExclusiveLocked()
        if activeNormalMutations == 0, !exclusiveActive {
            ready = drainWaiters
            drainWaiters.removeAll(keepingCapacity: false)
        } else {
            ready = []
        }
        lock.unlock()
        ready.forEach { $0.resume() }
        if let activated {
            activated.continuation.resume(
                returning: StorageExclusiveMutationPermit(gate: self)
            )
        }
    }

    /// Must be called with `lock` held. Returns the request whose continuation
    /// must be resumed after unlocking.
    private nonisolated func activateNextExclusiveLocked() -> ExclusiveRequest? {
        guard !eraseSealed,
              !crossStoreRecoverySealed,
              !exclusiveActive,
              activeNormalMutations == 0,
              !exclusiveRequests.isEmpty else {
            return nil
        }
        exclusiveActive = true
        return exclusiveRequests.removeFirst()
    }

    private nonisolated func cancelExclusiveRequest(_ id: UUID) {
        let cancelled: ExclusiveRequest?
        lock.lock()
        if let index = exclusiveRequests.firstIndex(where: { $0.id == id }) {
            cancelled = exclusiveRequests.remove(at: index)
        } else {
            cancelled = nil
        }
        lock.unlock()
        cancelled?.continuation.resume(throwing: CancellationError())
    }

    private nonisolated func gateClosedDetailLocked() -> String {
        if eraseSealed { return "erase_in_progress" }
        if crossStoreRecoverySealed { return "cross_store_recovery_pending" }
        return "cross_store_transaction_in_progress"
    }
}

/// Idempotently releases one normal mutation slot. Callers should use
/// `defer { permit.finish() }`; `deinit` is a final safety net for thrown paths.
nonisolated final class StorageMutationPermit: @unchecked Sendable {
    private let lock = NSLock()
    private var gate: StorageMutationGate?

    fileprivate nonisolated init(gate: StorageMutationGate) {
        self.gate = gate
    }

    nonisolated func finish() {
        let ownedGate: StorageMutationGate?
        lock.lock()
        ownedGate = gate
        gate = nil
        lock.unlock()
        ownedGate?.finishNormalMutation()
    }

    deinit {
        finish()
    }
}

/// Idempotently releases the single cross-store transaction slot.
nonisolated final class StorageExclusiveMutationPermit: @unchecked Sendable {
    private let lock = NSLock()
    private var gate: StorageMutationGate?

    fileprivate nonisolated init(gate: StorageMutationGate) {
        self.gate = gate
    }

    nonisolated func finish() {
        let ownedGate: StorageMutationGate?
        lock.lock()
        ownedGate = gate
        gate = nil
        lock.unlock()
        ownedGate?.finishExclusiveMutation()
    }

    deinit {
        finish()
    }
}
