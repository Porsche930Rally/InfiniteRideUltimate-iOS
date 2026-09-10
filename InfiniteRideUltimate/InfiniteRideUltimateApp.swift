import SwiftUI

@main
struct InfiniteRideUltimateApp: App {
    @StateObject private var app = AppModel()
    @StateObject private var bluetooth = BluetoothSensorManager()
    @StateObject private var location = LocationService()
    @StateObject private var proximity = ProximityRiderService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(bluetooth)
                .environmentObject(location)
                .environmentObject(proximity)
                .preferredColorScheme(.dark)
                .task { app.attach(bluetooth: bluetooth, location: location, proximity: proximity) }
        }
    }
}
