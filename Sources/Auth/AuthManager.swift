import Foundation
import GoogleSignIn
import Combine

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var isSignedIn = false
    @Published var userEmail: String?
    @Published var userName: String?

    private let suite = "group.com.jk.googletaskonmac"

    private init() {
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, _ in
            guard let self, let user else { return }
            Task { @MainActor in
                self.handleUser(user)
                await self.refreshWidgetCache()
            }
        }
    }

    func signIn(presenting viewController: UIViewController) {
        let scopes = ["https://www.googleapis.com/auth/tasks"]
        GIDSignIn.sharedInstance.signIn(
            withPresenting: viewController,
            hint: nil,
            additionalScopes: scopes
        ) { [weak self] result, error in
            guard let self else { return }
            if let error {
                print("Sign in error: \(error.localizedDescription)")
                return
            }
            if let user = result?.user {
                Task { @MainActor in
                    self.handleUser(user)
                    await self.refreshWidgetCache()
                }
            }
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        isSignedIn = false
        userEmail = nil
        userName = nil
        WidgetDataService.shared.clear()
    }

    func getAccessToken() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw AuthError.notSignedIn
        }
        try await user.refreshTokensIfNeeded()
        let token = user.accessToken.tokenString
        UserDefaults(suiteName: suite)?.set(token, forKey: "accessToken")
        return token
    }

    func refreshWidgetCache() async {
        do {
            let token = try await getAccessToken()
            let lists = try await GoogleTasksService.shared.fetchTaskLists(token: token)
            var allTasks: [(task: GTTask, listId: String)] = []
            for list in lists {
                let tasks = try await GoogleTasksService.shared.fetchTasks(listId: list.id, token: token)
                allTasks.append(contentsOf: tasks.map { ($0, list.id) })
            }
            WidgetDataService.shared.update(tasks: allTasks, isSignedIn: true)
        } catch {
            print("Widget cache refresh error: \(error)")
        }
    }

    private func handleUser(_ user: GIDGoogleUser) {
        isSignedIn = true
        userEmail = user.profile?.email
        userName = user.profile?.name
    }
}

enum AuthError: LocalizedError {
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in"
        }
    }
}
