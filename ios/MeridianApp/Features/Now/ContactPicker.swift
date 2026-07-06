// ContactPicker.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// iOS-native replacement for Android's `ActivityResultContracts.PickContact`.
// Presents a searchable list of system contacts (Contacts framework, limited-access
// aware) and returns the chosen contact's display name to the caller.
//
// Requires NSContactsUsageDescription in Info.plist.

import SwiftUI
import Contacts
import UIKit

// MARK: - ContactPickerResult

/// A single pickable contact row.
struct ContactPickerResult: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
}

// MARK: - ContactPicker

/// A sheet that searches system contacts and calls `onPick` with the selected name.
///
/// The Contacts framework store is owned by an actor (`ContactsRepository`), so it never
/// crosses the main actor; we only ever receive `Sendable` `ContactPickerResult` values.
struct ContactPicker: View {

    /// Invoked with the chosen contact's display name; the sheet dismisses afterwards.
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    // Contacts access is funneled through the shared actor.
    private let repository = ContactsRepository()

    @State private var query: String = ""
    @State private var results: [ContactPickerResult] = []
    @State private var accessState: PermissionState = .notDetermined
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                MeridianColors.background.ignoresSafeArea()

                Group {
                    switch accessState {
                    case .denied:
                        deniedState
                    case .notDetermined:
                        // Requesting; show a spinner until resolved.
                        ProgressView()
                            .tint(MeridianColors.primary)
                    case .granted, .limited:
                        contactList
                    }
                }
            }
            .navigationTitle("Pick a Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(MeridianColors.primary)
                }
            }
            .searchable(text: $query, prompt: "Search contacts")
        }
        .preferredColorScheme(.dark)
        .task {
            accessState = await repository.requestAccess() ? .granted : .denied
        }
        .onChange(of: query) { _, newValue in
            scheduleSearch(newValue)
        }
    }

    // MARK: - States

    private var contactList: some View {
        List {
            if isSearching {
                HStack {
                    ProgressView().tint(MeridianColors.primary)
                    Text("Searching…")
                        .font(.bodyMedium)
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                }
                .listRowBackground(Color.clear)
            } else if query.isEmpty {
                Text("Type a name to search your contacts.")
                    .font(.bodyMedium)
                    .foregroundStyle(MeridianColors.onSurfaceVariant)
                    .listRowBackground(Color.clear)
            } else if results.isEmpty {
                Text("No matches for \"\(query)\".")
                    .font(.bodyMedium)
                    .foregroundStyle(MeridianColors.onSurfaceVariant)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(results) { contact in
                    Button {
                        onPick(contact.name)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 22))
                                .foregroundStyle(MeridianColors.primary.opacity(0.8))
                            Text(contact.name)
                                .font(.titleMedium)
                                .foregroundStyle(MeridianColors.onSurface)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var deniedState: some View {
        EmptyStateView(
            icon: "person.crop.circle.badge.exclamationmark",
            title: "Contacts Access Off",
            message: "Enable Contacts access in Settings to pick a name, or type it manually.",
            actionLabel: "Open Settings",
            action: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        )
    }

    // MARK: - Search

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            // `searchContacts` already returns Sendable `[ContactPickerResult]`,
            // mapped + deduped inside the repository actor — no CNContact crosses the boundary.
            let found = await repository.searchContacts(query: trimmed)
            if Task.isCancelled { return }
            results = found
            isSearching = false
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("ContactPicker") {
    ContactPicker(onPick: { _ in })
}
#endif
