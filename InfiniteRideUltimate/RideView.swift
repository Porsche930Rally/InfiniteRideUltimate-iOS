import SwiftUI
import MapKit

struct RouteMap: View {
    @EnvironmentObject var location: LocationService
    let route: [Coordinate]
    let peers: [NearbyPeer]
    var compact = false
    var topographic = false
    var northUp = false
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            if route.count > 1 {
                MapPolyline(coordinates: route.map(\.cl)).stroke(IRTheme.cyan, lineWidth: compact ? 4 : 6)
                Annotation("Finish", coordinate: route.last!.cl) {
                    Image(systemName: "flag.checkered.circle.fill").font(.title2).foregroundStyle(IRTheme.lime)
                }
            }
            ForEach(peers.filter { $0.coordinate != nil }) { peer in
                Annotation(peer.name, coordinate: peer.coordinate!.cl) {
                    VStack(spacing: 2) {
                        ZStack {
                            Circle().fill(IRTheme.lime).frame(width: 24, height: 24)
                            Image(systemName: "figure.outdoor.cycle").font(.caption2.bold()).foregroundStyle(.black)
                        }
                        Text(peerLabel(peer)).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.black.opacity(.82), in: Capsule()).foregroundStyle(.white)
                    }
                }
            }
        }
        .mapStyle(topographic ? .standard(elevation: .realistic, emphasis: .muted) : .standard(elevation: .realistic))
        .mapControls { if !compact { MapCompass(); MapScaleView(); MapUserLocationButton(); MapPitchToggle() } }
        .onAppear { recenter() }
        .onChange(of: northUp) { _, _ in recenter() }
    }

    private func recenter() {
        if let loc = location.location {
            let heading = northUp ? 0 : (location.heading?.trueHeading ?? max(0, loc.course))
            position = .camera(MapCamera(centerCoordinate: loc.coordinate, distance: compact ? 4800 : 1600, heading: heading, pitch: topographic ? 18 : 58))
        } else if !route.isEmpty { position = .rect(routeRect(route)) }
    }
    private func peerLabel(_ peer: NearbyPeer) -> String {
        guard let here = location.location, let c = peer.coordinate else { return peer.name }
        let meters = here.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
        return "\(peer.name) • \(Int(meters)) m"
    }
    private func routeRect(_ route: [Coordinate]) -> MKMapRect {
        route.reduce(MKMapRect.null) { rect, c in let p = MKMapPoint(c.cl); return rect.union(MKMapRect(x: p.x, y: p.y, width: 1, height: 1)) }
    }
}

struct RiderRadar: View {
    @EnvironmentObject var location: LocationService
    let peers: [NearbyPeer]
    var large = false
    var body: some View {
        GeometryReader { geo in
            let radius = min(geo.size.width, geo.size.height) * 0.43
            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(Color(red: 0.004, green: 0.025, blue: 0.04))
                ForEach(1...4, id: \.self) { ring in
                    Circle().stroke(IRTheme.cyan.opacity(.32), lineWidth: 1)
                        .frame(width: radius * 2 * CGFloat(ring) / 4, height: radius * 2 * CGFloat(ring) / 4)
                }
                Rectangle().fill(IRTheme.cyan.opacity(.25)).frame(width: radius * 2, height: 1)
                Rectangle().fill(IRTheme.cyan.opacity(.25)).frame(width: 1, height: radius * 2)
                Image(systemName: "location.north.fill").foregroundStyle(IRTheme.lime).font(.title2.bold())
                ForEach(Array(peers.enumerated()), id: \.offset) { index, peer in
                    let point = radarPoint(peer, radius: radius)
                    VStack(spacing: 1) {
                        Circle().fill(IRTheme.orange).frame(width: 11, height: 11)
                        Text(shortName(peer.name)).font(.system(size: 9, weight: .bold))
                        Text(distanceText(peer)).font(.system(size: 8, weight: .bold)).foregroundStyle(IRTheme.cyan)
                    }.offset(x: point.x, y: point.y + CGFloat(index % 2) * 8)
                }
                VStack { HStack { Text("RIDER RADAR").font(.caption.bold()).foregroundStyle(IRTheme.cyan); Spacer(); Text("\(peers.count) LIVE").font(.caption2.bold()).foregroundStyle(IRTheme.lime) }; Spacer() }.padding(14)
            }
        }.frame(height: large ? 390 : 230)
    }
    private func radarPoint(_ peer: NearbyPeer, radius: CGFloat) -> CGPoint {
        guard let here = location.location, let c = peer.coordinate else {
            let angle = Double(abs(peer.id.hashValue % 360)) * .pi / 180
            return .init(x: sin(angle) * Double(radius * 0.65), y: -cos(angle) * Double(radius * 0.65))
        }
        let distance = min(100, here.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)))
        let heading = location.heading?.trueHeading ?? max(0, here.course)
        let relative = (bearing(here.coordinate, c.cl) - heading) * .pi / 180
        let r = max(Double(radius * 0.15), distance / 100 * Double(radius * 0.88))
        return .init(x: sin(relative) * r, y: -cos(relative) * r)
    }
    private func distanceText(_ peer: NearbyPeer) -> String {
        guard let here = location.location, let c = peer.coordinate else { return "~" }
        return "\(Int(here.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)))) m"
    }
    private func shortName(_ value: String) -> String { value.count > 10 ? String(value.prefix(9)) + "…" : value }
    private func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let p1 = a.latitude * .pi / 180, p2 = b.latitude * .pi / 180, dl = (b.longitude - a.longitude) * .pi / 180
        return atan2(sin(dl) * cos(p2), cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)) * 180 / .pi
    }
}

