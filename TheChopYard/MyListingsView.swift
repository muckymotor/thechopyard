import SwiftUI
import FirebaseFirestore // Keep if any direct Firestore interaction remains, though delete is here
import SDWebImageSwiftUI // Assuming you're using this for image loading

struct MyListingsView: View {
    @Binding var userListings: [Listing]
    // ✅ REMOVED: @Binding var showingEditSheet: Bool
    @Binding var selectedListing: Listing? // This will be set to trigger the sheet in ProfileView
    var onRefresh: () -> Void

    @State private var showDeleteAlert = false
    @State private var listingToDelete: Listing? = nil
    // @EnvironmentObject var appViewModel: AppViewModel // Only if directly needed for actions not covered by bindings/callbacks

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if userListings.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray.fill") // Using a filled system image
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
        // .navigationTitle("My Listings") // Usually set by the containing NavigationView in ProfileView
        // If this view can be presented modally or independently, a navigation title here is fine.
        // For now, assuming ProfileView handles the overall navigation title.
        .refreshable {
            onRefresh()
        }
        .alert("Confirm Delete", isPresented: $showDeleteAlert, presenting: listingToDelete) { listingForAlert in
            Button("Delete", role: .destructive) {
                Task {
                    await deleteListing(listingForAlert)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { listingForAlert in
            // Use optional chaining for listing title in case it's unexpectedly nil (though unlikely for an existing listing)
            Text("Are you sure you want to delete \"\(listingForAlert.title)\"? This cannot be undone.")
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
                        Image(systemName: "photo.on.rectangle.angled") // Different placeholder icon
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
                        // ✅ **CHANGED HERE**: Only set selectedListing.
                        // This will propagate to ProfileView and trigger its .sheet.
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
        guard let listingID = listing.id else {
            print("Error: Listing ID is nil. Cannot delete.")
            // Optionally, show an error to the user
            return
        }

        do {
            try await Firestore.firestore().collection("listings").document(listingID).delete()
            print("Listing \(listingID) successfully deleted from Firestore.")
            onRefresh() // This will trigger fetchUserListings in ProfileView
        } catch {
            print("Error deleting listing \(listingID) from Firestore: \(error.localizedDescription)")
            // Optionally, show an error to the user
        }
    }
}
