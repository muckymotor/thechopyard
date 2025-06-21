import SwiftUI
import CoreLocation // Keep for LocationManager and distance calculations
import Combine
import FirebaseFirestore
// Assuming ListingRow is defined elsewhere and works with the Listing model
// Assuming LocationManager is correctly defined and provides location updates

struct HomeFeedView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @StateObject private var locationManager = LocationManager()

    // Filter and Sort state remains local to the view
    @State private var selectedRadius: Double = 210.0 // Max radius for "Everywhere"
    @State private var selectedCategories: Set<String> = []
    @State private var selectedSort: SortOption = .newest
    @State private var showingFilter = false

    enum SortOption: String, CaseIterable, Identifiable {
        case newest = "Newest"
        case nearest = "Nearest"
        var id: String { rawValue }
    }

    var body: some View {
        // ✅ Use NavigationStack for modern navigation APIs
        NavigationStack {
            VStack(spacing: 0) { // Reduce default VStack spacing if not needed
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
                    Image("chopyard_logo") // Ensure this image asset exists
                        .resizable()
                        .scaledToFit()
                        .frame(height: 40) // Adjusted height slightly
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingFilter.toggle() }) {
                        Image(systemName: "slider.horizontal.3")
                            .imageScale(.large)
                    }
                }
            }
            // This .navigationDestination handles presenting ListingDetailView
            // when a Listing object is provided as the value to a NavigationLink
            .navigationDestination(for: Listing.self) { listingItem in
                ListingDetailView(listing: listingItem)
                // AppViewModel is already in the environment, no need to pass it again here
                // unless ListingDetailView or ChatView specifically remove it.
            }
        }
        // .environmentObject(appViewModel) // AppViewModel is already injected by ContentView/App
        .sheet(isPresented: $showingFilter) {
            // Pass bindings and a callback to the filter sheet
            FilterOptionsView( // Assuming you have a separate FilterOptionsView
                selectedRadius: $selectedRadius,
                selectedCategories: $selectedCategories,
                selectedSort: $selectedSort,
                onApply: {
                    Task { await applyFiltersAndRefresh() }
                }
            )
            // If filterSheet is a computed var in this View, ensure it has its own NavigationView or is simple.
            // For better structure, FilterOptionsView is often a separate struct.
        }
        // Use .task for operations tied to view lifecycle or specific state changes
        .task(id: selectedCategories) { await applyFiltersAndRefresh() }
        .task(id: selectedSort) { await applyFiltersAndRefresh() }
        // Initial fetch and fetch when user logs in/out (handled by AppViewModel's listener now too)
        .task(id: appViewModel.user?.uid) { // Re-fetch if user changes, good for initial load too
            print("HomeFeedView: User UID changed or view appeared, fetching initial listings.")
            await appViewModel.fetchListings(categories: selectedCategories, sortBy: selectedSort, loadMore: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .listingUpdated).receive(on: RunLoop.main)) { notification in
            if let updated = notification.object as? Listing {
                appViewModel.updateListing(updated)
            } else if let id = notification.object as? String {
                Task { await appViewModel.refreshListing(id: id) }
            } else {
                Task {
                    await appViewModel.fetchListings(categories: selectedCategories, sortBy: selectedSort, loadMore: false)
                }
            }
        }
        .onAppear {
            // Redundant if .task(id: appViewModel.user?.uid) handles initial load well.
            // Kept for safety if listings are empty and user is already set.
            if appViewModel.listings.isEmpty && appViewModel.user != nil {
                print("HomeFeedView: .onAppear, listings empty, fetching.")
                Task {
                    await appViewModel.fetchListings(categories: selectedCategories, sortBy: selectedSort, loadMore: false)
                }
            }
            if locationManager.location == nil { // Request location on appear
                locationManager.requestPermissionAndFetchLocation()
            }
        }
    }

    private var listingsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if appViewModel.isLoadingPage && appViewModel.listings.isEmpty {
                    ProgressView("Loading...")
                        .padding(.top, 50)
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
                        .onAppear {
                            if let lastDisplayed = filteredListings.last,
                               listingItem.id == lastDisplayed.id,
                               !appViewModel.isLoadingPage {
                                Task {
                                    await appViewModel.fetchListings(
                                        categories: selectedCategories,
                                        sortBy: selectedSort,
                                        loadMore: true
                                    )
                                }
                            }
                        }
                    }

                    if appViewModel.isLoadingPage && !appViewModel.listings.isEmpty {
                        ProgressView().padding()
                    }
                }
            }
            .padding(.vertical)
        }
        .refreshable {
            print("HomeFeedView: Refresh triggered.")

            do {
                async let listingsRefresh: () = appViewModel.fetchListings(
                    categories: selectedCategories,
                    sortBy: selectedSort,
                    loadMore: false
                )

                async let delay: () = try Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

                _ = try await (listingsRefresh, delay)
            } catch {
                print("HomeFeedView: Refresh cancelled or failed: \(error.localizedDescription)")
            }
        }
        .overlay(alignment: .center) {
            if let errorMessage = appViewModel.errorMessage {
                ErrorBannerView(errorMessage: errorMessage)
            }
        }
    }


    // Assuming filterSheet is now a separate view, e.g., FilterOptionsView
    // If filterSheet was a computed property, ensure it doesn't contain its own NavigationView
    // if presented as a sheet from within this NavigationStack context.
    // For simplicity, I'll assume you'll create/use a separate FilterOptionsView struct.
    // If 'filterSheet' is a computed property, it should be:
    private var filterSheet: some View {
        // If this sheet needs its own navigation, wrap it in a NavigationStack
        // For simple filters, a Form within a VStack is often enough.
        FilterOptionsView(
            selectedRadius: $selectedRadius,
            selectedCategories: $selectedCategories,
            selectedSort: $selectedSort,
            onApply: {
                Task { await applyFiltersAndRefresh() }
            }
        )
    }
    
    static let categories = [ // Keep categories here if specific to HomeFeed filters
        "Air Intake & Fuel Systems", "Brakes", "Drivetrain & Transmission", "Electrical & Wiring",
        "Engine", "Exhaust", "Fenders", "Frame & Chassis", "Gas Tanks", "Gauge & Instruments",
        "Handlebars & Controls", "Lighting", "Oil Tanks", "Seats", "Suspension", "Tires",
        "Wheels/Wheel Components", "Motorcycles", "Other"
    ]

    private func applyFiltersAndRefresh() async {
        print("HomeFeedView: Applying filters and refreshing.")
        // When filters change, AppViewModel should fetch a new, non-paginated list
        await appViewModel.fetchListings(
            categories: selectedCategories,
            sortBy: selectedSort,
            loadMore: false // Always a fresh load when applying filters
        )
    }

    private var filteredListings: [Listing] {
        // This client-side filtering is applied AFTER AppViewModel fetches listings
        // (which might already be server-side filtered by category and sorted by newest).
        var listingsToFilter = appViewModel.listings

        // Client-side distance filtering
        if locationManager.authorizationStatus != .denied, let userLocation = locationManager.location {
            let radiusInMiles = selectedRadius
            if radiusInMiles < 210 { // 210 or more means "Everywhere"
                let radiusInMeters = radiusInMiles * 1609.34
                listingsToFilter = listingsToFilter.filter { listing in
                    listing.clLocation.distance(from: userLocation) <= radiusInMeters
                }
            }
        }

        // Client-side sorting (only if 'nearest' is selected, as 'newest' is handled by server/AppViewModel)
        if selectedSort == .nearest {
            guard let userLocation = locationManager.location else { return listingsToFilter }
            return listingsToFilter.sorted {
                $0.clLocation.distance(from: userLocation) < $1.clLocation.distance(from: userLocation)
            }
        }
        // If .newest, assume appViewModel.listings are already sorted or don't need further client-side sort.
        return listingsToFilter
    }
}

// You would create this view in a new file for better organization
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
