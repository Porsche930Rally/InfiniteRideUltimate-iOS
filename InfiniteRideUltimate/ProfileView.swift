import SwiftUI

struct ProfileView:View{
    @EnvironmentObject var app:AppModel
    var body:some View{NavigationStack{Form{Section{VStack(spacing:8){Image(systemName:"person.crop.circle.fill").font(.system(size:92)).foregroundStyle(IRTheme.cyan);Text(app.profile.name).font(.title.weight(.bold));Text("More roads. A better you.").foregroundStyle(IRTheme.muted)}.frame(maxWidth:.infinity)}.listRowBackground(IRTheme.background)
        Section("Athlete"){TextField("Name",text:$app.profile.name);TextField("Backup email",text:$app.profile.email).keyboardType(.emailAddress).textInputAutocapitalization(.never);Stepper("Age  \(app.profile.age)",value:$app.profile.age,in:13...100);LabeledContent("Rider kg"){TextField("kg",value:$app.profile.riderKg,format:.number).keyboardType(.decimalPad)};LabeledContent("Resting HR"){TextField("bpm",value:$app.profile.restingHR,format:.number).keyboardType(.numberPad)};LabeledContent("Maximum HR"){TextField("bpm",value:$app.profile.maximumHR,format:.number).keyboardType(.numberPad)}}
        Section("Bike showroom"){BikeShowroomView(selection:$app.profile.selectedBikeType).frame(height:220);LabeledContent("Bike kg"){TextField("kg",value:$app.profile.bikeKg,format:.number).keyboardType(.decimalPad)};LabeledContent("Wheel circumference"){TextField("mm",value:$app.profile.wheelCircumferenceMM,format:.number).keyboardType(.numberPad)}}
        Section("Race"){Picker("Your role",selection:$app.raceRole){ForEach(TeamRole.allCases){Text($0.rawValue).tag($0)}};Stepper("Sprint alert  \(app.profile.sprintAlertMeters) m",value:$app.profile.sprintAlertMeters,in:50...3000,step:50);Stepper("Director team slots  \(app.profile.raceTeamSlots)",value:$app.profile.raceTeamSlots,in:1...12)}
        Section("Display"){Toggle("Metric units",isOn:$app.profile.metric);Toggle("Rounded interface",isOn:$app.profile.roundedUI);Picker("Default ride view",selection:$app.profile.rideDisplayMode){ForEach(RideDisplayMode.allCases){Text($0.title).tag($0)}};Picker("Data layout",selection:$app.profile.activeRideLayout){ForEach(RideLayout.allCases){Text($0.title).tag($0)}};Toggle("Topographic map north-up",isOn:$app.profile.topoNorthUp)}
        Section{Button("SAVE PROFILE"){app.saveProfile()}.frame(maxWidth:.infinity)}
        Section{Text("InfiniteRide Ultimate iOS 5.5\nINfiniteBoost45").font(.caption).foregroundStyle(IRTheme.muted)}}.scrollContentBackground(.hidden).background(IRTheme.background).navigationTitle("Profile")}}
}

struct BikeShowroomView: View {
    @Binding var selection: BikeType
    @State private var dragX: CGFloat = 0
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 23).fill(Color(red:0.004,green:0.024,blue:0.035))
                bike(at: selection.index - 1, width: geo.size.width, height: geo.size.height).scaleEffect(.72).opacity(.35).offset(x:-geo.size.width * 0.35)
                bike(at: selection.index + 1, width: geo.size.width, height: geo.size.height).scaleEffect(.72).opacity(.35).offset(x:geo.size.width * 0.35)
                bike(at: selection.index, width: geo.size.width, height: geo.size.height).scaleEffect(1 + min(0.04,abs(dragX)/200))
                VStack { Spacer(); HStack { Button("‹"){move(-1)}.font(.largeTitle.bold()); Spacer(); VStack(spacing:5){Text(selection.title).font(.headline.bold());HStack(spacing:7){ForEach(BikeType.allCases){type in Circle().fill(type==selection ? IRTheme.lime:IRTheme.muted).frame(width:type==selection ? 7:5,height:type==selection ? 7:5)}}}; Spacer(); Button("›"){move(1)}.font(.largeTitle.bold()) }.padding(.horizontal,14).padding(.bottom,7) }
                RoundedRectangle(cornerRadius:23).stroke(IRTheme.cyan.opacity(.7),lineWidth:1.5)
            }.contentShape(Rectangle()).gesture(DragGesture().onChanged{dragX=$0.translation.width}.onEnded{value in if abs(value.translation.width)>30{move(value.translation.width<0 ? 1:-1)};dragX=0})
        }
    }
    private func bike(at raw:Int,width:CGFloat,height:CGFloat)->some View {
        let count=BikeType.allCases.count,index=(raw%count+count)%count
        return Image("bike_chooser_showroom").resizable().scaledToFill()
            .frame(width:width*count,height:height).offset(x:(CGFloat(count-1)/2-CGFloat(index))*width)
            .frame(width:width,height:height).clipped().allowsHitTesting(false)
    }
    private func move(_ amount:Int){let all=BikeType.allCases,index=(selection.index+amount+all.count)%all.count;withAnimation(.easeOut(duration:.23)){selection=all[index]}}
}

struct TeamView:View{
    @EnvironmentObject var app:AppModel;@EnvironmentObject var proximity:ProximityRiderService;@Environment(\.dismiss) var dismiss
    var body:some View{NavigationStack{List{Section("Nearby InfiniteRide phones"){Text(proximity.status).font(.caption).foregroundStyle(IRTheme.cyan);if proximity.peers.isEmpty{Text("Press Scan on both phones. Keep InfiniteRide open during first discovery.")}ForEach(proximity.peers){peer in VStack(alignment:.leading,spacing:5){Text(peer.name).font(.headline);Text("RSSI \(peer.rssi) • \(peer.heartRate) bpm • \(peer.cadence) rpm • \(peer.power) W").font(.caption);HStack{Button("SAVE FRIEND"){save(peer,false)};Button("JOIN TEAM"){save(peer,true)}}}}Section("Saved friends and team"){ForEach($app.team){$rider in VStack(alignment:.leading){TextField("Rider name",text:$rider.name);Toggle("Race teammate",isOn:$rider.isTeammate);Picker("Role",selection:$rider.role){ForEach(TeamRole.allCases){Text($0.rawValue).tag($0)}}}}}.scrollContentBackground(.hidden).background(IRTheme.background).navigationTitle("Rider Scan").toolbar{ToolbarItem(placement:.topBarLeading){Button(proximity.active ? "Stop":"Scan"){proximity.active ? proximity.stop():proximity.start(name:app.profile.name)}};ToolbarItem(placement:.confirmationAction){Button("Done"){app.saveProfile();dismiss()}}}}}}}
    private func save(_ peer:NearbyPeer,_ teammate:Bool){if let i=app.team.firstIndex(where:{$0.id==peer.id}){app.team[i].isTeammate=teammate}else{app.team.append(SavedRider(id:peer.id,name:peer.name,isTeammate:teammate,role:peer.role))}}
}
