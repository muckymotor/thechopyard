import SwiftUI
import SDWebImageSwiftUI

struct ListingRow: View {
    let listing: Listing
    let locationManager: LocationManager // Assuming LocationManager is an ObservableObject or provides location
    @EnvironmentObject var appViewModel: AppViewModel

    // Determine if the listing is saved, handling optional ID
    private var isSaved: Bool {
        guard let listingID = listing.id else { return false }
        return appViewModel.savedListingIds.contains(listingID)
    }

    var body: some View {
        NavigationLink(destination: ListingDetailView(listing: listing)) {
            VStack(alignment: .leading, spacing: 0) {
                // Listing Image
                if let urlString = listing.imageUrls.first, let url = URL(string: urlString) {
                    WebImage(url: url)
                        .resizable()
                        .indicator(.activity)
                        .scaledToFill()
                        // Making image square based on screen width, similar to your previous setup
                        .frame(width: UIScreen.main.bounds.width - 32, height: UIScreen.main.bounds.width - 32)
                        .clipped()
                        .cornerRadius(10)
                        .padding(.horizontal) // Consistent padding with content below
                        .padding(.bottom) // Add some space below the image
                } else {
                    // Placeholder for missing image
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: UIScreen.main.bounds.width - 32, height: UIScreen.main.bounds.width - 32)
                        .cornerRadius(10)
                        .overlay(Image(systemName: "photo").font(.largeTitle).foregroundColor(.gray))
                        .padding(.horizontal)
                        .padding(.bottom)
                }

                // Details section
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Text(listing.title)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer()

                        Button {
                            // The toggleSavedListing function in AppViewModel already handles optional ID
                            appViewModel.toggleSavedListing(listing)
                        } label: {
                            // ✅ **CORRECTED HERE**
                            Image(systemName: isSaved ? "heart.fill" : "heart")
                                .foregroundColor(.red)
                                .imageScale(.large)
                        }
                        .buttonStyle(.plain) // Keeps the tap effect localized to the heart
                    }

                    Text("$\(listing.price, specifier: "%.2f")") // Using string interpolation with specifier
                        .font(.subheadline)
                        .fontWeight(.medium) // Make price stand out a bit
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack {
                        if let locationName = listing.locationName, !locationName.isEmpty {
                            Text(locationName)
                                .font(.footnote)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        Spacer()

                        if let userLocation = locationManager.location {
                             // Uses the clLocation computed property from Listing struct
                            Text(listing.formattedDistance(from: userLocation))
                                .font(.footnote)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                }
                .padding([.horizontal, .bottom]) // Apply padding to the text content VStack
                .frame(maxWidth: .infinity, alignment: .leading) // Ensure it takes full width
            }
            .background(Color(.systemBackground)) // Adapts to light/dark mode
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
            .padding(.bottom, 8) // Space between rows
        }
        .buttonStyle(.plain) // Apply to NavigationLink to prevent entire row blue tint
    }
}
