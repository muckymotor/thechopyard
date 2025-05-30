import SwiftUI
import PhotosUI
import FirebaseStorage
import FirebaseFirestore
import FirebaseAuth
import CoreLocation

@available(iOS 16.0, *)
struct CreateListingView: View {
    @Environment(\.dismiss) var dismiss
    @State private var title = ""
    @State private var price = ""
    @State private var listingDescription = "" // Renamed from 'description'
    @State private var locationText = ""
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var uiImages: [UIImage] = []
    @State private var isSubmitting = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isShowingLocationSearch = false
    @State private var selectedCategory: String = ""

    private let categories = [
        "Air Intake & Fuel Systems", "Brakes", "Drivetrain & Transmission", "Electrical & Wiring",
        "Engine", "Exhaust", "Fenders", "Frame & Chassis", "Gas Tanks", "Gauge & Instruments",
        "Handlebars & Controls", "Lighting", "Oil Tanks", "Seats", "Suspension", "Tires",
        "Wheels/Wheel Components", "Motorcycles", "Other"
    ]

    private let db = Firestore.firestore()
    private let storage = Storage.storage().reference()

    var body: some View {
        NavigationView {
            Form {
                detailsSection
                photoSection
                submitButtonSection
            }
            .navigationTitle("Create Listing")
        }
        .sheet(isPresented: $isShowingLocationSearch) {
            LocationSearchView { selectedPlace, coordinate in
                locationText = selectedPlace
                selectedCoordinate = coordinate
            }
        }
        .onChange(of: selectedPhotoItems) { _ in
            Task {
                var loadedImages: [UIImage] = []
                for item in selectedPhotoItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        loadedImages.append(image)
                    }
                }
                uiImages = loadedImages
            }
        }
        .alert(isPresented: $showAlert) {
             Alert(title: Text(alertMessage.contains("successfully") ? "Success" : "Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }

    private var detailsSection: some View {
        Section(header: Text("Details")) {
            TextField("Title", text: $title)
            TextField("Price", text: $price).keyboardType(.decimalPad)
            TextField("Description", text: $listingDescription, axis: .vertical)
                 .lineLimit(3...6)
            locationField
            categorySelectionSection // This is the corrected part
        }
    }

    private var locationField: some View {
        HStack {
            TextField("Location", text: $locationText).disabled(true)
            Spacer()
            Button {
                isShowingLocationSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
            }
        }
    }

    // --- CORRECTED SECTION ---
    private var categorySelectionSection: some View {
        VStack(alignment: .leading) { // Wrap in a VStack
            Picker("Category", selection: $selectedCategory) {
                Text("Select Category").tag("") // Placeholder/default empty tag
                ForEach(categories, id: \.self) { category in
                    Text(category).tag(category)
                }
            }

            if selectedCategory.isEmpty {
                Text("Please select a category.")
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        }
    }
    // --- END CORRECTED SECTION ---


    private var photoSection: some View {
        Section(header: Text("Photos")) {
            PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 10, matching: .images) {
                Text("Select up to 10 photos")
            }

            if !uiImages.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(uiImages, id: \.self) { image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipped()
                                .cornerRadius(8)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private var submitButtonSection: some View {
        Section {
            Button("Submit Listing") {
                hideKeyboard()
                validateAndSubmitListing()
            }
            .disabled(isSubmitting || !isFormValid())
        }
    }
    
    private func isFormValid() -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !price.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Double(price) != nil &&
        !listingDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !locationText.isEmpty &&
        !uiImages.isEmpty &&
        selectedCoordinate != nil &&
        !selectedCategory.isEmpty
    }

    private func validateAndSubmitListing() {
        guard isFormValid() else {
            alertMessage = "Please fill all fields and select at least one image and category."
            showAlert = true
            return
        }
        guard Auth.auth().currentUser?.uid != nil else {
            alertMessage = "You must be logged in to create a listing."
            showAlert = true
            return
        }
        
        Task {
            await submitListing()
        }
    }

    private func submitListing() async {
        isSubmitting = true
        guard let coordinate = selectedCoordinate else {
            alertMessage = "No location selected."
            showAlert = true
            isSubmitting = false
            return
        }
        guard let userId = Auth.auth().currentUser?.uid else {
             alertMessage = "User not authenticated."
             showAlert = true
             isSubmitting = false
             return
        }

        do {
            let uploadedImageUrls = try await uploadImages(images: uiImages)
            let aspectRatios = uiImages.map { $0.size.width / $0.size.height }

            let newListingData: [String: Any] = [
                "title": title,
                "price": Double(price) ?? 0,
                "description": listingDescription,
                "locationName": locationText,
                "latitude": coordinate.latitude,
                "longitude": coordinate.longitude,
                "imageUrls": uploadedImageUrls,
                "imageAspectRatios": aspectRatios,
                "sellerId": userId,
                "category": selectedCategory,
                "timestamp": Timestamp(date: Date())
            ]

            try await db.collection("listings").addDocument(data: newListingData)
            alertMessage = "Listing submitted successfully!"
            showAlert = true
            resetForm()
        } catch {
            alertMessage = "Error submitting listing: \(error.localizedDescription)"
            showAlert = true
        }
        isSubmitting = false
    }
    
    private func uploadImages(images: [UIImage]) async throws -> [String] {
        var uploadedUrls: [String] = []
        for image in images {
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                throw NSError(domain: "CreateListingView", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to get image data."])
            }
            
            let imageRef = storage.child("listing_images/\(UUID().uuidString).jpg")
            
            try await imageRef.putDataAsync(imageData)
            let downloadURL = try await imageRef.downloadURL()
            uploadedUrls.append(downloadURL.absoluteString)
        }
        return uploadedUrls
    }

    private func resetForm() {
        title = ""
        price = ""
        listingDescription = ""
        locationText = ""
        selectedCoordinate = nil
        selectedPhotoItems = []
        uiImages = []
        selectedCategory = ""
    }

    private func hideKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}
