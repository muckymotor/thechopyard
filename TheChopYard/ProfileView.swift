import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import CoreLocation

// --- ADDED @available TAG ---
@available(iOS 16.0, *)
struct ProfileView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @State private var userListings: [Listing] = []
    @State private var showingEditSheet = false // This will be handled by .sheet(item: ...)
    @State private var selectedListing: Listing? // Make this Identifiable for the sheet
    @State private var isLoading = true
    @State private var username: String = ""
    @State private var showingLogoutAlert = false
    @State private var alertMessage: String? = nil // For error alerts

    private let db = Firestore.firestore()

    var body: some View {
        NavigationStack { // Now safe because ProfileView is iOS 16+
            VStack {
                List {
                    if isLoading {
                        Section {
                            HStack {
                                Spacer()
                                ProgressView("Loading Profile...")
                                Spacer()
                            }
                        }
                    } else {
                        Section(header: Text("Account")) {
                            HStack {
                                Text("Username")
                                Spacer()
                                Text(username.isEmpty ? "Not set" : username)
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        Section {
                            NavigationLink(destination: MyListingsView(
                                userListings: $userListings,
                                showingEditSheet: $showingEditSheet, // Keep if MyListingsView directly uses this
                                selectedListing: $selectedListing,   // Keep if MyListingsView directly uses this
                                onRefresh: { Task { await fetchUserListings() } }
                            )) {
                                Label("My Listings", systemImage: "doc.plaintext")
                            }
                            
                            NavigationLink(destination: SavedListingsView()) {
                                Label("Saved Listings", systemImage: "heart")
                            }
                            
                            NavigationLink(destination: SettingsView(
                                currentUsername: username,
                                onUsernameUpdated: { Task { await fetchUsername() } }
                            )) {
                                Label("Settings", systemImage: "gearshape")
                            }
                        }
                        
                        Section {
                            Button(role: .destructive) {
                                showingLogoutAlert = true
                            } label: {
                                Text("Log Out")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                    }
                }
                .navigationTitle("Profile")
                .task {
                    await loadProfileData()
                }
                // Use .sheet(item: ...) for presenting EditListingView
                // Make sure your Listing struct is Identifiable (it already is)
                .sheet(item: $selectedListing) { listingToEdit in
                    EditListingView(listing: listingToEdit, onSave: {
                        Task { await fetchUserListings() }
                    })
                    .environmentObject(appViewModel) // Pass AppViewModel if EditListingView needs it
                }
                .alert(item: $alertMessage) { message in // For displaying errors
                    Alert(title: Text("Error"), message: Text(message), dismissButton: .default(Text("OK")))
                }
                .alert("Are you sure you want to log out?", isPresented: $showingLogoutAlert) {
                    Button("Log Out", role: .destructive) {
                        appViewModel.signOut()
                    }
                    Button("Cancel", role: .cancel) { }
                }
            }
        }
    }
    
    private func loadProfileData() async {
        isLoading = true
        await fetchUsername()
        await fetchUserListings()
        isLoading = false
    }

    private func fetchUsername() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            self.username = "Error: Not logged in" // Provide feedback
            // isLoading = false // Ensure isLoading is handled if returning early
            return
        }
        do {
            let snapshot = try await db.collection("users").document(userId).getDocument()
            if let data = snapshot.data(), let name = data["username"] as? String {
                self.username = name
            } else {
                self.username = "No username set" // Or handle as an error/prompt to set one
            }
        } catch {
            print("Error fetching username: \(error.localizedDescription)")
            self.username = "Error loading username" // Update UI to reflect error
            // self.alertMessage = "Could not load username: \(error.localizedDescription)" // Example error alert
        }
        // isLoading = false // Ensure isLoading is handled in all paths
    }

    private func fetchUserListings() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        do {
            let snapshot = try await db.collection("listings")
                .whereField("sellerId", isEqualTo: userId)
                .order(by: "timestamp", descending: true)
                .getDocuments()
            
            self.userListings = snapshot.documents.compactMap { doc in
                Listing(id: doc.documentID, data: doc.data())
            }
        } catch {
            print("Error fetching listings: \(error.localizedDescription)")
            // self.alertMessage = "Could not load your listings: \(error.localizedDescription)" // Example error alert
        }
    }
}

// --- REMOVED REDUNDANT EXTENSION FOR Listing ---

// For alert(item: $alertMessage), String needs to be Identifiable
extension String: Identifiable {
    public var id: String { self }
}
