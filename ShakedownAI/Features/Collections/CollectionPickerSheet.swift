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
            ZStack {
                SpaceBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(show.shortName)
                            .font(Theme.mono(13, weight: .semibold))
                            .foregroundStyle(Theme.accent)

                        ForEach(env.library.collections, id: \.persistentModelID) { collection in
                            let alreadyIn = collection.items.contains { $0.showIdentifier == show.identifier }
                            let saved = alreadyIn || savedTo == collection.name
                            Button {
                                env.library.add(show: show, to: collection)
                                withAnimation(.snappy) { savedTo = collection.name }
                            } label: {
                                HStack {
                                    Image(systemName: collection.iconName)
                                        .foregroundStyle(Theme.accent)
                                        .frame(width: 28)
                                    Text(collection.name)
                                        .font(Theme.body)
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Image(systemName: saved ? "checkmark.circle.fill" : "plus.circle")
                                        .foregroundStyle(saved ? Theme.sage : Theme.textTertiary)
                                        .contentTransition(.symbolEffect(.replace))
                                }
                                .padding(13)
                                .cardStyle()
                            }
                            .buttonStyle(.plain)
                            .disabled(alreadyIn)
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
                                    .foregroundStyle(Theme.accent)
                            }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(.top, 6)
                    }
                    .padding(Theme.screenPadding)
                }
            }
            .navigationTitle("Save Show")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.success, trigger: savedTo)
    }
}
