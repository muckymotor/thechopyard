import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
class AppViewModel: ObservableObject {
    @Published var user: User?
    @Published var isLoggedIn = false
    @Published var savedListingIds: Set<String> = []
    @Published var listings: [Listing] = []
    @Published var isLoadingPage = false
    @Published var errorMessage: String? = nil
    @Published var hasUnreadMessages = false

    private var authStateListenerHandle: AuthStateDidChangeListenerHandle?
    private var savedListingsListener: ListenerRegistration?
    private var unreadMessagesListener: ListenerRegistration?
    private var lastDocumentSnapshot: DocumentSnapshot?

    private let listingsCollection = Firestore.firestore().collection("listings")
    private let itemsPerPage = 10
    private let db = Firestore.firestore()

    init() {
        self.user = Auth.auth().currentUser
        self.isLoggedIn = user != nil

        if isLoggedIn {
            fetchSavedListings()
            startUnreadMessagesListener()
        }

        self.authStateListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            self.user = user
            self.isLoggedIn = user != nil
            self.hasUnreadMessages = false

            self.savedListingsListener?.remove()
            self.unreadMessagesListener?.remove()

            if user != nil {
                self.fetchSavedListings()
                self.startUnreadMessagesListener()
            } else {
                self.savedListingIds = []
                self.savedListingsListener = nil
                self.unreadMessagesListener = nil
            }
        }
    }

    deinit {
        if let handle = authStateListenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
        savedListingsListener?.remove()
        unreadMessagesListener?.remove()
    }

    func signOutCurrentUser() {
        savedListingsListener?.remove()
        savedListingsListener = nil
        unreadMessagesListener?.remove()
        unreadMessagesListener = nil

        do {
            try Auth.auth().signOut()
        } catch let signOutError as NSError {
            self.errorMessage = "Error signing out: \(signOutError.localizedDescription)"
        }

        self.user = nil
        self.isLoggedIn = false
        self.savedListingIds = []
        self.listings = []
        self.lastDocumentSnapshot = nil
    }

    func toggleSavedListing(_ listing: Listing) {
        guard let userId = self.user?.uid else { return }
        guard let listingID = listing.id else { return }

        let ref = db.collection("users").document(userId).collection("savedListings").document(listingID)

        Task {
            if self.savedListingIds.contains(listingID) {
                do {
                    try await ref.delete()
                    self.savedListingIds.remove(listingID)
                } catch {
                    print("Error removing saved listing \(listingID): \(error.localizedDescription)")
                }
            } else {
                do {
                    try await ref.setData(["savedAt": Timestamp()])
                    self.savedListingIds.insert(listingID)
                } catch {
                    print("Error saving listing \(listingID): \(error.localizedDescription)")
                }
            }
        }
    }

    func fetchSavedListings() {
        guard let userId = self.user?.uid else {
            self.savedListingIds = []
            savedListingsListener?.remove()
            savedListingsListener = nil
            return
        }

        savedListingsListener?.remove()

        savedListingsListener = db.collection("users").document(userId).collection("savedListings")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error = error {
                    print("Error fetching saved listings IDs: \(error.localizedDescription)")
                    self.savedListingIds = []
                    return
                }
                let ids = Set(snapshot?.documents.map { $0.documentID } ?? [])
                self.savedListingIds = ids
            }
    }

    func fetchListings(categories: Set<String>? = nil,
                       sortBy: HomeFeedView.SortOption? = .newest,
                       loadMore: Bool = false) async {
        guard !(self.isLoadingPage && loadMore) else { return }

        self.isLoadingPage = true
        if !loadMore { self.errorMessage = nil }

        var query: Query = listingsCollection

        if let selectedCategories = categories, !selectedCategories.isEmpty {
            if selectedCategories.count <= 30 {
                query = query.whereField("category", in: Array(selectedCategories))
            }
        }

        query = query.order(by: "timestamp", descending: true)

        if loadMore, let lastSnap = self.lastDocumentSnapshot {
            query = query.start(afterDocument: lastSnap)
        } else {
            self.listings = []
            self.lastDocumentSnapshot = nil
        }

        query = query.limit(to: itemsPerPage)

        do {
            let snapshot = try await query.getDocuments()
            let newDocs = snapshot.documents.compactMap { try? $0.data(as: Listing.self) }

            if loadMore {
                self.listings.append(contentsOf: newDocs)
            } else {
                self.listings = newDocs
            }

            if !snapshot.documents.isEmpty {
                self.lastDocumentSnapshot = snapshot.documents.last
            }
        } catch {
            self.errorMessage = "Error fetching listings: \(error.localizedDescription)"
        }

        self.isLoadingPage = false
    }

    func startUnreadMessagesListener() {
        guard let currentUserId = user?.uid else { return }

        unreadMessagesListener = db.collection("chats")
            .whereField("visibleTo", arrayContains: currentUserId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }

                var hasUnread = false

                if let documents = snapshot?.documents {
                    for doc in documents {
                        let data = doc.data()
                        let readBy = data["readBy"] as? [String] ?? []
                        let senderId = data["lastMessageSenderId"] as? String ?? ""
                        let chatId = doc.documentID

                        print("🔍 Chat \(chatId): readBy=\(readBy), senderId=\(senderId), user=\(currentUserId)")

                        if !readBy.contains(currentUserId), senderId != currentUserId {
                            hasUnread = true
                            break
                        }
                    }
                }

                DispatchQueue.main.async {
                    self.hasUnreadMessages = hasUnread
                    print("🔴 hasUnreadMessages = \(hasUnread)")
                }
            }
    }
}
