import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SettingsView: View {
    let currentUsername: String
    var onUsernameUpdated: () -> Void

    @State private var newUsername: String
    @State private var isAvailable: Bool? = nil
    @State private var isSaving = false
    @State private var errorMessage = ""

    private let db = Firestore.firestore()

    init(currentUsername: String, onUsernameUpdated: @escaping () -> Void) {
        self.currentUsername = currentUsername
        self.onUsernameUpdated = onUsernameUpdated
        _newUsername = State(initialValue: currentUsername)
    }

    var body: some View {
        Form {
            Section(header: Text("Edit Username")) {
                HStack {
                    TextField("Username", text: $newUsername)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: newUsername) { _ in
                            validateUsername()
                        }

                    if let available = isAvailable {
                        Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(available ? .green : .red)
                    }
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Button("Save Username") {
                    updateUsername()
                }
                .disabled(!canSave)
            }
        }
        .navigationTitle("Settings")
        .onAppear(perform: validateUsername)
    }

    private var canSave: Bool {
        !newUsername.isEmpty &&
        newUsername != currentUsername &&
        isAvailable == true &&
        !isSaving
    }

    private func validateUsername() {
        guard !newUsername.isEmpty else {
            isAvailable = nil
            return
        }
        guard newUsername != currentUsername else {
            isAvailable = true
            return
        }

        db.collection("usernames").document(newUsername).getDocument { doc, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Username validation error: \(error.localizedDescription)")
                    isAvailable = false
                } else {
                    isAvailable = !(doc?.exists ?? false)
                }
            }
        }
    }

    private func updateUsername() {
        guard let sellerId = Auth.auth().currentUser?.uid else { return }

        isSaving = true
        errorMessage = ""

        let usernamesRef = db.collection("usernames").document(newUsername)
        let oldUsernameRef = db.collection("usernames").document(currentUsername)
        let userRef = db.collection("users").document(sellerId)

        db.runTransaction { transaction, errorPointer in
            do {
                let newUsernameDoc = try transaction.getDocument(usernamesRef)
                if newUsernameDoc.exists {
                    let error = NSError(domain: "App", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Username already taken."
                    ])
                    errorPointer?.pointee = error
                    return nil
                }

                transaction.setData(["uid": sellerId], forDocument: usernamesRef)
                transaction.deleteDocument(oldUsernameRef)
                transaction.updateData(["username": newUsername], forDocument: userRef)

                return nil
            } catch let err as NSError {
                errorPointer?.pointee = err
                return nil
            }
        } completion: { _, error in
            DispatchQueue.main.async {
                isSaving = false
                if let error = error {
                    errorMessage = error.localizedDescription
                } else {
                    onUsernameUpdated()
                }
            }
        }
    }
}
