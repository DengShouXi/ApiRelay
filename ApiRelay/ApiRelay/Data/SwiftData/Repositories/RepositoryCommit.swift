import Foundation

/// Final synchronous authorization seam around one concrete SwiftData mutation.
///
/// Callers may bind this closure to `SessionLockQuerying.commitAuthorizationLease`.
/// Repository implementations must invoke it around the actual model mutation and
/// `ModelContext.save()` without suspending in between.
typealias RepositoryCommit = @Sendable (_ operation: () throws -> Void) throws -> Void
