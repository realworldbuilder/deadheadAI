import SwiftUI

/// First-launch welcome. Ride along with everything on this phone, or get on
/// the bus with a handle from the notesfile so shelves and journal are the
/// same here and on the web.
struct OnboardingSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var showingPair = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            AppMark(size: 72)

            VStack(spacing: 8) {
                Text("Nethead")
                    .font(Theme.largeTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("When did the bus come by for you?")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                onboardRow(icon: "sparkles", text: "An old head who's spun every tape, riding shotgun.")
                onboardRow(icon: "dot.radiowaves.left.and.right", text: "Every tape on archive.org, '65 to '95 — boards, auds, matrixes. Nothing re-hosted.")
                onboardRow(icon: "book.closed", text: "The jams, the setlists, a journal, and thirty years of shows.")
            }
            .padding(.horizontal, 10)

            Spacer()

            Button("Get on the Bus") {
                dismiss()
            }
            .buttonStyle(.primary(fullWidth: true))

            if env.api != nil {
                Button("I've got a handle on the notesfile") {
                    showingPair = true
                }
                .buttonStyle(.secondary)
            }

            Text("A handle from the notesfile keeps your shelves and journal the same here and on the web. Or just ride along — everything stays on this phone, and you can get on later from Settings.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .background(Theme.background)
        .presentationBackground(Theme.background)
        .interactiveDismissDisabled()
        .sheet(isPresented: $showingPair) {
            PairSheet()
                .onDisappear {
                    if env.authProvider.currentAccount != nil { dismiss() }
                }
        }
    }

    private func onboardRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24)
            Text(text)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
