import SwiftUI
import GoogleSignIn

@main
struct GoogleTaskApp: App {
    @StateObject private var authManager = AuthManager.shared
    @State private var showQuickAdd = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .sheet(isPresented: $showQuickAdd) {
                    QuickAddTaskView()
                        .environmentObject(authManager)
                }
                .onOpenURL { url in
                    if url.scheme == "googletask", url.host == "add" {
                        showQuickAdd = true
                    } else {
                        GIDSignIn.sharedInstance.handle(url)
                    }
                }
        }
    }
}
