import Foundation
import CoreLocation

final class AppModel: ObservableObject {
    @Published var tab: AppTab = .home
    @Published var rideState: RideState = .ready
    @Published var rideKind: RideKind = .solo
    @Published var profile = AthleteProfile()
    @Published var rides: [RideActivity] = []
    @Published var samples: [RideSample] = []
    @Published var elapsed: TimeInterval = 0
    @Published var distanceMeters = 0.0
    @Published var selectedRoute: [Coordinate] = []
    @Published var selectedRouteName = ""
    @Published var fitness: FitnessResult = .empty
    @Published var team: [SavedRider] = []
    @Published var raceRole: TeamRole = .captain
    @Published var raceDistanceMeters = 40_000.0
    @Published var message = "Ready"

    weak var bluetooth: BluetoothSensorManager?
    weak var location: LocationService?
    weak var proximity: ProximityRiderService?
    private var timer: Timer?
    private var startedAt = Date()
    private var activeSeconds: TimeInterval = 0
    private var lastTick = Date()
    private var lastLocation: CLLocation?

    init() { load() }

    func attach(bluetooth: BluetoothSensorManager, location: LocationService, proximity: ProximityRiderService) {
        self.bluetooth = bluetooth; self.location = location; self.proximity = proximity
        bluetooth.wheelCircumferenceMeters = Double(profile.wheelCircumferenceMM) / 1000
    }

    var currentSpeedMps: Double {
        let wheel = bluetooth?.wheelSpeedMps ?? 0
        if wheel > 0.2 { return wheel }
        return max(0, location?.location?.speed ?? 0)
    }
    var heartRate: Int { bluetooth?.heartRate ?? 0 }
    var cadence: Int { bluetooth?.cadence ?? 0 }
    var power: Int { bluetooth?.power ?? 0 }
    var remainingMeters: Double { max(0, raceDistanceMeters - distanceMeters) }
    var speedDisplay: Double { currentSpeedMps * (profile.metric ? 3.6 : 2.236936) }
    var distanceDisplay: Double { distanceMeters / (profile.metric ? 1000 : 1609.344) }
    var connectedSensors: Int { bluetooth?.devices.filter(\.connected).count ?? 0 }

    func start(_ kind: RideKind) {
        if rideState == .finished || rideState == .ready {
            samples = []; elapsed = 0; distanceMeters = 0; activeSeconds = 0; lastLocation = nil; startedAt = Date()
        }
        rideKind = kind; rideState = .recording; lastTick = Date(); location?.start();if kind.isRace{proximity?.start(name:profile.name)};scheduleTimer(); tab = .ride
        message = "\(kind.title) recording"
    }

    func pauseOrResume() {
        if rideState == .recording { rideState = .paused; timer?.invalidate(); timer = nil; message = "Ride paused" }
        else if rideState == .paused { rideState = .recording; lastTick = Date(); scheduleTimer(); message = "Ride resumed" }
    }

    func finish() {
        guard rideState == .recording || rideState == .paused else { return }
        timer?.invalidate(); timer = nil; rideState = .finished; location?.stop();proximity?.stop()
        let activity = RideActivity(startedAt: startedAt, kind: rideKind, duration: elapsed, distanceMeters: distanceMeters, samples: samples, routeName: selectedRouteName.isEmpty ? nil : selectedRouteName)
        if elapsed >= 5 { rides.insert(activity, at: 0); fitness = FitnessEngine.analyze(activity, profile: profile); save() }
        message = elapsed >= 5 ? "Ride saved and analyzed" : "Ride too short to save"
    }

    func discard() {
        timer?.invalidate(); timer = nil; rideState = .ready; samples = []; elapsed = 0; distanceMeters = 0; location?.stop();proximity?.stop(); message = "Activity discarded"; tab = .home
    }

