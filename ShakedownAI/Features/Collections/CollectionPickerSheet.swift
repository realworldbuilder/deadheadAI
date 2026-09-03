import SwiftUI

/// "Save to collection" picker, opened from a show page.
struct CollectionPickerSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let show: Show
    @State private var savedTo: String?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(show.shortName)
                        .font(Theme.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)

                    let collections = env.library.collections
                    VStack(spacing: 0) {
                        ForEach(Array(collections.enumerated()), id: \.element.persistentModelID) { index, collection in
                            let alreadyIn = (collection.items ?? []).contains { $0.showIdentifier == show.identifier }
                            let saved = alreadyIn || savedTo == collection.name
                            Button {
                                env.library.add(show: show, to: collection)
                                withAnimation(.snappy) { savedTo = collection.name }
                            } label: {
                                HStack {
                                    Image(systemName: collection.iconName)
                                        .foregroundStyle(Theme.textSecondary)
                                        .frame(width: 28)
                                    Text(collection.name)
                                        .font(Theme.body)
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Image(systemName: saved ? "checkmark.circle.fill" : "plus.circle")
                                        .foregroundStyle(saved ? Theme.sage : Theme.textTertiary)
                                        .contentTransition(.symbolEffect(.replace))
                                }
                                .listRowStyle(divider: index < collections.count - 1)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(alreadyIn)
                        }
                    }

                    HStack(spacing: 10) {
                        TextField("New collection…", text: $newName)
                            .font(Theme.body)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                        Button {
                            let collection = env.library.createCollection(name: newName)
                            env.library.add(show: show, to: collection)
                            withAnimation(.snappy) { savedTo = collection.name }
                            newName = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Create collection and save")
                    }
                    .padding(.top, 6)
                }
                .padding(Theme.screenPadding)
            }
            .background(Theme.background)
            .navigationTitle("Save Show")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
        .sensoryFeedback(.success, trigger: savedTo)
    }
}
