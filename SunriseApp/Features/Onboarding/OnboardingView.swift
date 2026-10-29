import SwiftUI

// -Nimah: Launch scan owns all classification and makeup fitting; try-on never repeats it.
struct OnboardingView: View {
    private enum Step { case welcome, faceScan, eyeScan, preparing }
    @ObservedObject var store: FaceShapeStore
    var onFinish: () -> Void
    var onCancel:(()->Void)?
    // -Nimah: Retake results are staged until fitting and both analyses succeed.
    @StateObject private var draft=FaceShapeStore()
    @State private var step:Step
    @State private var started=false
    @StateObject private var preparation=LaunchFitPreparation()
    @State private var preparationFailed=false

    // -Nimah: Repeat analysis on launch, with welcome shown only on the first launch.
    init(store:FaceShapeStore,showWelcome:Bool = true,onCancel:(()->Void)? = nil,onFinish:@escaping ()->Void) {
        self.store=store;self.onFinish=onFinish;self.onCancel=onCancel;_step=State(initialValue:showWelcome ? .welcome : .faceScan)
    }
    var body: some View {
        NavigationStack {
            switch step {
            case .welcome:welcome
            case .faceScan:
                FaceAnalysis.scanScreen(store:draft,continueTitle:"Next: scan your eyes",onScanFrame:{ frame,face in
                    // -Nimah: Compute brow/cheek attachments here, while the launch scan is still visible.
                    preparation.submit(FaceLandmarkFrame(frame:frame,anchor:face))
                }) { step = .eyeScan }
            case .eyeScan:
                EyeAnalysis.scanScreen(store:draft,continueTitle:"See my makeup") {
                    step = .preparing
                    Task {
                        guard draft.latest != nil,draft.eyes != nil else { preparationFailed=true;return }
                        let fitted=await preparation.finish()
                        // -Nimah: A neutral eye recommendation is a valid fallback, not a failed face scan.
                        guard fitted,draft.latest != nil,draft.eyes != nil else {
                            preparationFailed=true;return
                        }
                        store.latest=draft.latest;store.eyes=draft.eyes
                        onFinish()
                    }
                }
            case .preparing:ProgressView("Preparing your recommended makeup")
            }
        }
        .toolbar { if let onCancel { ToolbarItem(placement:.cancellationAction) { Button("Cancel",action:onCancel) } } }
        .onAppear { if !started { started=true;preparation.restart() } }
        .alert("Brow fitting unavailable",isPresented:$preparationFailed) {
            Button("Repeat initial scan") { draft.latest=nil;draft.eyes=nil;preparation.restart();step = .faceScan }
        } message: { Text("Brow contours could not be fitted from the initial scan. Your previous saved result is unchanged. Please retry the face scan to prepare your makeup.") }
    }

    private var welcome: some View {
        OnboardingWelcomeScreen {step = .faceScan}
            .toolbar(.hidden,for:.navigationBar)
    }
}

// -Nimah: Native accessible controls over a static silk asset; no camera/model work on welcome.
struct OnboardingWelcomeScreen:View {
    let onStart:()->Void
    @ScaledMetric(relativeTo:.title3) private var subtitleSize:CGFloat=14
    @ScaledMetric(relativeTo:.title2) private var buttonSize:CGFloat=19
    private let rose=Color(red:1,green:0.79,blue:0.84)
    private let wine=Color(red:0.43,green:0,blue:0.15)

    var body:some View {
        GeometryReader {proxy in
            ScrollView(.vertical,showsIndicators:false) {
                VStack(spacing:0) {
                    Spacer(minLength:proxy.size.height*0.22)
                    branding
                    Spacer(minLength:proxy.size.height*0.10)
                    Text("EVERY FACE,\nITS OWN WAY")
                        .font(.system(size:subtitleSize,weight:.medium))
                        .tracking(5).lineSpacing(10)
                        .multilineTextAlignment(.center).foregroundStyle(rose)
                        .fixedSize(horizontal:false,vertical:true)
                    Spacer(minLength:proxy.size.height*0.065)
                    startButton
                    HStack(spacing:12) {
                        // Four stages: welcome, face scan, eye scan, preparation. These are progress, not tabs.
                        ForEach(0..<4) {index in
                            Circle().fill(index==0 ? Color(red:1,green:0.87,blue:0.88):Color(red:0.48,green:0.06,blue:0.23))
                                .frame(width:8,height:8)
                        }
                    }
                    .accessibilityElement(children:.ignore)
                    .accessibilityLabel("Step 1 of 4")
                    .padding(.top,34)
                    Spacer(minLength:proxy.size.height*0.045)
                }
                .padding(.horizontal,32)
                .frame(minHeight:proxy.size.height)
                .frame(maxWidth:560)
                .frame(maxWidth:.infinity)
            }
            .background {
                Image("onboarding-silk").resizable().scaledToFill()
                    .frame(width:proxy.size.width,height:proxy.size.height+proxy.safeAreaInsets.top+proxy.safeAreaInsets.bottom)
                    .clipped().ignoresSafeArea()
                    .accessibilityHidden(true)
            }
        }
        .background(wine.ignoresSafeArea())
        .preferredColorScheme(.dark)
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

    private var startButton:some View {
        Button(action:onStart) {
            ZStack(alignment:.trailing) {
                Text("Get Started")
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
        .accessibilityHint("Begin your face scan, followed by your eye scan")
    }
}

#Preview { OnboardingView(store: FaceShapeStore(), onFinish: {}) }
