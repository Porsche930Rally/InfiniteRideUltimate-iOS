import SwiftUI

struct RootView: View {
    @EnvironmentObject var app:AppModel
    var body: some View {
        ZStack(alignment:.bottom){IRTheme.background.ignoresSafeArea();Group{switch app.tab{case .home:HomeView();case .ride:RideView();case .data:DataView();case .coach:CoachView();case .profile:ProfileView()}}.padding(.bottom,62);BottomBar()}
        .foregroundStyle(.white).tint(IRTheme.lime)
    }
}

private struct BottomBar:View{
    @EnvironmentObject var app:AppModel
    var body:some View{HStack{ForEach(AppTab.allCases,id:\.self){item in Button(action:{app.tab=item}){VStack(spacing:4){Image(systemName:symbol(item)).font(.system(size:18));Text(item.rawValue.capitalized).font(.caption2.weight(.semibold))}.foregroundStyle(app.tab==item ? IRTheme.lime:Color.white.opacity(0.62)).frame(maxWidth:.infinity)}}}.padding(.top,9).padding(.bottom,7).background(.ultraThinMaterial).overlay(alignment:.top){Rectangle().fill(IRTheme.line).frame(height:1)}}
    private func symbol(_ item:AppTab)->String{switch item{case .home:return "house.fill";case .ride:return "figure.outdoor.cycle";case .data:return "chart.bar.fill";case .coach:return "trophy.fill";case .profile:return "person.fill"}}
}
