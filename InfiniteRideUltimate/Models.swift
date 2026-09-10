import Foundation
import CoreLocation

enum AppTab: String, CaseIterable { case home, ride, data, coach, profile }

enum RideKind: String, Codable, CaseIterable, Identifiable {
    case solo, soloTimeTrial, criterium, teamTimeTrial, teamRoadRace
    var id: String { rawValue }
    var title: String {
        switch self {
        case .solo: return "Solo Ride"
        case .soloTimeTrial: return "Solo Time Trial"
        case .criterium: return "Criterium"
        case .teamTimeTrial: return "Team Time Trial"
        case .teamRoadRace: return "Team Road Race"
        }
    }
    var symbol: String {
        switch self {
        case .solo: return "figure.outdoor.cycle"
        case .soloTimeTrial: return "timer"
        case .criterium: return "arrow.triangle.2.circlepath"
        case .teamTimeTrial: return "person.3.sequence"
        case .teamRoadRace: return "flag.checkered"
        }
    }
    var isRace: Bool { self == .criterium || self == .teamTimeTrial || self == .teamRoadRace }
}

enum RideState: String, Codable { case ready, recording, paused, finished }

enum RideDisplayMode: Int, Codable, CaseIterable, Identifiable {
    case performance, computer, routeRadar, topoData, radarRoute
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .performance: return "Performance Dashboard"
        case .computer: return "Cycling Computer"
        case .routeRadar: return "3D Route + Radar"
        case .topoData: return "Topographic Map + Data"
        case .radarRoute: return "Large Radar + 3D Route"
        }
    }
}

enum RideLayout: Int, Codable, CaseIterable, Identifiable {
    case road, timeTrial, training, minimal
    var id: Int { rawValue }
    var title: String { ["Road", "Time Trial", "Training", "Minimal"][rawValue] }
}

enum BikeType: String, Codable, CaseIterable, Identifiable {
    case road = "ROAD", mountain = "MTB", timeTrial = "TT / TRI", hybrid = "HYBRID", gravel = "GRAVEL"
    var id: String { rawValue }
    var title: String { self == .timeTrial ? "TIME TRIAL" : rawValue }
    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

struct Coordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    init(_ coordinate: CLLocationCoordinate2D) { latitude = coordinate.latitude; longitude = coordinate.longitude }
    var cl: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

struct RideSample: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var elapsed: TimeInterval
    var distanceMeters: Double
    var speedMps: Double
    var heartRate: Int
    var cadence: Int
    var power: Int
    var altitudeMeters: Double
    var grade: Double
    var coordinate: Coordinate?
    var powerMeasured: Bool
}

struct RideActivity: Codable, Identifiable {
    var id = UUID()
    var startedAt: Date
    var kind: RideKind
    var duration: TimeInterval
    var distanceMeters: Double
    var samples: [RideSample]
    var routeName: String?
    var averageSpeedMps: Double { duration > 0 ? distanceMeters / duration : 0 }
    var averageHeartRate: Int {
        let values = samples.map(\.heartRate).filter { $0 > 0 }
        return values.isEmpty ? 0 : values.reduce(0,+) / values.count
    }
    var averageCadence: Int {
        let values = samples.map(\.cadence).filter { $0 > 0 }
        return values.isEmpty ? 0 : values.reduce(0,+) / values.count
    }
    var averagePower: Int {
        let values = samples.map(\.power).filter { $0 > 0 }
        return values.isEmpty ? 0 : values.reduce(0,+) / values.count
    }
}

enum PowerCalibrationMode: String, Codable, CaseIterable, Identifiable {
    case off = "Off"
    case automatic = "Automatic"
    case manual = "Manual"
    var id: String { rawValue }
}

struct AthleteProfile: Codable {
    var name = "Mike"
    var age = 26
    var riderKg = 62.6
    var bikeKg = 9.0
    var restingHR = 55
    var maximumHR = 190
    var wheelCircumferenceMM = 2096
    var metric = false
    var manualVO2: Double = 0
    var sprintAlertMeters = 300
    var email = ""
    var rideDisplayMode: RideDisplayMode = .performance
    var activeRideLayout: RideLayout = .road
    var topoNorthUp = false
    var roundedUI = true
    var raceTeamLocked = false
    var raceTeamSlots = 4
    var selectedBikeType: BikeType = .road
    // Optional so profiles saved by 5.5 continue to decode without migration.
    var powerCalibrationMode: PowerCalibrationMode? = .automatic
    var powerCalibrationFactor: Double? = 1.0
    var powerCalibrationOffsetWatts: Int? = 0
    var powerCalibrationSamples: Int? = 0
    var powerCalibrationUpdatedAt: Date? = nil
}

struct SavedRider: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var isTeammate: Bool
    var role: TeamRole
}

enum TeamRole: String, Codable, CaseIterable, Identifiable {
    case captain = "Captain", pull = "Pull Rider", leadout = "Leadout", sprinter = "Sprinter", support = "Support", gc = "GC Leader"
    var id: String { rawValue }
}

struct FitnessResult {
    var vo2: Double
    var ftp: Double
    var shortRangeVO2: Double
    var maxSprint: Double
    var qualifying: Bool
    var summary: String
    static let empty = FitnessResult(vo2: 0, ftp: 0, shortRangeVO2: 0, maxSprint: 0, qualifying: false, summary: "Complete or import a qualifying ride.")
}
