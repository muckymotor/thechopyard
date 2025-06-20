import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct Message: Identifiable, Codable {
    @DocumentID var id: String?
    let text: String
    let senderId: String
    let timestamp: Date
}


@MainActor
struct ChatView: View {
    let chatId: String
    let sellerUsername: String
    @EnvironmentObject var appViewModel: AppViewModel
    @State private var messages: [Message] = []
    @State private var newMessage = ""
    @State private var listener: ListenerRegistration?

    private var db: Firestore { Firestore.firestore() }
    private var currentsellerId: String? { appViewModel.user?.uid }

    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { message in
                            HStack {
                                if message.senderId == currentsellerId {
                                    Spacer()
                                    Text(message.text)
                                        .padding()
                                        .background(Color.blue.opacity(0.2))
                                        .cornerRadius(10)
                                } else {
                                    Text(message.text)
                                        .padding()
                                        .background(Color.gray.opacity(0.2))
                                        .cornerRadius(10)
                                    Spacer()
                                }
                            }
                            .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }

            HStack {
                TextField("Message...", text: $newMessage)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button("Send") {
                    sendMessage()
                }
                .disabled(newMessage.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .navigationTitle(sellerUsername)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            listenToMessages()
            markChatAsRead()
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
    }

    private func listenToMessages() {
        listener?.remove()
        guard let currentsellerId else { return }

        listener = db.collection("chats").document(chatId)
            .collection("messages")
            .order(by: "timestamp")
            .addSnapshotListener { snapshot, error in
                guard let docs = snapshot?.documents else { return }
                self.messages = docs.compactMap { try? $0.data(as: Message.self) }

                // 🟢 Ensure chat is marked read when new messages arrive
                self.markChatAsRead()
            }
    }


    private func sendMessage() {
        guard let currentsellerId else { return }

        let message = Message(id: nil, text: newMessage, senderId: currentsellerId, timestamp: Date())
        let messageRef = db.collection("chats").document(chatId).collection("messages").document()
        let chatRef = db.collection("chats").document(chatId)

        do {
            try messageRef.setData(from: message)
            chatRef.updateData([
                "lastMessage": message.text,
                "lastMessageTimestamp": message.timestamp,
                "lastMessageSenderId": currentsellerId,
                "readBy": [currentsellerId] // Reset readBy to only the sender
            ])
            newMessage = ""
        } catch {
            print("Failed to send message: \(error.localizedDescription)")
        }
    }

    private func markChatAsRead() {
        guard let currentsellerId else { return }
        let chatRef = db.collection("chats").document(chatId)
        chatRef.updateData([
            "readBy": FieldValue.arrayUnion([currentsellerId])
        ])
    }
}
