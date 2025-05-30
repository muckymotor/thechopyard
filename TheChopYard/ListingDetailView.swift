import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import CoreLocation

struct ListingDetailView: View {
    let listing: Listing

    @State private var sellerUsername: String = "Loading..."
    @State private var navigateToChat = false
    @State private var chatId: String?
    @State private var userLocation: CLLocation?

    private let db = Firestore.firestore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    imageCarousel

                    Text(listing.title).font(.title).bold()
                    Text("$\(String(format: "%.2f", listing.price))").font(.title2)

                    HStack {
                        Text("Seller:").bold()
                        Text(sellerUsername).foregroundColor(.gray)
                    }

                    if let locationName = listing.locationName {
                        HStack {
                            Text("Location:").bold()
                            Text(locationName).foregroundColor(.gray)
                        }
                    }

                    if let userLocation = userLocation {
                        Text(listing.formattedDistance(from: userLocation))
                            .foregroundColor(.gray)
                            .font(.footnote)
                    }

                    if let category = listing.category {
                        HStack {
                            Text("Category:").bold()
                            Text(category).foregroundColor(.gray)
                        }
                    }

                    HStack {
                        Text("Posted:").bold()
                        Text(listing.timestamp.relativeTimeString()).foregroundColor(.gray)
                    }

                    if let description = listing.description, !description.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description:").bold()
                            Text(description).foregroundColor(.primary)
                        }
                    }

                    Button(action: startOrOpenChat) {
                        Text("Message Seller")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding()
            }
            .navigationTitle("Listing Details")
            .onAppear {
                fetchSellerUsername()
                fetchUserLocation()
            }
            .navigationDestination(isPresented: $navigateToChat) {
                ChatView(chatId: chatId ?? "", sellerUsername: sellerUsername)
            }
        }
    }

    private var imageCarousel: some View {
        let imageSize = UIScreen.main.bounds.width - 32

        return TabView {
            ForEach(listing.imageUrls, id: \.self) { urlString in
                if let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Color.gray.opacity(0.3)
                                .overlay(Image(systemName: "photo").font(.largeTitle).foregroundColor(.white))
                        case .empty:
                            ProgressView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: imageSize, height: imageSize)
                    .clipped()
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
            }
        }
        .frame(height: imageSize)
        .tabViewStyle(PageTabViewStyle())
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }

    private func fetchSellerUsername() {
        db.collection("users").document(listing.sellerId).getDocument { snapshot, _ in
            if let data = snapshot?.data(), let username = data["username"] as? String {
                sellerUsername = username
            } else {
                sellerUsername = "Unknown"
            }
        }
    }

    private func fetchUserLocation() {
        if let location = CLLocationManager().location {
            userLocation = location
        }
    }

    private func startOrOpenChat() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        db.collection("chats")
            .whereField("listingId", isEqualTo: listing.id)
            .getDocuments { snapshot, _ in
                if let documents = snapshot?.documents {
                    for doc in documents {
                        let data = doc.data()
                        let participants = data["participants"] as? [String] ?? []
                        let visibleTo = data["visibleTo"] as? [String] ?? []

                        if participants.contains(currentUserId) && participants.contains(listing.sellerId) {
                            if visibleTo.contains(currentUserId) {
                                chatId = doc.documentID
                                navigateToChat = true
                                return
                            } else {
                                db.collection("chats").document(doc.documentID).updateData([
                                    "visibleTo": FieldValue.arrayUnion([currentUserId])
                                ]) { error in
                                    if error == nil {
                                        chatId = doc.documentID
                                        navigateToChat = true
                                    }
                                }
                                return
                            }
                        }
                    }
                }

                // Create new chat
                let newChatRef = db.collection("chats").document()
                newChatRef.setData([
                    "participants": [currentUserId, listing.sellerId],
                    "visibleTo": [currentUserId, listing.sellerId],
                    "listingId": listing.id,
                    "lastMessage": "",
                    "timestamp": Timestamp()
                ]) { error in
                    if error == nil {
                        chatId = newChatRef.documentID
                        navigateToChat = true
                    }
                }
            }
    }
}
