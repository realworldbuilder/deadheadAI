import SwiftUI

/// Gets the phone on the bus: the code from the head's page on the notesfile.
struct PairSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var problem: String?
    @State private var isWorking = false
    @FocusState private var focused: Bool

    private var siteURL: URL? { env.api?.url(path: "/me") }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("On the notesfile, open your page and tap Get the phone on the bus. It shows a code. Type it here.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)

                TextField("ROSE-77", text: $code)
                    .font(.system(.title2, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke))
                    .focused($focused)
                    .onSubmit(pair)
                    .accessibilityLabel("Code from the notesfile")

                if let problem {
                    Text(problem)
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.accent)
                }

                Button {
                    pair()
                } label: {
                    if isWorking {
                        ProgressView().tint(.white).frame(maxWidth: .infinity)
                    } else {
                        Text("Get on the Bus").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.primary(fullWidth: true))
                .disabled(isWorking || code.trimmingCharacters(in: .whitespaces).count < 6)

                if let siteURL {
                    Link(destination: siteURL) {
                        Label("No handle yet? Get on the bus on the notesfile first", systemImage: "arrow.up.right")
                            .font(Theme.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Text("From then on this phone rides as your handle: same shelves, mix tapes and journal as the web, and it shows up in the lot while it's spinning.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)

                Spacer()
            }
            .padding(Theme.screenPadding)
            .background(Theme.background)
            .navigationTitle("Get on the Bus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
    }

    private func pair() {
        guard !isWorking else { return }
        isWorking = true
        problem = nil
        let entered = code
        Task {
            do {
                _ = try await env.authProvider.pair(code: entered)
                dismiss()
            } catch NetheadAPIError.message(let text) {
                problem = text
            } catch NetheadAPIError.offline {
                problem = "The notesfile didn't answer. Check your connection and try again."
            } catch NetheadAPIError.notConfigured {
                problem = "This build doesn't know where the notesfile lives."
            } catch {
                problem = "Bummer — that didn't take. Get a fresh code from your page and try again."
            }
            isWorking = false
        }
    }
}
