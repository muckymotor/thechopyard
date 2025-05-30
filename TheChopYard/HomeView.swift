import SwiftUI

struct HomeView: View {
    var body: some View {
        TabView {
            HomeFeedView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            MessagesView()
                .tabItem {
                    Label("Messages", systemImage: "bubble.left.and.bubble.right")
                }

            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }

            if #available(iOS 16.0, *) {
                CreateListingView()
                    .tabItem {
                        Label("Listing", systemImage: "plus")
                    }
            } else {
                // Fallback on earlier versions
            }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
    }
}
