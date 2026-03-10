import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        if authManager.isSignedIn {
            TaskListsView()
        } else {
            LoginView()
        }
    }
}
