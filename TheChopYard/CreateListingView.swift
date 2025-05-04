//
//  CreateListingView.swift
//  TheChopYard
//
//  Created by Joseph Griffiths on 5/3/25.
//

import SwiftUI

struct CreateListingView: View {
    @State private var title = ""
    @State private var price = ""
    @State private var location = ""
    @State private var images: [UIImage] = []

    var body: some View {
        Form {
            TextField("Title", text: $title)
            TextField("Price", text: $price)
            TextField("Location", text: $location)
            
            // Image picker implementation goes here for adding images
            
            Button("Submit") {
                // Handle Firebase upload logic here
            }
        }
    }
}
