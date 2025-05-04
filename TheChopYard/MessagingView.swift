//
//  MessagingView.swift
//  TheChopYard
//
//  Created by Joseph Griffiths on 5/3/25.
//

import SwiftUI

struct Message: Identifiable {
    var id: String
    var content: String
    var senderId: String
    var timestamp: Date
}

struct MessagingView: View {
    @State private var message = ""
    @State private var messages: [Message] = []

    var body: some View {
        VStack {
            List(messages) { message in
                Text(message.content)
            }

            HStack {
                TextField("Type a message", text: $message)
                Button("Send") {
                    // Send message logic here
                }
            }
            .padding()
        }
        .onAppear {
            // Fetch messages from Firebase Firestore
        }
    }
}

