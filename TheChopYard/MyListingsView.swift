import SwiftUI
import FirebaseFirestore
import FirebaseStorage
import SDWebImageSwiftUI
import Combine

struct MyListingsView: View {
    @Binding var userListings: [Listing]
    @Binding var selectedListing: Listing?
    var onRefresh: () -> Void

    @EnvironmentObject var appViewModel: AppViewModel
    @State private var showDeleteAlert = false
    @State private var listingToDelete: Listing?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if userListings.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("You haven't created any listings yet.")
                            .font(.title3)
                            .foregroundColor(.gray)
                        Text("Your active listings will appear here.")
                            .font(.callout)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .padding(.top, 50)
                } else {
                    ForEach(userListings) { listing in
                        listingCard(for: listing)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    listingToDelete = listing
                                    showDeleteAlert = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .padding(.vertical)
        }
        .refreshable {
            onRefresh()
        }
        .alert("Confirm Delete", isPresented: $showDeleteAlert, presenting: listingToDelete) { listing in
            Button("Delete", role: .destructive) {
                Task {
                    await deleteListing(listing)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { listing in
            Text("Are you sure you want to delete \"\(listing.title)\"? This cannot be undone.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .listingUpdated).receive(on: RunLoop.main)) { _ in
            onRefresh()
        }
    }

    @ViewBuilder
    private func listingCard(for listing: Listing) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let urlString = listing.imageUrls.first, let imageURL = URL(string: urlString) {
                WebImage(url: imageURL)
                    .resizable()
                    .indicator(.activity)
                    .transition(.fade(duration: 0.5))
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .background(Color.gray.opacity(0.1))
                    .clipped()
                    .cornerRadius(10)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .cornerRadius(10)
                    .overlay(
                        Image(systemName: "photo.on.rectangle.angled")
                            .foregroundColor(.gray)
                            .font(.title2)
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(listing.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Button("Edit") {
                        self.selectedListing = listing
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .buttonStyle(.borderless)
                }

                Text(String(format: "$%.2f", listing.price))
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Posted: \(listing.timestamp, style: .date)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.08), radius: 5, x: 0, y: 3)
        .padding(.horizontal)
    }

    private func deleteListing(_ listing: Listing) async {
        guard let listingID = listing.id else { return }
        let db = Firestore.firestore()
        let storage = Storage.storage()

        do {
            try await db.collection("listings").document(listingID).delete()

            // Remove listingID from any user's savedListingIds
            let usersSnapshot = try await db.collection("users").whereField("savedListingIds", arrayContains: listingID).getDocuments()
            for document in usersSnapshot.documents {
                try await db.collection("users").document(document.documentID).updateData([
                    "savedListingIds": FieldValue.arrayRemove([listingID])
                ])
            }

            // Delete images from storage
            for urlString in listing.imageUrls {
                if let url = URL(string: urlString),
                   let imageName = url.pathComponents.last {
                    let sellerId = listing.sellerId
                    let ref = storage.reference().child("listing_images/\(sellerId)/\(imageName)")
                    try? await ref.delete()
                }
            }

            appViewModel.removeSavedListingId(listingID)
            onRefresh()
        } catch {
            print("Failed to delete listing: \(error.localizedDescription)")
        }
    }
}
