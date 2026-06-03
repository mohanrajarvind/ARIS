import SwiftUI

struct RootPagerView: View {
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(isActive: selectedTab == 0)
                .tag(0)

            ContentView(isActive: selectedTab == 1)
                .tag(1)

            MapsView(isActive: selectedTab == 2)
                .tag(2)

            SettingsView()
                .tag(3)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .ignoresSafeArea()
    }
}
