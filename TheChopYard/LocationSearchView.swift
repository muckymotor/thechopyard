import SwiftUI
import MapKit

struct LocationSearchView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = LocationSearchViewModel()
    @State private var searchText = ""

    var onLocationSelected: (String, CLLocationCoordinate2D) -> Void

    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.searchResults, id: \.self) { result in
                    VStack(alignment: .leading) {
                        Text(result.title)
                            .font(.headline)
                        if !result.subtitle.isEmpty {
                            Text(result.subtitle)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let displayName = result.subtitle.isEmpty
                            ? result.title
                            : "\(result.title), \(result.subtitle)"
                        viewModel.resolveLocation(for: result) { coordinate in
                            if let coordinate = coordinate {
                                onLocationSelected(displayName, coordinate)
                            }
                            dismiss()
                        }
                    }
                }
            }
            .searchable(text: $searchText)
            .onChange(of: searchText) { newValue in
                viewModel.updateSearch(with: newValue)
            }
            .navigationTitle("Search Location")
        }
    }
}

class LocationSearchViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var searchResults: [MKLocalSearchCompletion] = []
    private var completer: MKLocalSearchCompleter

    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.0902, longitude: -95.7129),
            latitudinalMeters: 3_000_000,
            longitudinalMeters: 3_000_000
        ) // Covers most of the US
    }

    func updateSearch(with query: String) {
        completer.queryFragment = query
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.searchResults = completer.results
        }
    }

    func resolveLocation(for completion: MKLocalSearchCompletion, completionHandler: @escaping (CLLocationCoordinate2D?) -> Void) {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            completionHandler(response?.mapItems.first?.placemark.coordinate)
        }
    }
}
