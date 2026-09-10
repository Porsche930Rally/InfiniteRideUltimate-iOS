import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct DataView:View{
    @EnvironmentObject var app:AppModel
    @State private var importing=false,error="",shareURL:URL?
    var body:some View{NavigationStack{ScrollView{VStack(alignment:.leading,spacing:12){
        Text("RIDE HISTORY").font(.title.weight(.black));Button{importing=true}{Label("IMPORT FIT / GPX / TCX / CSV",systemImage:"square.and.arrow.down.fill").frame(maxWidth:.infinity)}.buttonStyle(.borderedProminent)
        if !error.isEmpty{Text(error).font(.caption).foregroundStyle(IRTheme.red)}
        if app.rides.isEmpty{ContentUnavailableView("No saved rides",systemImage:"bicycle",description:Text("Record or import an activity to begin analysis."))}
        ForEach(app.rides){ride in GlassCard{VStack(alignment:.leading,spacing:9){HStack{VStack(alignment:.leading){Text(ride.kind.title).font(.headline);Text(ride.startedAt.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(IRTheme.muted)};Spacer();Text(String(format:"%.1f %@",ride.distanceMeters/(app.profile.metric ? 1000:1609.344),app.profile.metric ? "km":"mi")).font(.title3.weight(.bold))};HStack{Label(app.formatTime(ride.duration),systemImage:"clock");Spacer();Label("\(ride.averageHeartRate) bpm",systemImage:"heart.fill");Spacer();Label("\(ride.averageCadence) rpm",systemImage:"metronome")}.font(.caption).foregroundStyle(IRTheme.muted);HStack{Button("ANALYZE"){app.analyze(ride);app.tab = .coach}.buttonStyle(.bordered);Menu("EXPORT"){Button("CSV"){shareURL=try? app.csvURL(for:ride)};Button("GPX"){shareURL=try? app.gpxURL(for:ride)}}.buttonStyle(.bordered);Button("USE ROUTE"){app.selectedRoute=ride.samples.compactMap(\.coordinate);app.selectedRouteName=ride.routeName ?? "Saved ride";app.raceDistanceMeters=ride.distanceMeters;app.message="Route loaded"}.buttonStyle(.bordered)}}}}
    }.padding(16)}.background(IRTheme.background).foregroundStyle(.white).fileImporter(isPresented:$importing,allowedContentTypes:[.data,.xml,.commaSeparatedText],allowsMultipleSelection:true){result in do{for url in try result.get(){try app.importActivity(url)}}catch{self.error=error.localizedDescription}}.sheet(isPresented:Binding(get:{shareURL != nil},set:{if !$0{shareURL=nil}})){if let shareURL{ShareSheet(items:[shareURL])}}}
}}

struct ShareSheet:UIViewControllerRepresentable{
    let items:[Any]
    func makeUIViewController(context:Context)->UIActivityViewController{UIActivityViewController(activityItems:items,applicationActivities:nil)}
    func updateUIViewController(_ uiViewController:UIActivityViewController,context:Context){}
}
