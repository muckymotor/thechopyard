import SwiftUI
import FirebaseFirestore
import CoreLocation

struct SavedListingsView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @StateObject private var locationManager = LocationManager()
    @State private var savedListings: [Listing] = []
    @State private var isLoading = false

    private let db = Firestore.firestore()

    var body: some View {
        NavigationView {
            VStack {
                if locationManager.authorizationStatus == .denied {
                    Text("Location permission denied. Please enable it in Settings to filter by distance and see nearby listings.")
                        .foregroundColor(.red)
                        .padding()
                        .multilineTextAlignment(.center)
                }
                listingsScrollView
            }
            .navigationBarTitle("Saved Listings", displayMode: .inline)
        }
        .task(id: appViewModel.savedListingIds) {
            await refreshSavedListings()
        }
        .onAppear {
            if locationManager.location == nil {
                locationManager.requestPermissionAndFetchLocation()
            }
        }
    }

    private var listingsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if isLoading && savedListings.isEmpty {
                    ProgressView("Loading saved listings...")
                        .padding(.top, 40)
                } else if filteredListings.isEmpty && !isLoading {
                    Text("You have no saved listings.")
                        .foregroundColor(.gray)
                        .padding(.top, 40)
                } else {
                    ForEach(filteredListings) { item in
                        ListingRow(
                            listing: item,
                            locationManager: locationManager
                        )
                        .environmentObject(appViewModel)
                    }

                    if isLoading && !savedListings.isEmpty {
                        ProgressView().padding()
                    }
                }
            }
            .padding(.top)
        }
    }

    private func refreshSavedListings() async {
        isLoading = true

        guard !appViewModel.savedListingIds.isEmpty else {
            self.savedListings = []
            isLoading = false
            return
        }

        do {
            let snapshot = try await db.collection("listings")
                .whereField(FieldPath.documentID(), in: Array(appViewModel.savedListingIds))
                .getDocuments()

            savedListings = snapshot.documents.compactMap { doc in
                Listing(id: doc.documentID, data: doc.data())
            }
        } catch {
            print("Error fetching saved listings: \(error.localizedDescription)")
            savedListings = []
        }

        isLoading = false
    }

    private var filteredListings: [Listing] {
        let locationFiltered: [Listing]

        if locationManager.authorizationStatus == .denied || locationManager.location == nil {
            locationFiltered = savedListings
        } else {
            let userLocation = locationManager.location!
            locationFiltered = savedListings.filter { listing in
                let distanceInMiles = listing.location.distance(from: userLocation) / 1609.34
                return distanceInMiles <= 100
            }
        }

        return locationFiltered.sorted { $0.timestamp > $1.timestamp }
    }
}
