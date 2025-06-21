import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                HomeFeedView()
                    .tabItem {
                        Label("Home", systemImage: "house")
                    }
                    .tag(0)

                MessagesView()
                    .tabItem {
                        Label("Messages", systemImage: "bubble.left.and.bubble.right")
                    }
                    .tag(1)

                SearchView()
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .tag(2)

                if #available(iOS 16.0, *) {
                    CreateListingView()
                        .tabItem {
                            Label("Listing", systemImage: "plus")
                        }
                        .tag(3)
                }

                ProfileView()
                    .tabItem {
                        Label("Profile", systemImage: "person.crop.circle")
                    }
                    .tag(4)
            }

            // Notify when Home tab is selected
            .onChange(of: selectedTab) { newValue in
                if newValue == 0 {
                    NotificationCenter.default.post(name: .homeTabSelected, object: nil)
                }
            }

            // Red dot overlay on Messages tab
            if appViewModel.hasUnreadMessages && selectedTab != 1 {
                GeometryReader { geometry in
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .position(x: geometry.size.width * 0.335, y: geometry.size.height - 40)
                        .transition(.scale)
                        .animation(.easeInOut, value: appViewModel.hasUnreadMessages)
                }
                .allowsHitTesting(false)
            }
        }
    }
}
