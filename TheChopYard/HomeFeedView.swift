import SwiftUI
import CoreLocation
import FirebaseFirestore

struct HomeFeedView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @StateObject private var locationManager = LocationManager()
    @State private var listings: [Listing] = []
    @State private var selectedRadius: Double = 210.0
    @State private var selectedCategories: Set<String> = []
    @State private var selectedSort: SortOption = .newest
    @State private var showingFilter = false
    @State private var isLoading = false
    @State private var lastDocument: DocumentSnapshot?
    @State private var initialLoadComplete = false

    private let pageSize = 10
    private let db = Firestore.firestore()

    enum SortOption: String, CaseIterable, Identifiable {
        case newest = "Newest"
        case nearest = "Nearest"
        var id: String { rawValue }
    }

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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image("chopyard_logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 45)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingFilter.toggle() }) {
                        Image(systemName: "slider.horizontal.3")
                            .imageScale(.large)
                    }
                }
            }
        }
        .sheet(isPresented: $showingFilter) {
            filterSheet
        }
        .task(id: appViewModel.user?.uid) {
            await refreshListings()
        }
        .onAppear {
            if !initialLoadComplete {
                Task { await refreshListings() }
            }
        }
    }

    private var listingsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if isLoading && listings.isEmpty {
                    ProgressView("Loading...")
                        .padding(.top, 40)
                } else if filteredListings.isEmpty && !isLoading {
                    Text("No listings found matching your criteria.")
                        .foregroundColor(.gray)
                        .padding(.top, 40)
                } else {
                    ForEach(filteredListings) { item in
                        ListingRow(listing: item, locationManager: locationManager)
                            .environmentObject(appViewModel)
                            .onAppear {
                                if item == listings.last && !isLoading {
                                    Task { await loadMoreListings() }
                                }
                            }
                    }
                    if isLoading && !listings.isEmpty {
                        ProgressView().padding()
                    }
                }
            }
            .padding(.top)
        }
        .refreshable {
            await refreshListings()
        }
    }

    private var filterSheet: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Filters")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.top)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Search Radius")
                            .font(.headline)
                        Slider(value: $selectedRadius, in: 0...210, step: 10)
                        Text(selectedRadius >= 210 ? "200+ miles" : "\(Int(selectedRadius)) miles")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sort By")
                            .font(.headline)
                        Picker("Sort By", selection: $selectedSort) {
                            ForEach(SortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Category")
                            .font(.headline)
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(categories, id: \.self) { category in
                                Toggle(isOn: Binding(
                                    get: { selectedCategories.contains(category) },
                                    set: { isOn in
                                        if (isOn) {
                                            selectedCategories.insert(category)
                                        } else {
                                            selectedCategories.remove(category)
                                        }
                                    }
                                )) {
                                    Text(category)
                                }
                            }
                        }
                    }

                    HStack(spacing: 16) {
                        Button(action: {
                            showingFilter = false
                            Task { await refreshListings() }
                        }) {
                            Text("Apply")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }

                        Button(action: {
                            selectedRadius = 1.0
                            selectedCategories.removeAll()
                            selectedSort = .newest
                        }) {
                            Text("Reset Filters")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(12)
                        }
                    }
                }
                .padding()
            }
        }
    }

    private let categories = [
        "Air Intake & Fuel Systems", "Brakes", "Drivetrain & Transmission", "Electrical & Wiring",
        "Engine", "Exhaust", "Fenders", "Frame & Chassis", "Gas Tanks", "Gauge & Instruments",
        "Handlebars & Controls", "Lighting", "Oil Tanks", "Seats", "Suspension", "Tires",
        "Wheels/Wheel Components", "Motorcycles", "Other"
    ]

    private func buildQuery() -> Query {
        var query: Query = db.collection("listings")

        if !selectedCategories.isEmpty {
            query = query.whereField("category", in: Array(selectedCategories))
        }

        if selectedSort == .newest || selectedCategories.isEmpty {
            query = query.order(by: "timestamp", descending: true)
        }

        return query.limit(to: pageSize)
    }

    private func refreshListings() async {
        isLoading = true
        let initialQuery = buildQuery()

        do {
            let snapshot = try await initialQuery.getDocuments()
            listings = snapshot.documents.compactMap { doc in
                Listing(id: doc.documentID, data: doc.data())
            }
            lastDocument = snapshot.documents.last
            initialLoadComplete = true
        } catch {
            print("Error refreshing listings: \(error.localizedDescription)")
        }

        isLoading = false
    }

    private func loadMoreListings() async {
        guard !isLoading, let lastDoc = lastDocument else { return }

        isLoading = true
        var paginatedQuery = buildQuery().start(afterDocument: lastDoc)

        do {
            let snapshot = try await paginatedQuery.getDocuments()
            let newListings = snapshot.documents.compactMap { doc in
                Listing(id: doc.documentID, data: doc.data())
            }
            listings.append(contentsOf: newListings)
            lastDocument = snapshot.documents.last
        } catch {
            print("Error loading more listings: \(error.localizedDescription)")
        }

        isLoading = false
    }

    private var filteredListings: [Listing] {
        let locationFiltered: [Listing]

        if locationManager.authorizationStatus == .denied || locationManager.location == nil {
            locationFiltered = listings
        } else {
            let userLocation = locationManager.location!
            locationFiltered = listings.filter { listing in
                let distanceInMiles = listing.location.distance(from: userLocation) / 1609.34
                return selectedRadius >= 101 || distanceInMiles <= selectedRadius
            }
        }

        let categoryFiltered = locationFiltered.filter { listing in
            selectedCategories.isEmpty || (listing.category != nil && selectedCategories.contains(listing.category!))
        }

        switch selectedSort {
        case .newest:
            return categoryFiltered.sorted { $0.timestamp > $1.timestamp }
        case .nearest:
            guard let userLocation = locationManager.location else { return categoryFiltered }
            return categoryFiltered.sorted {
                $0.location.distance(from: userLocation) < $1.location.distance(from: userLocation)
            }
        }
    }
}
