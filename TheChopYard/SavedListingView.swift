// SavedListingsView.swift

import SwiftUI
import FirebaseFirestore
import CoreLocation

// NO ErrorAlertItem struct definition here anymore.
// It will use the definition from AppUtilities.swift (or your shared file).

struct SavedListingsView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var locationManager: LocationManager
    @State private var savedListings: [Listing] = []
    @State private var isLoading = false
    @State private var errorAlertItem: ErrorAlertItem? // This will now refer to the shared definition

    // ... (rest of your SavedListingsView code remains the same as you provided in the last turn)
    // The body, listingsScrollView, fetchFullSavedListings, clientSideSortedListings methods
    // DO NOT need to change again for this specific error.
    // Just ensure the duplicate/commented-out struct definition is removed from this file.

    var body: some View {
        NavigationView {
            Group {
                if isLoading && savedListings.isEmpty {
                    ProgressView("Loading saved listings...")
                } else if savedListings.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "heart.slash.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No Saved Listings")
                            .font(.title3)
                            .foregroundColor(.gray)
                        Text("Listings you save will appear here.")
                            .font(.callout)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    listingsScrollView
                }
            }
            .navigationTitle("Saved Listings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isLoading { ProgressView() }
                }
            }
        }
        .task(id: appViewModel.savedListingIds) {
            await fetchFullSavedListings()
        }
        .onAppear {
            if savedListings.isEmpty && !appViewModel.savedListingIds.isEmpty && !isLoading {
                Task { await fetchFullSavedListings() }
            }
            if locationManager.location == nil {
                locationManager.requestPermissionAndFetchLocation()
            }
        }
        .alert(item: $errorAlertItem) { item in
            Alert(title: Text(item.title), message: Text(item.message), dismissButton: .default(Text("OK")))
        }
    }

    private var listingsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(clientSideSortedListings) { item in
                    ListingRow(
                        listing: item,
                        locationManager: locationManager
                    )
                    .environmentObject(appViewModel)
                }
            }
            .padding(.vertical)
        }
        .refreshable {
            await fetchFullSavedListings()
        }
    }

    private func fetchFullSavedListings() async {
        isLoading = true
        errorAlertItem = nil
        let db = Firestore.firestore()

        let idsToFetch = Array(appViewModel.savedListingIds)

        guard !idsToFetch.isEmpty else {
            self.savedListings = []
            isLoading = false
            return
        }

        var fetchedListings: [Listing] = []
        let chunkSize = 30
        let chunks = stride(from: 0, to: idsToFetch.count, by: chunkSize).map {
            Array(idsToFetch[$0..<min($0 + chunkSize, idsToFetch.count)])
        }

        do {
            for chunk in chunks {
                if chunk.isEmpty { continue }
                let snapshot = try await db.collection("listings")
                    .whereField(FieldPath.documentID(), in: chunk)
                    .getDocuments()
                
                let chunkListings = snapshot.documents.compactMap { document -> Listing? in
                    try? document.data(as: Listing.self)
                }
                fetchedListings.append(contentsOf: chunkListings)
            }
            self.savedListings = fetchedListings
        } catch {
            print("Error fetching saved listings details: \(error.localizedDescription)")
            self.savedListings = []
            self.errorAlertItem = ErrorAlertItem(message: "Could not load saved listings: \(error.localizedDescription)")
        }
        isLoading = false
    }

    private var clientSideSortedListings: [Listing] {
        return savedListings.sorted { $0.timestamp > $1.timestamp }
    }
}
