import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import CoreLocation

@MainActor
struct ListingDetailView: View {
    let listing: Listing
    @EnvironmentObject var appViewModel: AppViewModel

    @State private var sellerUsername: String = "Loading..."
    @State private var navigateToChat = false
    @State private var chatDocumentIdToNavigate: String?
    @StateObject private var localLocationManager = LocationManager()

    private let db = Firestore.firestore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                imageCarousel

                VStack(alignment: .leading, spacing: 8) {
                    Text(listing.title).font(.title).bold()
                    Text("$\(String(format: "%.2f", listing.price))").font(.title2)

                    HStack {
                        Text("Seller:").bold()
                        Text(sellerUsername).foregroundColor(sellerUsername == "Loading..." || sellerUsername.starts(with: "Unknown") ? .gray : .primary)
                    }

                    if let locationName = listing.locationName, !locationName.isEmpty {
                        HStack {
                            Text("Location:").bold()
                            Text(locationName).foregroundColor(.gray)
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
                        Text(listing.timestamp, style: .relative).foregroundColor(.gray) + Text(" ago").foregroundColor(.gray)
                    }

                    if let description = listing.description, !description.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Description:").bold()
                            Text(description).foregroundColor(.primary)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal)

                if let currentsellerId = appViewModel.user?.uid, currentsellerId != listing.sellerId {
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
        }
        .navigationDestination(isPresented: $navigateToChat) {
            if let chatId = chatDocumentIdToNavigate {
                ChatView(chatId: chatId, sellerUsername: self.sellerUsername)
                    .environmentObject(appViewModel)
            } else {
                Text("Error: Could not open chat. Chat ID missing.")
            }
        }
    }

    private var imageCarousel: some View {
        let padding: CGFloat = 16
        let imageSide = UIScreen.main.bounds.width - (padding * 2)

        return TabView {
            if listing.imageUrls.isEmpty {
                placeholderImage(size: imageSide)
            } else {
                ForEach(listing.imageUrls, id: \.self) { urlString in
                    if let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            case .failure:
                                placeholderImage(size: imageSide, icon: "exclamationmark.triangle.fill")
                            case .empty:
                                ProgressView().frame(width: imageSide, height: imageSide)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(width: imageSide, height: imageSide)
                        .clipped()
                        .cornerRadius(10)
                    } else {
                        placeholderImage(size: imageSide)
                    }
                }
            }
        }
        .frame(height: imageSide)
        .tabViewStyle(PageTabViewStyle())
        .indexViewStyle(.page(backgroundDisplayMode: .automatic))
        .padding(.vertical)
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
            self.sellerUsername = "Unknown (Invalid Seller ID)"
            return
        }
        do {
            let document = try await db.collection("users").document(listing.sellerId).getDocument()
            if let data = document.data(), let username = data["username"] as? String {
                self.sellerUsername = username
            } else {
                self.sellerUsername = "Unknown"
            }
        } catch {
            self.sellerUsername = "Unknown (Error)"
        }
    }

    private func handleMessageSellerTapped() {
        guard let listingId = listing.id else {
            print("ListingDetailView: Listing ID is nil.")
            return
        }
        guard let currentsellerId = appViewModel.user?.uid, !currentsellerId.isEmpty else {
            print("ListingDetailView: Current user ID not found.")
            return
        }
        if currentsellerId == listing.sellerId {
            print("ListingDetailView: User cannot message themselves.")
            return
        }

        Task {
            await startOrOpenChat(currentsellerId: currentsellerId, recipientId: listing.sellerId, listingId: listingId)
        }
    }

    private func startOrOpenChat(currentsellerId: String, recipientId: String, listingId: String) async {
        let participantsArray = [currentsellerId, recipientId].sorted()
        let chatId = participantsArray.joined(separator: "_") + "_\(listingId)"
        let chatRef = db.collection("chats").document(chatId)

        do {
            let chatSnapshot = try await chatRef.getDocument()

            if chatSnapshot.exists {
                var visibleTo = chatSnapshot.data()?["visibleTo"] as? [String] ?? []
                if !visibleTo.contains(currentsellerId) {
                    visibleTo.append(currentsellerId)
                    try await chatRef.updateData([
                        "visibleTo": visibleTo,
                        "lastMessageTimestamp": FieldValue.serverTimestamp()
                    ])
                }
                self.chatDocumentIdToNavigate = chatId
                self.navigateToChat = true
            } else {
                async let currentUsername = fetchUsername(for: currentsellerId)
                async let sellerUsername = fetchUsername(for: recipientId)

                let participantNames = [
                    currentsellerId: try await currentUsername,
                    recipientId: try await sellerUsername
                ]

                let newChatData: [String: Any] = [
                    "participants": participantsArray,
                    "participantNames": participantNames,
                    "visibleTo": participantsArray,
                    "listingId": listingId,
                    "listingTitle": listing.title,
                    "listingImageUrl": listing.imageUrls.first ?? "",
                    "lastMessage": "",
                    "lastMessageSenderId": "",
                    "lastMessageTimestamp": FieldValue.serverTimestamp(),
                    "createdAt": FieldValue.serverTimestamp()
                ]

                try await chatRef.setData(newChatData)
                self.chatDocumentIdToNavigate = chatId
                self.navigateToChat = true
            }
        } catch {
            print("ListingDetailView: Failed to create or fetch chat: \(error.localizedDescription)")
        }
    }

    private func fetchUsername(for uid: String) async throws -> String {
        let doc = try await db.collection("users").document(uid).getDocument()
        guard let data = doc.data(), let username = data["username"] as? String else {
            throw NSError(domain: "FetchUsername", code: 404, userInfo: [NSLocalizedDescriptionKey: "Username not found for UID: \(uid)"])
        }
        return username
    }
}