struct RideView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var bluetooth: BluetoothSensorManager
    @EnvironmentObject var proximity: ProximityRiderService
    @State private var finishPrompt = false, showSensors = false, showTeam = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                header
                Group {
                    switch app.profile.rideDisplayMode {
                    case .performance: VStack(spacing: 9) { speedHero; metricGrid; map(285, false) }
                    case .computer: VStack(spacing: 9) { speedHero; metricGrid; if !app.selectedRoute.isEmpty { map(175, false) } }
                    case .routeRadar: VStack(spacing: 9) { map(330, false); RiderRadar(peers: proximity.peers) }
                    case .topoData: topoAndData
                    case .radarRoute: VStack(spacing: 9) { RiderRadar(peers: proximity.peers, large: true); map(250, false) }
                    }
                }
                if app.rideKind.isRace { raceCard }
                Text(app.formatTime(app.elapsed)).font(.system(size: 31, weight: .bold, design: .monospaced)).foregroundStyle(IRTheme.cyan)
                controls
            }.padding(16)
        }
        .background(IRTheme.background)
        .sheet(isPresented: $showSensors) { SensorSheet() }
        .sheet(isPresented: $showTeam) { TeamDirectorView() }
        .confirmationDialog("Finish this activity?", isPresented: $finishPrompt, titleVisibility: .visible) {
            Button("Finish and save") { app.finish() }
            Button("Discard Activity", role: .destructive) { app.discard() }
            Button("Keep riding", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(app.rideKind.title.uppercased()).font(.caption.weight(.black)).foregroundStyle(app.rideKind.isRace ? IRTheme.orange : IRTheme.cyan)
                Text(app.rideState.rawValue.uppercased()).font(.title2.weight(.black))
                Text(app.profile.rideDisplayMode.title.uppercased()).font(.caption2.bold()).foregroundStyle(IRTheme.muted)
            }
            Spacer()
            Button { cycleLayout() } label: { VStack(spacing: 1) { Text("LAYOUT").font(.caption2.bold()); Text(app.profile.activeRideLayout.title).font(.caption2) } }.buttonStyle(.bordered)
            Button { cycleView() } label: { VStack(spacing: 1) { Image(systemName: "rectangle.3.group"); Text("VIEW").font(.caption2.bold()) } }.buttonStyle(.borderedProminent)
            Button { showSensors = true } label: { Label("\(app.connectedSensors)", systemImage: "sensor.tag.radiowaves.forward.fill") }.buttonStyle(.bordered)
        }
    }

    private var topoAndData: some View {
        VStack(spacing: 9) {
            HStack {
                Text("TOPOGRAPHIC FOLLOWER").font(.caption.bold()).foregroundStyle(IRTheme.cyan)
                Spacer()
                Button(app.profile.topoNorthUp ? "NORTH ↑" : "HEADING ↑") { app.profile.topoNorthUp.toggle(); app.saveProfile() }.buttonStyle(.bordered)
            }
            map(390, true)
            metricGrid
        }
    }
    private var speedHero: some View {
        VStack(spacing: 0) {
            Text("SPEED").font(.caption.weight(.black))
            Text(app.speedDisplay, format: .number.precision(.fractionLength(1))).font(.system(size: 72, weight: .black, design: .rounded))
            Text(app.profile.metric ? "km/h" : "mph").font(.title3.weight(.bold)).foregroundStyle(IRTheme.cyan)
        }
    }
    private var metricGrid: some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 8) {
            ForEach(layoutFields.indices, id: \.self) { index in
                let field = layoutFields[index]
                MetricTile(title: field.0, value: field.1, unit: field.2, color: field.3, symbol: field.4)
            }
        }
    }
    private var layoutFields: [(String, String, String, Color, String)] {
        let hr = ("HEART RATE", app.heartRate > 0 ? "\(app.heartRate)" : "--", "bpm", IRTheme.red, "heart.fill")
        let cad = ("CADENCE", app.cadence > 0 ? "\(app.cadence)" : "--", "rpm", IRTheme.lime, "metronome.fill")
        let pow = ("POWER", app.power > 0 ? "\(app.power)" : "\(app.samples.last?.power ?? 0)", "W", IRTheme.orange, "bolt.fill")
        let dist = ("DISTANCE", String(format: "%.2f", app.distanceDisplay), app.profile.metric ? "km" : "mi", IRTheme.cyan, "road.lanes")
        let time = ("ELAPSED", app.formatTime(app.elapsed), "time", IRTheme.cyan, "clock.fill")
        let avg = ("AVERAGE", String(format: "%.1f", app.elapsed > 0 ? app.distanceMeters / app.elapsed * (app.profile.metric ? 3.6 : 2.236936) : 0), app.profile.metric ? "km/h" : "mph", IRTheme.lime, "speedometer")
        switch app.profile.activeRideLayout {
        case .road: return [hr, cad, pow, dist]
        case .timeTrial: return [pow, avg, hr, time]
        case .training: return [hr, pow, cad, time]
        case .minimal: return [hr, cad, dist, time]
        }
    }
    private var raceCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("RACE RIDER").font(.caption.weight(.black)).foregroundStyle(IRTheme.orange); Spacer(); Text("P\(racePosition.position) / \(racePosition.total)").font(.headline).foregroundStyle(IRTheme.lime) }
                HStack { Text("\(Int(app.remainingMeters)) m remaining"); Spacer(); Text("ROLE • \(app.raceRole.rawValue)") }.font(.caption.weight(.bold))
                Text(String(format: "TEAM SPREAD %.1f m • %@", racePosition.spread, app.message)).font(.headline)
                Button("RIDER / DIRECTOR TEAM BOARD") { showTeam = true }.buttonStyle(.bordered)
            }
        }
    }
    private var controls: some View {
        HStack {
            Button("LAP") { app.addLap() }.buttonStyle(.bordered).frame(maxWidth: .infinity)
            Button(app.rideState == .recording ? "PAUSE" : "START / RESUME") { app.rideState == .ready || app.rideState == .finished ? app.start(.solo) : app.pauseOrResume() }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
            Button("FINISH + SAVE") { finishPrompt = true }.buttonStyle(.bordered).frame(maxWidth: .infinity)
        }
    }
    private func map(_ height: CGFloat, _ topo: Bool) -> some View {
        RouteMap(route: app.selectedRoute, peers: proximity.peers, compact: height < 260, topographic: topo, northUp: app.profile.topoNorthUp)
            .frame(height: height).clipShape(RoundedRectangle(cornerRadius: 18))
    }
    private func cycleView() { app.profile.rideDisplayMode = RideDisplayMode(rawValue: (app.profile.rideDisplayMode.rawValue + 1) % RideDisplayMode.allCases.count)!; app.saveProfile() }
    private func cycleLayout() { app.profile.activeRideLayout = RideLayout(rawValue: (app.profile.activeRideLayout.rawValue + 1) % RideLayout.allCases.count)!; app.saveProfile() }
    private var racePosition: (position: Int, total: Int, spread: Double) {
        proximity.localPosition(location: app.location?.location, heading: app.location?.heading?.trueHeading ?? app.location?.location?.course ?? 0, teamIDs: Set(app.team.filter(\.isTeammate).map(\.id)))
    }
}

