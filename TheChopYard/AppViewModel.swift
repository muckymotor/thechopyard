import SwiftUI
import FirebaseAuth
import FirebaseFirestore

class AppViewModel: ObservableObject {
    @Published var user: User?
    @Published var savedListingIds: Set<String> = []
    @Published var isLoggedIn: Bool = false

    private let db = Firestore.firestore()

    init() {
        self.user = Auth.auth().currentUser
        self.isLoggedIn = user != nil
        fetchSavedListings()

        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.user = user
            self?.isLoggedIn = user != nil
            if user != nil {
                self?.fetchSavedListings()
            }
        }
    }

    func signOut() {
        try? Auth.auth().signOut()
        self.user = nil
        self.savedListingIds = []
        self.isLoggedIn = false
    }

    func toggleSavedListing(_ listing: Listing) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let ref = db.collection("users").document(userId).collection("savedListings").document(listing.id)
        if savedListingIds.contains(listing.id) {
            ref.delete()
            savedListingIds.remove(listing.id)
        } else {
            ref.setData(["savedAt": Timestamp()])
            savedListingIds.insert(listing.id)
        }
    }

    func fetchSavedListings() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(userId).collection("savedListings").getDocuments { snapshot, _ in
            let ids = Set(snapshot?.documents.map { $0.documentID } ?? [])
            DispatchQueue.main.async {
                self.savedListingIds = ids
            }
        }
    }
}
