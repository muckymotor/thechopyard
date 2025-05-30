import SwiftUI
import FirebaseAuth

struct ContentView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    var body: some View {
        Group {
            if appViewModel.isLoggedIn {
                HomeView()
            } else {
                LoginView(
                    onLogin: {
                        appViewModel.isLoggedIn = true
                    },
                    onSignup: {
                        appViewModel.isLoggedIn = true
                    }
                )
            }
        }
        .onAppear {
            appViewModel.isLoggedIn = Auth.auth().currentUser != nil
        }
    }
}
