import SwiftUI
import GoogleSignIn

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("Google Tasks")
                    .font(.largeTitle.bold())
                Text("Sign in to access your tasks")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: signIn) {
                HStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                    Text("Sign in with Google")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    private func signIn() {
        guard
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let root = scene.windows.first?.rootViewController
        else { return }
        authManager.signIn(presenting: root)
    }
}
