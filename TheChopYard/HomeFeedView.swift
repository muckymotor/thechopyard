import SwiftUI
import CoreLocation
import FirebaseFirestore

struct HomeFeedView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @StateObject private var locationManager = LocationManager()

    @State private var selectedRadius: Double = 210.0
    @State private var selectedCategories: Set<String> = []
    @State private var selectedSort: SortOption = .newest
    @State private var showingFilter = false
    @State private var listingListener: ListenerRegistration?

    enum SortOption: String, CaseIterable, Identifiable {
        case newest = "Newest"
        case nearest = "Nearest"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if locationManager.authorizationStatus == .denied {
                    Text("Location permission denied. Please enable it in Settings.")
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
                        .frame(height: 40)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingFilter.toggle() }) {
                        Image(systemName: "slider.horizontal.3").imageScale(.large)
                    }
                }
            }
            .navigationDestination(for: Listing.self) { ListingDetailView(listing: $0) }
        }
        .sheet(isPresented: $showingFilter) {
            FilterOptionsView(
                selectedRadius: $selectedRadius,
                selectedCategories: $selectedCategories,
                selectedSort: $selectedSort,
                onApply: {}
            )
        }
        .task {
            if locationManager.location == nil {
                locationManager.requestPermissionAndFetchLocation()
            }
        }
        .onAppear {
            startLiveListingListener()
        }
        .onDisappear {
            listingListener?.remove()
        }
    }

    private func startLiveListingListener() {
        listingListener?.remove()

        let query = Firestore.firestore().collection("listings")
            .order(by: "timestamp", descending: true)

        listingListener = query.addSnapshotListener { snapshot, error in
            guard let docs = snapshot?.documents else { return }
            let updatedListings = docs.compactMap { try? $0.data(as: Listing.self) }

            DispatchQueue.main.async {
                appViewModel.listings = updatedListings
            }
        }
    }

    private var listingsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if appViewModel.isLoadingPage && appViewModel.listings.isEmpty {
                    ProgressView("Loading...").padding(.top, 50)
                } else if filteredListings.isEmpty && !appViewModel.isLoadingPage {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No listings found.")
                            .font(.title3)
                            .foregroundColor(.gray)
                        Text("Try adjusting your filters or check back later.")
                            .font(.callout)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .padding(.top, 50)
                } else {
                    ForEach(filteredListings) { listingItem in
                        NavigationLink(value: listingItem) {
                            ListingRow(listing: listingItem, locationManager: locationManager)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical)
        }
        .refreshable {
            await appViewModel.fetchListings(
                categories: selectedCategories,
                sortBy: selectedSort,
                loadMore: false
            )
        }
    }

    private var filteredListings: [Listing] {
        var listings = appViewModel.listings

        if locationManager.authorizationStatus != .denied,
           let userLocation = locationManager.location,
           selectedRadius < 210 {
            let maxDistance = selectedRadius * 1609.34
            listings = listings.filter {
                $0.clLocation.distance(from: userLocation) <= maxDistance
            }
        }

        if !selectedCategories.isEmpty {
            listings = listings.filter { selectedCategories.contains($0.category ?? "") }
        }

        if selectedSort == .nearest, let userLocation = locationManager.location {
            listings.sort {
                $0.clLocation.distance(from: userLocation) < $1.clLocation.distance(from: userLocation)
            }
        }

        return listings
    }

    static let categories = [
        "Air Intake & Fuel Systems", "Brakes", "Drivetrain & Transmission", "Electrical & Wiring",
        "Engine", "Exhaust", "Fenders", "Frame & Chassis", "Gas Tanks", "Gauge & Instruments",
        "Handlebars & Controls", "Lighting", "Oil Tanks", "Seats", "Suspension", "Tires",
        "Wheels/Wheel Components", "Motorcycles", "Other"
    ]
}


struct FilterOptionsView: View {
    @Binding var selectedRadius: Double
    @Binding var selectedCategories: Set<String>
    @Binding var selectedSort: HomeFeedView.SortOption // Use the enum from HomeFeedView
    var onApply: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView { // Sheets often have their own NavigationView for a title/done button
            Form {
                Section(header: Text("Search Radius")) {
                    Slider(value: $selectedRadius, in: 0...210, step: 10)
                    Text(selectedRadius >= 210 ? "Everywhere" : "\(Int(selectedRadius)) miles")
                        .font(.caption).foregroundColor(.gray)
                }

                Section(header: Text("Sort By")) {
                    Picker("Sort By", selection: $selectedSort) {
                        ForEach(HomeFeedView.SortOption.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                Section(header: Text("Category")) {
                    List { // Use List for multi-selection toggles
                        ForEach(HomeFeedView.categories, id: \.self) { category in
                            Toggle(category, isOn: Binding(
                                get: { selectedCategories.contains(category) },
                                set: { isOn in
                                    if isOn { selectedCategories.insert(category) }
                                    else { selectedCategories.remove(category) }
                                }
                            ))
                        }
                    }
                }
                
                Section {
                    Button("Apply Filters") {
                        onApply()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Filter Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") {
                        selectedRadius = 210.0
                        selectedCategories.removeAll()
                        selectedSort = .newest
                        // onApply() // Optionally apply reset immediately
                        // dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// Example ErrorBannerView (create this in a separate file too)
struct ErrorBannerView: View {
    let errorMessage: String

    var body: some View {
        Text("Error: \(errorMessage)")
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(10)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                // You might want this banner to disappear after a few seconds
            }
    }
}
