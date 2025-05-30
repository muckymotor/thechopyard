import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SignupView: View {
    var onSignup: () -> Void

    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage = ""
    @State private var isLoading = false

    private let db = Firestore.firestore()

    var body: some View {
        VStack(spacing: 20) {
            Text("Sign Up").font(.largeTitle)

            TextField("Username", text: $username)
                .autocapitalization(.none)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            SecureField("Confirm Password", text: $confirmPassword)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            if !errorMessage.isEmpty {
                Text(errorMessage).foregroundColor(.red)
            }

            if isLoading {
                ProgressView()
            }

            Button("Sign Up") {
                signUp()
            }
            .disabled(isLoading)
        }
        .padding()
    }

    private func signUp() {
        errorMessage = ""
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !trimmedUsername.isEmpty else {
            errorMessage = "Please choose a username."
            return
        }
        guard isValidEmail(email) else {
            errorMessage = "Please enter a valid email address."
            return
        }
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match"
            return
        }

        isLoading = true
        let usernameRef = db.collection("usernames").document(trimmedUsername)

        usernameRef.getDocument { docSnapshot, error in
            if let error = error {
                self.isLoading = false
                self.errorMessage = "Error checking username: \(error.localizedDescription)"
                return
            }

            if docSnapshot?.exists == true {
                self.isLoading = false
                self.errorMessage = "Username is already taken."
                return
            }

            usernameRef.setData(["reserved": true]) { error in
                if let error = error {
                    self.isLoading = false
                    self.errorMessage = "Failed to reserve username: \(error.localizedDescription)"
                    return
                }

                Auth.auth().createUser(withEmail: email, password: password) { result, error in
                    if let error = error {
                        usernameRef.delete()
                        self.isLoading = false
                        self.errorMessage = "Sign up failed: \(error.localizedDescription)"
                        return
                    }

                    guard let user = result?.user else {
                        self.isLoading = false
                        self.errorMessage = "Unexpected error creating user."
                        return
                    }

                    saveUserData(userId: user.uid, trimmedUsername: trimmedUsername)
                }
            }
        }
    }

    private func saveUserData(userId: String, trimmedUsername: String) {
        let userData: [String: Any] = [
            "username": trimmedUsername,
            "email": email,
            "createdAt": Timestamp()
        ]

        let batch = db.batch()
        let userRef = db.collection("users").document(userId)
        let usernameRef = db.collection("usernames").document(trimmedUsername)

        batch.setData(userData, forDocument: userRef)
        batch.setData(["uid": userId], forDocument: usernameRef)

        batch.commit { error in
            self.isLoading = false
            if let error = error {
                self.errorMessage = "Failed to complete signup: \(error.localizedDescription)"
                return
            }
            self.onSignup()
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        return NSPredicate(format: "SELF MATCHES %@", emailRegEx).evaluate(with: email)
    }
}
