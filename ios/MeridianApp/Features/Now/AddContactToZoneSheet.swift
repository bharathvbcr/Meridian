// AddContactToZoneSheet.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// Ported from `AddContactToZoneDialog` in `NowScreen.kt`.
//
// A glass form sheet for adding a starred contact to a zone. The user can type a name
// or tap the person button to pick one from system contacts (via `ContactPicker`).
// Confirming calls `onConfirm(trimmedName)`.

import SwiftUI

// MARK: - AddContactToZoneSheet

struct AddContactToZoneSheet: View {

    /// Display name of the zone the contact is being added to.
    let zoneName: String
    /// Called with the trimmed contact name when the user taps Add.
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var showContactPicker = false
    @FocusState private var nameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MeridianColors.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: MeridianSpacing.lg.rawValue) {
                    Text("Add a starred contact in this zone — they appear on Plan automatically.")
                        .font(.bodyMedium)
                        .foregroundStyle(MeridianColors.onSurfaceVariant)

                    HStack(spacing: MeridianSpacing.sm.rawValue) {
                        TextField("Name", text: $name)
                            .textFieldStyle(.plain)
                            .font(.titleMedium)
                            .foregroundStyle(MeridianColors.onSurface)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit { confirmIfValid() }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            .background {
                                RoundedRectangle(cornerRadius: MeridianRadius.small.rawValue, style: .continuous)
                                    .fill(MeridianColors.surface.opacity(0.6))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: MeridianRadius.small.rawValue, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                                    }
                            }

                        Button {
                            showContactPicker = true
                        } label: {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(MeridianColors.primary)
                        }
                        .accessibilityLabel("Pick from contacts")
                    }

                    Spacer()
                }
                .padding(MeridianSpacing.xl.rawValue)
            }
            .navigationTitle("Add to \(zoneName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { confirmIfValid() }
                        .font(.titleMedium)
                        .foregroundStyle(trimmedName.isEmpty ? MeridianColors.onSurfaceVariant : MeridianColors.primary)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .sheet(isPresented: $showContactPicker) {
                ContactPicker { pickedName in
                    name = pickedName
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear { nameFocused = true }
    }

    private func confirmIfValid() {
        guard !trimmedName.isEmpty else { return }
        onConfirm(trimmedName)
        dismiss()
    }
}

// MARK: - Previews

#if DEBUG
#Preview("AddContactToZoneSheet") {
    Color.black
        .sheet(isPresented: .constant(true)) {
            AddContactToZoneSheet(zoneName: "Tokyo", onConfirm: { _ in })
        }
}
#endif
