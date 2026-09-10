import SwiftUI

enum IRTheme {
    static let background = Color(red: 0.005, green: 0.012, blue: 0.018)
    static let panel = Color(red: 0.045, green: 0.065, blue: 0.075)
    static let panel2 = Color(red: 0.065, green: 0.085, blue: 0.095)
    static let line = Color(red: 0.18, green: 0.25, blue: 0.28)
    static let cyan = Color(red: 0.24, green: 0.86, blue: 1.0)
    static let lime = Color(red: 0.67, green: 1.0, blue: 0.20)
    static let orange = Color(red: 1.0, green: 0.45, blue: 0.20)
    static let red = Color(red: 1.0, green: 0.30, blue: 0.29)
    static let muted = Color.white.opacity(0.65)
}

struct GlassCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [IRTheme.panel2.opacity(.95),IRTheme.panel.opacity(.88)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(IRTheme.line.opacity(.8),lineWidth:1))
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct PulseLine: Shape {
    var phase: CGFloat
    var animatableData: CGFloat { get { phase } set { phase = newValue } }
    func path(in rect: CGRect) -> Path {
        var p=Path(),x:CGFloat=0;p.move(to:.init(x:0,y:rect.midY))
        while x<=rect.width { let t=(x/rect.width+phase).truncatingRemainder(dividingBy:1);let center:CGFloat=.55;let d=abs(t-center);var y=rect.midY+sin(t*CGFloat.pi*8)*2;if d<.018{y=rect.midY-rect.height*.42}else if d<.035{y=rect.midY+rect.height*.30}else if d<.055{y=rect.midY-rect.height*.12};p.addLine(to:.init(x:x,y:y));x+=2 }
        return p
    }
}

struct HeartMetric: View {
    let heartRate: Int
    @State private var phase: CGFloat = 0
    var body: some View {
        ZStack {
            PulseLine(phase: phase).stroke(IRTheme.red.opacity(.35),style:.init(lineWidth:2,lineCap:.round,lineJoin:.round))
            HStack { Image(systemName:"heart.fill").foregroundStyle(IRTheme.red);Text(heartRate>0 ? "\(heartRate)":"--").font(.system(size:34,weight:.bold,design:.rounded));Text("bpm").foregroundStyle(IRTheme.cyan) }
        }.frame(height:54).onAppear{withAnimation(.linear(duration:2).repeatForever(autoreverses:false)){phase=1}}
    }
}

struct MetricTile: View {
    let title:String,value:String,unit:String,color:Color,symbol:String
    var body:some View{VStack(alignment:.leading,spacing:5){HStack{Image(systemName:symbol).foregroundStyle(color);Text(title).font(.caption2.weight(.bold)).foregroundStyle(IRTheme.muted)};Text(value).font(.system(size:30,weight:.bold,design:.rounded));Text(unit).font(.caption.weight(.bold)).foregroundStyle(color)}.padding(14).frame(maxWidth:.infinity,minHeight:108,alignment:.leading).background(IRTheme.panel).overlay(RoundedRectangle(cornerRadius:16).stroke(IRTheme.line)).clipShape(RoundedRectangle(cornerRadius:16))}
}
