import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import CoreLocation

@MainActor
struct ListingDetailView: View {
    @State var listing: Listing
    @EnvironmentObject var appViewModel: AppViewModel

    @State private var sellerUsername: String = "Loading..."
    @State private var navigateToChat = false
    @State private var chatDocumentIdToNavigate: String?
    @StateObject private var localLocationManager = LocationManager()
    @State private var listingListener: ListenerRegistration?

    private let db = Firestore.firestore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                imageCarousel
                detailsSection

                if let currentId = appViewModel.user?.uid, currentId != listing.sellerId {
                    Button(action: handleMessageSellerTapped) {
                        Text("Message Seller")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Listing Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await fetchSellerUsername()
            localLocationManager.requestPermissionAndFetchLocation()
            startListeningToListing()
        }
        .onDisappear {
            listingListener?.remove()
        }
        .navigationDestination(isPresented: $navigateToChat) {
            if let chatId = chatDocumentIdToNavigate {
                ChatView(chatId: chatId, sellerUsername: sellerUsername, otherUserId: listing.sellerId)
                    .environmentObject(appViewModel)
            } else {
                Text("Error: Could not open chat.")
            }
        }
    }

    private func startListeningToListing() {
        guard let id = listing.id else { return }

        listingListener?.remove()

        listingListener = db.collection("listings").document(id)
            .addSnapshotListener { snapshot, error in
                guard let doc = snapshot, let updated = try? doc.data(as: Listing.self) else { return }
                DispatchQueue.main.async {
                    self.listing = updated
                    appViewModel.updateListing(updated)
                }
            }
    }

    private var imageCarousel: some View {
        let padding: CGFloat = 16
        let side = UIScreen.main.bounds.width - (padding * 2)

        return TabView {
            if listing.imageUrls.isEmpty {
                placeholderImage(size: side)
            } else {
                ForEach(listing.imageUrls, id: \.self) { url in
                    if let u = URL(string: url) {
                        AsyncImage(url: u) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFill()
                            case .failure: placeholderImage(size: side, icon: "exclamationmark.triangle.fill")
                            case .empty: ProgressView().frame(width: side, height: side)
                            @unknown default: EmptyView()
                            }
                        }
                        .frame(width: side, height: side)
                        .clipped()
                        .cornerRadius(10)
                    } else {
                        placeholderImage(size: side)
                    }
                }
            }
        }
        .frame(height: side)
        .tabViewStyle(PageTabViewStyle())
        .indexViewStyle(.page(backgroundDisplayMode: .automatic))
        .padding(.vertical)
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(listing.title).font(.title).bold()
            Text("$\(String(format: "%.2f", listing.price))").font(.title2)

            HStack {
                Text("Seller:").bold()
                Text(sellerUsername).foregroundColor(.gray)
            }

            if let location = listing.locationName, !location.isEmpty {
                HStack {
                    Text("Location:").bold()
                    Text(location).foregroundColor(.gray)
                }
            }

            if let category = listing.category, !category.isEmpty {
                HStack {
                    Text("Category:").bold()
                    Text(category).foregroundColor(.gray)
                }
            }

            HStack {
                Text("Posted:").bold()
                Text(listing.timestamp, style: .relative).foregroundColor(.gray)
                + Text(" ago").foregroundColor(.gray)
            }

            if let desc = listing.description, !desc.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description:").bold()
                    Text(desc).foregroundColor(.primary)
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func placeholderImage(size: CGFloat, icon: String = "photo.fill") -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.15))
            .frame(width: size, height: size)
            .cornerRadius(10)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 50))
                    .foregroundColor(.gray.opacity(0.5))
            )
    }

    private func fetchSellerUsername() async {
        guard !listing.sellerId.isEmpty else {
            self.sellerUsername = "Unknown"
            return
        }
        do {
            let doc = try await db.collection("users").document(listing.sellerId).getDocument()
            if let data = doc.data(), let username = data["username"] as? String {
                self.sellerUsername = username
            } else {
                self.sellerUsername = "Unknown"
            }
        } catch {
            self.sellerUsername = "Unknown"
        }
    }

    private func handleMessageSellerTapped() {
        guard let listingId = listing.id,
              let currentId = appViewModel.user?.uid,
              currentId != listing.sellerId else { return }

        Task {
            await startOrOpenChat(currentsellerId: currentId, recipientId: listing.sellerId, listingId: listingId)
        }
    }

    private func startOrOpenChat(currentsellerId: String, recipientId: String, listingId: String) async {
        let chatId = [currentsellerId, recipientId].sorted().joined(separator: "_") + "_\(listingId)"
        let chatRef = db.collection("chats").document(chatId)

        do {
            let chatDoc = try await chatRef.getDocument()

            if chatDoc.exists {
                var visibleTo = chatDoc.data()?["visibleTo"] as? [String] ?? []
                if !visibleTo.contains(currentsellerId) {
                    visibleTo.append(currentsellerId)
                    try await chatRef.updateData([
                        "visibleTo": visibleTo,
                        "lastMessageTimestamp": FieldValue.serverTimestamp()
                    ])
                }
                chatDocumentIdToNavigate = chatId
                navigateToChat = true
            } else {
                async let currentUsername = fetchUsername(for: currentsellerId)
                async let sellerUsername = fetchUsername(for: recipientId)
                let participantNames = [
                    currentsellerId: try await currentUsername,
                    recipientId: try await sellerUsername
                ]
                try await chatRef.setData([
                    "participants": [currentsellerId, recipientId].sorted(),
                    "participantNames": participantNames,
                    "visibleTo": [currentsellerId, recipientId],
                    "listingId": listingId,
                    "listingTitle": listing.title,
                    "listingImageUrl": listing.imageUrls.first ?? "",
                    "lastMessage": "",
                    "lastMessageSenderId": "",
                    "lastMessageTimestamp": FieldValue.serverTimestamp(),
                    "createdAt": FieldValue.serverTimestamp()
                ])
                chatDocumentIdToNavigate = chatId
                navigateToChat = true
            }
        } catch {
            print("Chat error: \(error.localizedDescription)")
        }
    }

    private func fetchUsername(for uid: String) async throws -> String {
        let doc = try await db.collection("users").document(uid).getDocument()
        guard let data = doc.data(), let username = data["username"] as? String else {
            throw NSError(domain: "FetchUsername", code: 404)
        }
        return username
    }
}