struct TeamDirectorView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var proximity: ProximityRiderService
    @Environment(\.dismiss) var dismiss
    @State private var director = false
    var body: some View {
        NavigationStack {
            List {
                Picker("View", selection: $director) { Text("RIDER").tag(false); Text("DIRECTOR").tag(true) }.pickerStyle(.segmented)
                if director {
                    Section("DIRECTOR TEAM BOARD") {
                        HStack {
                            Button("+ ADD SLOT") { app.profile.raceTeamSlots = min(12, app.profile.raceTeamSlots + 1); app.saveProfile() }
                            Spacer()
                            Button(app.profile.raceTeamLocked ? "TEAM LOCKED" : "TEAM OPEN") { app.profile.raceTeamLocked.toggle(); app.saveProfile() }
                                .buttonStyle(.borderedProminent).tint(app.profile.raceTeamLocked ? IRTheme.orange : IRTheme.lime)
                        }
                        ForEach(0..<app.profile.raceTeamSlots, id: \.self) { slot in
                            HStack {
                                Text("SLOT \(slot + 1)").font(.caption.bold()).foregroundStyle(IRTheme.cyan).frame(width: 55, alignment: .leading)
                                if slot < app.team.count {
                                    RiderAvatar(name: app.team[slot].name); Text(app.team[slot].name); Spacer(); Text(app.team[slot].role.rawValue).font(.caption).foregroundStyle(IRTheme.muted)
                                } else {
                                    Menu("ASSIGN CURRENT CONNECTION") { ForEach(proximity.peers) { peer in Button(peer.name) { assign(peer) } } }.font(.caption.bold())
                                }
                            }
                        }
                    }
                }
                Section("CURRENT CONNECTIONS") {
                    Text(proximity.status).font(.caption).foregroundStyle(IRTheme.cyan)
                    if proximity.peers.isEmpty { Text("No riders connected yet.").foregroundStyle(IRTheme.muted) }
                    ForEach(proximity.peers) { peer in
                        HStack { RiderAvatar(name: peer.name); VStack(alignment: .leading) { Text(peer.name).font(.headline); Text("\(peer.heartRate) bpm • \(peer.cadence) rpm • \(peer.power) W").font(.caption) }; Spacer(); Button("TEAM") { assign(peer) } }
                    }
                }
                Section("TEAM ROSTER") {
                    ForEach($app.team) { $rider in
                        VStack(alignment: .leading) {
                            HStack { RiderAvatar(name: rider.name); TextField("Rider name", text: $rider.name) }
                            Toggle("Race teammate", isOn: $rider.isTeammate)
                            Picker("Role", selection: $rider.role) { ForEach(TeamRole.allCases) { Text($0.rawValue).tag($0) } }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(IRTheme.background).navigationTitle(director ? "Race Director" : "Rider Team")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(proximity.active ? "Stop" : "Scan") { proximity.active ? proximity.stop() : proximity.start(name: app.profile.name) } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { app.saveProfile(); dismiss() } }
            }
        }
    }
    private func assign(_ peer: NearbyPeer) {
        if let i = app.team.firstIndex(where: { $0.id == peer.id }) { app.team[i].isTeammate = true }
        else { app.team.append(.init(id: peer.id, name: peer.name, isTeammate: true, role: peer.role)) }
        app.saveProfile()
    }
}

struct RiderAvatar: View {
    let name: String
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [IRTheme.cyan, IRTheme.lime], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(String(name.prefix(1)).uppercased()).font(.caption.bold()).foregroundStyle(.black)
        }.frame(width: 34, height: 34)
    }
}
