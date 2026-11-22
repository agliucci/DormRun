import Foundation

/// Local Stripe Connect bank-link state until profiles.stripe_account_id is live end-to-end.
enum RunnerPayoutStore: Sendable {
    private nonisolated static let bankLinkedKey = "dormrun.runner.bankLinked"

    nonisolated static var isBankLinked: Bool {
        get { UserDefaults.standard.bool(forKey: bankLinkedKey) }
        set { UserDefaults.standard.set(newValue, forKey: bankLinkedKey) }
    }

    nonisolated static func markLinkedFromReturnURL() {
        isBankLinked = true
    }
}
