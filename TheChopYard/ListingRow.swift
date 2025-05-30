import SwiftUI
import SDWebImageSwiftUI

struct ListingRow: View {
    let listing: Listing
    let locationManager: LocationManager
    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        NavigationLink(destination: ListingDetailView(listing: listing)) {
            VStack(alignment: .leading, spacing: 0) {
                // Listing Image
                if let urlString = listing.imageUrls.first, let url = URL(string: urlString) {
                    WebImage(url: url)
                        .resizable()
                        .indicator(.activity)
                        .scaledToFill()
                        .frame(width: UIScreen.main.bounds.width - 32, height: UIScreen.main.bounds.width - 32)
                        .clipped()
                        .cornerRadius(10)
                        .padding(.horizontal)
                        .padding(.bottom)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Text(listing.title)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer()

                        Button {
                            appViewModel.toggleSavedListing(listing)
                        } label: {
                            Image(systemName: appViewModel.savedListingIds.contains(listing.id) ? "heart.fill" : "heart")
                                .foregroundColor(.red)
                                .imageScale(.large)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("$\(listing.price, specifier: "%.2f")")
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack {
                        if let locationName = listing.locationName {
                            Text(locationName)
                                .font(.footnote)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        Spacer()

                        if let userLocation = locationManager.location {
                            Text(listing.formattedDistance(from: userLocation))
                                .font(.footnote)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                }
                .padding([.horizontal, .bottom])
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
            .padding(.bottom, 8)
        }
        .buttonStyle(.plain)
    }
}
