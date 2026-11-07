import SwiftUI

struct OnboardingWelcomeScreen:View {
    let onStart:()->Void
    @State private var page=0
    @ScaledMetric(relativeTo:.body) private var bodySize:CGFloat=17
    @ScaledMetric(relativeTo:.largeTitle) private var heroSize:CGFloat=64
    @ScaledMetric(relativeTo:.title3) private var subtitleSize:CGFloat=14
    @ScaledMetric(relativeTo:.title2) private var buttonSize:CGFloat=19
    private let rose=Color(red:1,green:0.79,blue:0.84)
    private let wine=Color(red:0.43,green:0,blue:0.15)

    var body:some View {
        GeometryReader {proxy in
            ZStack {
                Image("onboarding-silk").resizable().scaledToFill()
                    .frame(width:proxy.size.width,height:proxy.size.height+proxy.safeAreaInsets.top+proxy.safeAreaInsets.bottom)
                    .clipped().ignoresSafeArea()
                    .accessibilityHidden(true)
                TabView(selection:$page) {
                    welcomePage(height:proxy.size.height).tag(0)
                    infoPage(height:proxy.size.height,symbol:"sparkles",title:"TRY IT ON, LIVE",
                             text:"See blush, brows and eyeliner on your face in real time. Pick a shade and strength you like.",
                             pills:["Blush","Brows","Eyeliner"],button:"Next",hint:nil) {withAnimation {page=2}}.tag(1)
                    infoPage(height:proxy.size.height,symbol:"camera",title:"LEARN IT, STEP BY STEP",
                             text:"Follow the guided tutorial on your own face, then take a photo of your look. Photos stay on your phone.",
                             pills:[],button:"Start Try On",hint:nil,action:onStart).tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode:.never))
            }
            .frame(width:proxy.size.width,height:proxy.size.height)
            .overlay(alignment:.bottom) {
                HStack(spacing:12) {
                    // Three pages: welcome, try it on, tutorial. These are progress, not tabs.
                    ForEach(0..<3) {index in
                        Circle().fill(index==page ? Color(red:1,green:0.87,blue:0.88):Color(red:0.48,green:0.06,blue:0.23))
                            .frame(width:8,height:8)
                    }
                }
                .accessibilityElement(children:.ignore)
                .accessibilityLabel("Step \(page+1) of 3")
                .padding(.bottom,max(proxy.size.height*0.045,16))
            }
            .overlay(alignment:.topTrailing) {
                if page>0 {
                    Button("Skip",action:onStart)
                        .font(.system(size:subtitleSize,weight:.medium)).foregroundStyle(rose)
                        .padding(.horizontal,24).padding(.top,12)
                }
            }
        }
        .background(wine.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func page(height:CGFloat,@ViewBuilder content:()->some View) -> some View {
        ScrollView(.vertical,showsIndicators:false) {
            VStack(spacing:0,content:content)
                .padding(.horizontal,32)
                .frame(minHeight:max(height-60,0))
                .frame(maxWidth:560)
                .frame(maxWidth:.infinity)
        }
    }

    private func welcomePage(height:CGFloat) -> some View {
        page(height:height) {
            Spacer(minLength:height*0.22)
            branding
            Spacer(minLength:height*0.10)
            Text("EVERY FACE,\nITS OWN WAY")
                .font(.system(size:subtitleSize,weight:.medium))
                .tracking(5).lineSpacing(10)
                .multilineTextAlignment(.center).foregroundStyle(rose)
                .fixedSize(horizontal:false,vertical:true)
            Spacer(minLength:height*0.065)
            pillButton("Get Started",hint:"Shows how dandan works") {withAnimation {page=1}}
            Spacer(minLength:height*0.045)
        }
    }

    private func infoPage(height:CGFloat,symbol:String,title:LocalizedStringKey,text:LocalizedStringKey,pills:[LocalizedStringKey],button:LocalizedStringKey,hint:LocalizedStringKey?,action:@escaping()->Void) -> some View {
        page(height:height) {
            Spacer(minLength:height*0.14)
            Image(systemName:symbol).font(.system(size:heroSize,weight:.light))
                .foregroundStyle(Color(red:1,green:0.88,blue:0.9))
                .shadow(color:.pink,radius:8)
                .accessibilityHidden(true)
            Spacer(minLength:height*0.05)
            Text(title)
                .font(.system(size:subtitleSize,weight:.medium))
                .tracking(5).lineSpacing(9)
                .multilineTextAlignment(.center).foregroundStyle(rose)
                .fixedSize(horizontal:false,vertical:true)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.system(size:bodySize))
                .multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal:false,vertical:true)
                .padding(.top,18)
            if !pills.isEmpty {
                HStack(spacing:10) {
                    ForEach(pills.indices,id:\.self) {index in
                        Text(pills[index]).font(.system(size:subtitleSize,weight:.medium)).foregroundStyle(rose)
                            .padding(.horizontal,16).padding(.vertical,8)
                            .background(wine.opacity(0.5),in:Capsule())
                            .overlay(Capsule().strokeBorder(rose.opacity(0.6),lineWidth:1))
                    }
                }
                .padding(.top,22)
            }
            Spacer(minLength:height*0.065)
            pillButton(button,hint:hint,action:action)
            Spacer(minLength:height*0.045)
        }
    }

    private var branding:some View {
        VStack(spacing:22) {
            Image("logo-burgundy")
                .resizable().scaledToFit()
                .overlay {
                    LinearGradient(stops:[.init(color:.white.opacity(0.65),location:0),.init(color:Color(red:1,green:0.3,blue:0.5).opacity(0.25),location:0.32),.init(color:.clear,location:0.7)],startPoint:.top,endPoint:.bottom)
                        .blendMode(.screen)
                        .mask(Image("logo-burgundy").resizable().scaledToFit())
                }
                .shadow(color:Color(red:0.98,green:0.20,blue:0.45).opacity(0.4),radius:8,y:2)
                .overlay(alignment:.topTrailing) {
                    Image(systemName:"sparkle").font(.system(size:30,weight:.light))
                        .foregroundStyle(Color(red:1,green:0.88,blue:0.9))
                        .shadow(color:.pink,radius:8).offset(x:6,y:-9)
                }
                .accessibilityLabel("dandan")
                .accessibilityAddTraits(.isHeader)
            Text("YOUR PERSONAL\nMAKEUP GUIDE")
                .font(.system(size:subtitleSize,weight:.medium))
                .tracking(5).lineSpacing(9)
                .multilineTextAlignment(.center)
                .foregroundStyle(rose)
                .fixedSize(horizontal:false,vertical:true)
        }
    }

    private func pillButton(_ title:LocalizedStringKey,hint:LocalizedStringKey?,action:@escaping()->Void) -> some View {
        Button(action:action) {
            ZStack(alignment:.trailing) {
                Text(title)
                    .font(.system(size:buttonSize,weight:.bold))
                    .foregroundStyle(wine)
                    .frame(maxWidth:.infinity)
                    .padding(.horizontal,52)
                Image(systemName:"arrow.right")
                    .font(.system(size:21,weight:.medium))
                    .foregroundStyle(.white)
                    .frame(width:42,height:42)
                    .background(LinearGradient(colors:[Color(red:0.83,green:0.04,blue:0.30),wine],startPoint:.topLeading,endPoint:.bottomTrailing),in:Circle())
                    .overlay(Circle().stroke(.white.opacity(0.35),lineWidth:1))
                    .shadow(color:wine.opacity(0.4),radius:4,y:3)
                    .padding(.trailing,12)
                    .accessibilityHidden(true)
            }
            .frame(minHeight:64)
            .padding(.vertical,2)
            .background(LinearGradient(colors:[Color(red:1,green:0.79,blue:0.80),Color(red:1,green:0.89,blue:0.89),Color(red:1,green:0.78,blue:0.82)],startPoint:.topLeading,endPoint:.bottomTrailing),in:Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.8),lineWidth:1.5))
            .overlay(Capsule().stroke(Color(red:0.98,green:0.32,blue:0.51).opacity(0.6),lineWidth:3).padding(-3))
            .shadow(color:Color(red:1,green:0.34,blue:0.53).opacity(0.8),radius:12,y:2)
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint.map {Text($0)} ?? Text(verbatim:""))
    }
}

