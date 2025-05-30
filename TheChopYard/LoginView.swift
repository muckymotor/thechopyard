import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct LoginView: View {
    @State private var emailOrUsername = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var navigateToSignup = false

    var onLogin: () -> Void
    var onSignup: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image("chopyard_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300, height: 100)
                    .padding(.top, 40)

                VStack(spacing: 16) {
                    TextField("Email or Username", text: $emailOrUsername)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                }

                if showError {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button(action: login) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                    } else {
                        Text("Log In")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .disabled(isLoading)

                HStack {
                    Text("Don't have an account?")
                        .foregroundColor(.secondary)

                    NavigationLink(destination: SignupView(onSignup: {
                        onSignup()
                    }), isActive: $navigateToSignup) {
                        Button("Sign Up") {
                            navigateToSignup = true
                        }
                        .fontWeight(.medium)
                    }
                }
                .padding(.top)

                Spacer()
            }
            .padding()
            .background(Color(.systemBackground))
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }

    private func login() {
        showError = false
        errorMessage = ""
        isLoading = true

        let input = emailOrUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if input.contains("@") {
            // Email login
            Auth.auth().signIn(withEmail: input, password: password) { result, error in
                handleAuthResult(error)
            }
        } else {
            // Username login: Look up associated email
            let db = Firestore.firestore()
            db.collection("usernames").document(input).getDocument { snapshot, error in
                if let data = snapshot?.data(), let uid = data["uid"] as? String {
                    db.collection("users").document(uid).getDocument { userSnapshot, error in
                        if let userData = userSnapshot?.data(), let email = userData["email"] as? String {
                            Auth.auth().signIn(withEmail: email, password: password) { result, error in
                                handleAuthResult(error)
                            }
                        } else {
                            showAuthError("No email found for this username.")
                        }
                    }
                } else {
                    showAuthError("Username not found.")
                }
            }
        }
    }

    private func handleAuthResult(_ error: Error?) {
        isLoading = false
        if let error = error {
            showAuthError(error.localizedDescription)
        } else {
            onLogin()
        }
    }

    private func showAuthError(_ message: String) {
        errorMessage = message
        showError = true
        isLoading = false
    }
}
