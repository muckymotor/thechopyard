// ProfileView.swift

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import CoreLocation

// NO ErrorAlertItem struct definition here anymore.
// It will use the definition from AppUtilities.swift (or your shared file).

@available(iOS 16.0, *)
struct ProfileView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @State private var userListings: [Listing] = []
    @State private var selectedListing: Listing?
    @State private var isLoading = true
    @State private var username: String = ""
    @State private var showingLogoutAlert = false
    @State private var errorAlertItem: ErrorAlertItem? // This will now refer to the shared definition

    private let db = Firestore.firestore()

    // ... (rest of your ProfileView code remains the same as you provided in the last turn)
    // The body, loadProfileData, fetchUsername, fetchUserListings methods
    // DO NOT need to change again for this specific error.
    // Just ensure the duplicate struct definition is removed from this file.

    var body: some View {
        NavigationStack {
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
                    
                    Section(header: Text("My Content")) {
                        NavigationLink {
                            MyListingsView(
                                userListings: $userListings,
                                selectedListing: $selectedListing,
                                onRefresh: { Task { await fetchUserListings() } }
                            )
                            .environmentObject(appViewModel)
                        } label: {
                            Label("My Listings", systemImage: "doc.plaintext")
                        }
                        
                        NavigationLink {
                            SavedListingsView()
                                .environmentObject(appViewModel)
                        } label: {
                            Label("Saved Listings", systemImage: "heart")
                        }
                    }
                    
                    Section(header: Text("General")) {
                        NavigationLink {
                            SettingsView(
                                currentUsername: username,
                                onUsernameUpdated: { Task { await fetchUsername() } }
                            )
                            .environmentObject(appViewModel)
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                    
                    Section {
                        Button(role: .destructive) {
                            showingLogoutAlert = true
                        } label: {
                            Text("Log Out")
                                .frame(maxWidth: .infinity, alignment: .center)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .task {
                await loadProfileData()
            }
            .sheet(item: $selectedListing) { listingToEdit in
                EditListingView(listing: listingToEdit, onSave: {
                    Task { await fetchUserListings() }
                })
                .environmentObject(appViewModel)
            }
            .alert("Log Out", isPresented: $showingLogoutAlert) {
                Button("Log Out", role: .destructive) {
                    appViewModel.signOutCurrentUser()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to log out?")
            }
            .alert(item: $errorAlertItem) { item in
                Alert(title: Text(item.title), message: Text(item.message), dismissButton: .default(Text("OK")))
            }
        }
    }
    
    private func loadProfileData() async {
        isLoading = true
        async let usernameFetch: () = fetchUsername()
        async let listingsFetch: () = fetchUserListings()
        _ = await [usernameFetch, listingsFetch]
        isLoading = false
    }

    private func fetchUsername() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            self.username = ""
            return
        }
        do {
            let snapshot = try await db.collection("users").document(userId).getDocument()
            if snapshot.exists, let data = snapshot.data(), let name = data["username"] as? String {
                self.username = name
            } else {
                self.username = "No username set"
            }
        } catch {
            print("Error fetching username: \(error.localizedDescription)")
            self.username = ""
            self.errorAlertItem = ErrorAlertItem(message: "Could not load username: \(error.localizedDescription)")
        }
    }

    private func fetchUserListings() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            self.userListings = []
            return
        }
        do {
            let snapshot = try await db.collection("listings")
                .whereField("sellerId", isEqualTo: userId)
                .order(by: "timestamp", descending: true)
                .getDocuments()
            self.userListings = snapshot.documents.compactMap { document -> Listing? in
                try? document.data(as: Listing.self)
            }
        } catch {
            print("Error fetching user listings: \(error.localizedDescription)")
            self.userListings = []
            self.errorAlertItem = ErrorAlertItem(message: "Could not load your listings: \(error.localizedDescription)")
        }
    }
}
