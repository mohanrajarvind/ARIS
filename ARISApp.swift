import SwiftUI

@main
struct ARISApp: App {
    @StateObject private var ble = BLEManager()
    @StateObject private var location = LocationManager()
    @StateObject private var nav = NavigationManager()

    var body: some Scene {
        WindowGroup {
            RootPagerView()
                .environmentObject(ble)
                .environmentObject(location)
                .environmentObject(nav)
        }
    }
}
