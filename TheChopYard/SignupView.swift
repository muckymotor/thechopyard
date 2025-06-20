import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SignupView: View {
    var onSignup: () -> Void // Callback for successful signup

    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String? = nil
    @State private var isLoading = false

    private let db = Firestore.firestore()

    var body: some View {
        VStack(spacing: 20) {
            Text("Sign Up")
                .font(.largeTitle)
                .padding(.bottom, 20)

            TextField("Username", text: $username)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            SecureField("Password (min. 6 characters)", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            SecureField("Confirm Password", text: $confirmPassword)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            if isLoading {
                ProgressView()
                    .padding(.top)
            }

            Button(action: {
                Task {
                    await attemptSignup()
                }
            }) {
                Text("Sign Up")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            .padding(.top)
            .disabled(isLoading)
        }
        .padding()
        .alert("Signup Information", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "An unexpected error occurred.")
        })
    }

    private func attemptSignup() async {
        errorMessage = nil
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !trimmedUsername.isEmpty, trimmedUsername.count >= 3 else {
            errorMessage = "Username must be at least 3 characters."
            return
        }
        guard isValidEmail(email) else {
            errorMessage = "Please enter a valid email address."
            return
        }
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return
        }
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }

        isLoading = true

        let usernameRef = db.collection("usernames").document(trimmedUsername)
        do {
            let usernameDoc = try await usernameRef.getDocument()
            if usernameDoc.exists {
                errorMessage = "Username is already taken. Please choose another."
                isLoading = false
                return
            }
        } catch {
            errorMessage = "Error checking username: \(error.localizedDescription)"
            isLoading = false
            return
        }

        // Step 2: Create Firebase Auth user
        do {
            let authResult = try await Auth.auth().createUser(withEmail: email, password: password)
            
            // ✅ **CORRECTED HERE**: Directly assign authResult.user
            let newUser = authResult.user
            // No 'guard let' needed as authResult.user is non-optional on success.
            // The 'try await' above would throw if user creation failed catastrophically.

            print("Firebase Auth user created successfully: \(newUser.uid)")
            await saveUserDataAndUsername(sellerId: newUser.uid, email: newUser.email ?? self.email, username: trimmedUsername)

        } catch {
            errorMessage = "Sign up failed: \(error.localizedDescription)"
            isLoading = false
        }
    }

    private func saveUserDataAndUsername(sellerId: String, email: String, username: String) async {
        let userRef = db.collection("users").document(sellerId)
        let usernameRef = db.collection("usernames").document(username)

        let userData: [String: Any] = [
            "username": username,
            "email": email,
            "createdAt": FieldValue.serverTimestamp()
        ]

        let usernameData: [String: Any] = [
            "uid": sellerId,
            "email": email
        ]

        let batch = db.batch()
        batch.setData(userData, forDocument: userRef)
        batch.setData(usernameData, forDocument: usernameRef)

        do {
            try await batch.commit()
            print("User data and username reserved successfully in Firestore.")
            isLoading = false
            onSignup() // Call the success callback
        } catch {
            errorMessage = "Failed to save user data: \(error.localizedDescription)"
            isLoading = false
            print("Error committing batch: \(error.localizedDescription). Firebase Auth user \(sellerId) was created but Firestore data might be inconsistent.")
            // Consider attempting to delete the Auth user here if Firestore save fails, for consistency.
            // This is an advanced error recovery step.
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        return NSPredicate(format: "SELF MATCHES %@", emailRegEx).evaluate(with: email)
    }
}
