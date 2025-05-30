import SwiftUI
import FirebaseFirestore
import SDWebImageSwiftUI

struct MyListingsView: View {
    @Binding var userListings: [Listing]
    @Binding var showingEditSheet: Bool
    @Binding var selectedListing: Listing?
    var onRefresh: () -> Void

    @State private var showDeleteAlert = false
    @State private var listingToDelete: Listing? = nil

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if userListings.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("You haven't created any listings yet.")
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
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
        .navigationTitle("My Listings")
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
            Text("Are you sure you want to delete this listing? This cannot be undone.")
        }
    }

    private func listingCard(for listing: Listing) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let url = listing.imageUrls.first, let imageURL = URL(string: url) {
                WebImage(url: imageURL)
                    .resizable()
                    .indicator(.activity)
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipped()
                    .cornerRadius(10)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(listing.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Button("Edit") {
                        selectedListing = listing
                        showingEditSheet = true
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .buttonStyle(.borderless)
                }

                Text(String(format: "$%.2f", listing.price))
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text("Posted: \(listing.timestamp, style: .date)")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private func deleteListing(_ listing: Listing) async {
        do {
            try await Firestore.firestore().collection("listings").document(listing.id).delete()
            onRefresh()
        } catch {
            print("Error deleting listing: \(error.localizedDescription)")
        }
    }
}
