import SwiftUI

struct SentView: View {
    @EnvironmentObject var store: MatchStore
    let name: String
    let subtitle: String

    @State private var shown = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle().fill(Color.mint).frame(width: 96, height: 96)
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Color.appBackground)
            }
            .scaleEffect(shown ? 1 : 0.3)
            .opacity(shown ? 1 : 0)

            Text("Sent to \(name)").font(.title.bold())
            Text(subtitle)
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
            Spacer()

            Button("Done") { tapHaptic(); store.close() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .foregroundStyle(.white)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { shown = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

#Preview {
    NavigationStack {
        SentView(name: "Maya", subtitle: "Maya will see Garden Song in their playlist.")
    }
    .environmentObject(MatchStore())
    .preferredColorScheme(.dark)
}
