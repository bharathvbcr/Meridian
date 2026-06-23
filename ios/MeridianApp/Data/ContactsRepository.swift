// ContactsRepository.swift
// Meridian — iOS 27, Swift 6, strict concurrency
//
// Actor-isolated wrapper around the Contacts framework with modern (limited-access aware)
// authorization. Requires NSContactsUsageDescription in Info.plist.

import Contacts
import Foundation

// MARK: - ContactsRepository

/// Actor that serialises all `CNContactStore` access, satisfying Swift 6 strict-concurrency
/// requirements. `CNContactStore` is not `Sendable`, so it never crosses the actor boundary.
///
/// Search results are mapped to the `Sendable` `ContactPickerResult` DTO *inside* the actor —
/// `CNContact` (a non-`Sendable` Objective-C class) is never returned across an isolation
/// boundary.
actor ContactsRepository {

    // MARK: Private state

    private let store = CNContactStore()

    /// Keys fetched on every search. Static to avoid re-allocation per call.
    private static let fetchKeys: [CNKeyDescriptor] = [
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactMiddleNameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactPostalAddressesKey as CNKeyDescriptor,
        CNContactImageDataAvailableKey as CNKeyDescriptor,
        CNContactThumbnailImageDataKey as CNKeyDescriptor,
    ]

    // MARK: - Authorization

    /// Current `CNAuthorizationStatus` for the contacts entity.
    var authorizationStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    /// `true` when the app can read at least some contacts (full or limited access).
    var hasReadAccess: Bool {
        switch authorizationStatus {
        case .authorized, .limited:
            return true
        default:
            return false
        }
    }

    /// Prompts for contacts access if not yet determined. Returns `true` when access is
    /// granted — including iOS 18+ *limited* access, which still permits search.
    func requestAccess() async -> Bool {
        switch authorizationStatus {
        case .authorized, .limited:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            break
        @unknown default:
            return false
        }

        // requestAccess(for:) returns `true` for both full and limited grants.
        let granted = (try? await store.requestAccess(for: .contacts)) ?? false
        return granted || hasReadAccess
    }

    // MARK: - Searching

    /// Searches contacts whose composite name contains `query` (case-insensitive).
    /// Returns an empty array when access is missing, `query` is empty, or the fetch throws.
    ///
    /// `CNContact` values are mapped to `Sendable` `ContactPickerResult` rows while still on the
    /// actor, so no non-`Sendable` value crosses the isolation boundary to the caller.
    func searchContacts(query: String) async -> [ContactPickerResult] {
        guard hasReadAccess, !query.isEmpty else { return [] }

        let predicate = CNContact.predicateForContacts(matchingName: query)
        return enumerate(matching: predicate)
    }

    /// Returns contacts whose email addresses contain `email` — useful for matching
    /// Plan-screen participants to real contacts.
    ///
    /// Maps to `Sendable` `ContactPickerResult` rows inside the actor (see `searchContacts(query:)`).
    func searchContacts(matchingEmail email: String) async -> [ContactPickerResult] {
        guard hasReadAccess, !email.isEmpty else { return [] }

        let predicate = CNContact.predicateForContacts(matchingEmailAddress: email)
        return enumerate(matching: predicate)
    }

    // MARK: - Private

    /// Runs a unified-contacts enumeration with the standard fetch keys and maps each matched
    /// `CNContact` to a `Sendable` `ContactPickerResult` (deduping by identifier) — all while
    /// synchronously isolated to the actor, keeping concurrency safe.
    private func enumerate(matching predicate: NSPredicate) -> [ContactPickerResult] {
        let request = CNContactFetchRequest(keysToFetch: Self.fetchKeys)
        request.predicate = predicate
        request.sortOrder = .familyName

        do {
            var results: [ContactPickerResult] = []
            var seen: Set<String> = []
            try store.enumerateContacts(with: request) { contact, _ in
                let id = contact.identifier
                guard seen.insert(id).inserted else { return }
                results.append(
                    ContactPickerResult(id: id, name: contact.displayName)
                )
            }
            return results
        } catch {
            return []
        }
    }
}

// MARK: - CNContact convenience helpers (nonisolated, Sendable-safe)

extension CNContact {
    /// Full display name from given + family components, falling back to organisation name.
    var displayName: String {
        let full = CNContactFormatter.string(from: self, style: .fullName) ?? ""
        if !full.isEmpty { return full }
        return organizationName.isEmpty ? "(No Name)" : organizationName
    }

    /// Primary email address, or `nil` when none is set.
    var primaryEmail: String? {
        emailAddresses.first.map { $0.value as String }
    }
}