    func addLap() { message = "Lap marker • \(formatTime(elapsed))" }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.capture() }
    }

    private func capture() {
        guard rideState == .recording else { return }
        let now = Date(), dt = min(2, max(0.2, now.timeIntervalSince(lastTick))); lastTick = now; activeSeconds += dt; elapsed = activeSeconds
        let loc = location?.location
        var increment = currentSpeedMps * dt
        if let loc, let previous = lastLocation, loc.timestamp.timeIntervalSince(previous.timestamp) > 0 { increment = min(100, max(0, loc.distance(from: previous))) }
        if let loc { lastLocation = loc }
        distanceMeters += increment
        let altitude = loc?.altitude ?? 0
        let prior = samples.last
        let grade: Double
        if let prior, increment > 2 { grade = min(0.25, max(-0.25, (altitude - prior.altitudeMeters) / increment)) } else { grade = 0 }
        samples.append(RideSample(date: now, elapsed: elapsed, distanceMeters: distanceMeters, speedMps: currentSpeedMps, heartRate: heartRate, cadence: cadence, power: power > 0 ? power : modeledPower(speed: currentSpeedMps, grade: grade), altitudeMeters: altitude, grade: grade, coordinate: loc.map { Coordinate($0.coordinate) }, powerMeasured: power > 0))
        if rideKind.isRace{proximity?.update(name:profile.name,role:raceRole,heart:heartRate,cadence:cadence,power:power,speed:currentSpeedMps,location:loc)}
        if rideKind.isRace && remainingMeters <= Double(profile.sprintAlertMeters) && remainingMeters > 0 { message = "SPRINT • \(Int(remainingMeters)) m to finish" }
    }

    private func modeledPower(speed: Double, grade: Double) -> Int {
        guard speed > 1 else { return 0 }
        let mass = profile.riderKg + profile.bikeKg, gravity = 9.80665
        let rolling = 0.0045 * mass * gravity * speed
        let climbing = mass * gravity * grade * speed
        let aero = 0.5 * 1.225 * 0.26 * pow(speed, 3)
        return max(0, Int((rolling + climbing + aero).rounded()))
    }

    func analyze(_ ride: RideActivity) { fitness = FitnessEngine.analyze(ride, profile: profile) }

    func importActivity(_ url: URL) throws {
        let imported = try ActivityImporter.load(url)
        rides.insert(imported, at: 0); selectedRoute = imported.samples.compactMap(\.coordinate); selectedRouteName = imported.routeName ?? url.deletingPathExtension().lastPathComponent
        if imported.distanceMeters > 500 { raceDistanceMeters = imported.distanceMeters }
        fitness = FitnessEngine.analyze(imported, profile: profile); save(); message = "Imported, analyzed and route saved"
    }

    func csvURL(for ride: RideActivity) throws -> URL { try ActivityExporter.csv(ride) }
    func gpxURL(for ride: RideActivity) throws -> URL { try ActivityExporter.gpx(ride) }

    func saveProfile() { bluetooth?.wheelCircumferenceMeters = Double(profile.wheelCircumferenceMM) / 1000; save() }

    private func save() {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(rides) { try? data.write(to: storage("rides.json"), options: .atomic) }
        if let data = try? encoder.encode(profile) { try? data.write(to: storage("profile.json"), options: .atomic) }
        if let data = try? encoder.encode(team) { try? data.write(to: storage("team.json"), options: .atomic) }
    }

    private func load() {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: storage("rides.json")), let value = try? decoder.decode([RideActivity].self, from: data) { rides = value }
        if let data = try? Data(contentsOf: storage("profile.json")), let value = try? decoder.decode(AthleteProfile.self, from: data) { profile = value }
        if let data = try? Data(contentsOf: storage("team.json")), let value = try? decoder.decode([SavedRider].self, from: data) { team = value }
        if let latest = rides.first { fitness = FitnessEngine.analyze(latest, profile: profile) }
    }

    private func storage(_ name: String) -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent(name)
    }

    func formatTime(_ seconds: TimeInterval) -> String { String(format: "%02d:%02d:%02d", Int(seconds)/3600, Int(seconds)/60%60, Int(seconds)%60) }
}
