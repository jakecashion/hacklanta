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
                DecorStar(color: .cubeYellow, size: 36, rotation: 10).offset(x: -90, y: -50)
                DecorStar(color: .cubeOrange, size: 24, rotation: -12).offset(x: 95, y: -60)
                DecorBlob(color: .lightBlue, size: 50).offset(x: 90, y: 50)
                DecorStar(color: .cubeRed, size: 18).offset(x: -80, y: 55)

                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 110, height: 110)
                    .background(Circle().fill(Color.cubeGreen))
                    .overlay(Circle().stroke(Color.ink, lineWidth: Brut.border))
                    .background(Circle().fill(Color.ink).offset(x: Brut.shadowLarge, y: Brut.shadowLarge))
            }
            .frame(height: 150)
            .scaleEffect(shown ? 1 : 0.3)
            .opacity(shown ? 1 : 0)

            Text("sent to \(name)").font(.system(.largeTitle, weight: .heavy))
            Text(subtitle)
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
            Spacer()

            Button("done") { tapHaptic(); store.close() }
                .buttonStyle(.brutPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .pageBackground()
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
    .brutScreen()
}
