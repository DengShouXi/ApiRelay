import Foundation

/// Presentation only. Never authorizes a vault write; that remains a StoreKit
/// transaction check inside KeyVaultService.
enum EntitlementDisplayState: Equatable {
    case checking
    case free
    case owned
    case unavailable

    init(tier: EntitlementTier) {
        self = tier == .free ? .free : .owned
    }

    var isOwned: Bool { self == .owned }
    var canPurchase: Bool { self == .free }

    var accessibilityCode: String {
        switch self {
        case .checking: "checking"
        case .free: "free"
        case .owned: "owned"
        case .unavailable: "unavailable"
        }
    }
}

/// `nil` from KeyVaultServing.remainingFreeQuota means unlimited, not an error.
/// Keep failures distinct before they reach the view.
enum FreeQuotaDisplayState: Equatable {
    case checking
    case free(remaining: Int)
    case unlimited
    case unavailable

    init(remaining: Int?) {
        if let remaining {
            self = .free(remaining: remaining)
        } else {
            self = .unlimited
        }
    }
}

extension Notification.Name {
    static let entitlementDidChange = Notification.Name("ApiRelay.entitlementDidChange")
}
