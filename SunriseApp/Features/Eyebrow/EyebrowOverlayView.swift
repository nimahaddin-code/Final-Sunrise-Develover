// -Nimah: Camera-first region → style → tutorial, mengikuti referensi eyebrow/forehead pengguna.
import SwiftUI

struct EyebrowOverlayView:View {
    @StateObject private var model:EyebrowViewModel
    @StateObject private var camera=FaceCameraState()
    @State private var visible=false
    @State private var showOptions=false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    init(checker:any FaceTrackingAvailabilityChecking,assessment:FaceShapeAssessment? = nil,initialRegion:FaceGuideRegion? = nil,initialShade:MakeupShade? = nil,initialIntensity:Double? = nil,startTutorial:Bool = false) { _model=StateObject(wrappedValue:EyebrowViewModel(checker:checker,assessment:assessment,initialRegion:initialRegion,initialShade:initialShade,initialIntensity:initialIntensity,startTutorial:startTutorial)) }
    private var supported:Bool { model.availability == .supported }
    private var lessons:[FaceGuideLesson] { model.lessons }
    var body:some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if supported && camera.authorized && camera.failure==nil {
                LiveGuideView(camera:camera,referenceID:"eyebrows",active:visible && scenePhase == .active,eyebrowConfiguration:model.liveConfiguration)
                    .ignoresSafeArea()
            } else { VStack { fallback.padding(.horizontal,32).padding(.top,100); Spacer() } }
            LinearGradient(colors:[.black.opacity(0.55),.clear,.clear,.black.opacity(0.18)],startPoint:.top,endPoint:.bottom)
                .ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing:14) {
                header
                Spacer(minLength:12)
                if model.phase == .positionFace {
                    faceFrame.frame(maxWidth:300,maxHeight:320).allowsHitTesting(false)
                    Spacer(minLength:8)
                }
                if supported {
                    HStack(spacing:8) {
                        Circle().fill(camera.tracked ? Color.green : Color.orange).frame(width:8,height:8)
                        Text(camera.tracked ? (camera.eyebrowGuideReady ? "Check placement alignment" : "Face detected · mapping") : model.trackingState(camera:camera).rawValue)
                            .font(.caption.weight(.medium))
                    }.foregroundStyle(.white).padding(.horizontal,18).padding(.vertical,12)
                        .background(.ultraThinMaterial,in:Capsule())
                }
                bottomPanel
            }.padding(.horizontal,12).padding(.top,8).padding(.bottom,8)
        }
        .toolbar(.hidden,for:.navigationBar).toolbar(.hidden,for:.tabBar)
        .navigationBarBackButtonHidden().preferredColorScheme(.dark)
        .sheet(isPresented:$showOptions) { options.preferredColorScheme(.light).presentationDetents([.medium,.large]) }
        .task {
            await model.prepare()
            if supported { await camera.requestPermission() }
            else if case .unsupported=model.availability { model.nextAfterScan() }
        }
        .onAppear { visible=true; camera.overlay=true }
        .onDisappear { visible=false; camera.stopSession?(); camera.suspend() }
        .onChange(of:camera.tracked) { _,tracked in if tracked && model.phase == .positionFace { model.nextAfterScan() } }
        .onChange(of:scenePhase) { _,phase in
            if phase != .active { camera.stopSession?(); camera.suspend() }
            else if supported { Task { await camera.requestPermission() } }
        }
    }
    private var header:some View {
        HStack {
            Button { if model.backLeavesStudio { dismiss() } else { model.back() } } label: {
                Image(systemName:model.backLeavesStudio ? "xmark" : "chevron.left")
                    .frame(width:38,height:38).background(.ultraThinMaterial,in:Circle())
            }.accessibilityLabel("Back")
            Spacer()
            Text(model.phase == .tutorial ? model.title : (model.phase == .chooseStyle ? model.configuration.region.title : "GlowGuide"))
                .font(.headline).lineLimit(1)
            Spacer()
            if model.phase == .tutorial {
                Text("\(model.stepIndex+1)/\(lessons.count)").font(.caption.monospacedDigit()).padding(8)
                    .overlay(Capsule().stroke(.white.opacity(0.7)))
            } else {
                Button { showOptions=true } label: {
                    Image(systemName:"slider.horizontal.3").frame(width:38,height:38).background(.ultraThinMaterial,in:Circle())
                }.accessibilityLabel("Guide settings")
            }
        }.foregroundStyle(.white)
    }
    @ViewBuilder private var bottomPanel:some View {
        switch model.phase {
        case .positionFace:
            Text(camera.scanInstruction).multilineTextAlignment(.center).font(.subheadline)
                .foregroundStyle(.white).padding().frame(maxWidth:240).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:22))
        case .tracking:
            panel {
                Text("Eye & brow scan").font(.headline)
                Text(camera.eyebrowGuideReady ? "Eye scan complete. Review the nose–eye mapping before applying makeup." : camera.scanInstruction).font(.subheadline)
                if let distance=camera.distanceHint { Text(distance).font(.caption) }
                Text("Coba posisi awal 25–60 cm; ini panduan posisi, bukan batas pasti perangkat. Pastikan alis tidak tertutup dan cahaya cukup.").font(.caption)
                Button("Scan ulang") { camera.refitFace() }
                action("Continue",disabled:!camera.eyebrowGuideReady) { model.nextAfterScan() }
            }
        case .chooseFaceShape:
            panel { faceShapeChoices }
        case .chooseRegion:
            panel {
                faceShapeChip
                Text("Choose region").font(.headline)
                HStack(spacing:12) {
                    ForEach(FaceGuideRegion.allCases) { region in
                        Button { model.select(region) } label: {
                            VStack(spacing:8) {
                                Image(systemName:region == .eyebrows ? "eyebrow" : (region == .blush ? "circle.lefthalf.filled" : "face.dashed")).font(.title2)
                                    .frame(width:54,height:54).background(Color.pink.opacity(0.10),in:Circle())
                                Text(region.title).font(.subheadline.weight(.semibold))
                            }.frame(maxWidth:.infinity).padding(.vertical,8)
                        }.foregroundStyle(AppColors.rose)
                    }
                }
            }
        case .chooseStyle:
            panel {
                HStack { Text("Your recommendation").font(.headline); Spacer(); Button("Region") { model.phase = .chooseRegion }.font(.caption) }
                faceShapeChip
                if model.configuration.region == .eyebrows || model.configuration.region == .blush {
                    referenceChoices
                } else {
                    Picker("Forehead makeup",selection:Binding(get:{ model.configuration.foreheadStyle.category },set:{ category in
                        model.configuration.foreheadStyle=category == .contour ? .hairline : .centerHighlight
                    })) {
                        ForEach(ForeheadCategory.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    ScrollView(.horizontal,showsIndicators:false) {
                        HStack(spacing:10) {
                            ForEach(ForeheadStyle.allCases.filter { $0.category==model.configuration.foreheadStyle.category }) { style in
                                styleCard(title:style.title,selected:model.configuration.foreheadStyle==style,brow:nil,forehead:style) { model.configuration.foreheadStyle=style }
                            }
                        }
                    }
                    HStack { Text("Top limit").font(.caption); Slider(value:$model.configuration.foreheadHeight,in:0.45...1).tint(AppColors.rose) }
                    Text("Keep the outline within visible skin. Hairline is not detected automatically.").font(.caption).foregroundStyle(.secondary)
                }
                previewControls
                if supported { Button("Refresh placement") { model.restorePreview(); camera.refitFace() }.font(.caption) }
                if supported && !camera.eyebrowGuideReady { Text("Aligning makeup automatically · keep your face visible").font(.caption).foregroundStyle(.secondary) }
            }
        case .tutorial:
            panel {
                previewControls
                if supported { Button("Refresh placement") { model.restorePreview(); camera.refitFace() }.font(.caption) }
                HStack(alignment:.top,spacing:16) {
                    VStack(alignment:.leading,spacing:6) {
                        Text("Step \(model.stepIndex+1) · \(lessons[model.stepIndex].title)").font(.headline)
                        Text(lessons[model.stepIndex].instruction).font(.subheadline)
                    }
                    Button { model.nextStep() } label: {
                        HStack { Text(model.stepIndex+1==lessons.count ? "Done" : "Next"); Image(systemName:"chevron.right") }
                            .font(.subheadline.weight(.semibold)).padding(.horizontal,16).padding(.vertical,16)
                            .background(AppColors.rose,in:RoundedRectangle(cornerRadius:12)).foregroundStyle(.white)
                    }
                }
                HStack {
                    Button("Previous") { model.previousStep() }
                    Spacer()
                    Button(model.configuration.showGuide ? "Hide guide" : "Show guide") { model.configuration.showGuide.toggle() }
                    Button { showOptions=true } label: { Image(systemName:"slider.horizontal.3") }.accessibilityLabel("Guide settings")
                }.font(.caption)
            }
        }
    }
    // -Nimah: Both modes use the same live camera; no captured photo or fabricated result.
    private var previewControls:some View {
        VStack(alignment:.leading,spacing:8) {
            Picker("Live comparison",selection:$model.configuration.previewAfter) {
                Text("Before").tag(false)
                Text("After").tag(true)
            }.pickerStyle(.segmented)
            Text(model.configuration.previewAfter ? "Live makeup simulation" : "Original live camera · no guide or effect")
                .font(.caption).foregroundStyle(.secondary)
            if model.configuration.previewAfter {
                HStack {
                    Text("Intensity").font(.caption)
                    Slider(value:$model.configuration.previewIntensity,in:0...1).tint(AppColors.rose)
                }
                Toggle("Placement guide",isOn:$model.configuration.showGuide).font(.caption)
                if model.configuration.region == .eyebrows {
                    Toggle("Brow mapping lines",isOn:$model.configuration.showMappingFormula).font(.caption)
                    Text("Shape follows detected brows. Formula lines are reference marks.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func panel<Content:View>(@ViewBuilder content:() -> Content) -> some View {
        VStack(spacing:0) {
            ScrollView {
                VStack(alignment:.leading,spacing:12,content:content).padding(18).frame(maxWidth:.infinity,alignment:.leading)
            }
            if model.phase == .chooseStyle {
                // -Nimah: Tutorial text is available immediately while live placement aligns automatically.
                action(supported ? "Start tutorial" : "Preview steps",disabled:!model.hasRecommendation) { model.beginTutorial() }
                    .padding(.horizontal,18).padding(.bottom,14)
            }
        }.frame(height:panelHeight)
            .background(Color.white.opacity(0.96),in:RoundedRectangle(cornerRadius:24)).foregroundStyle(Color.black)
            .environment(\.colorScheme,.light)
    }
    // -Nimah: Keep camera visible; longer choices and accessibility text can scroll within the card.
    private var panelHeight:CGFloat {
        switch model.phase {
        case .chooseStyle:return 390
        case .tutorial:return 330
        case .chooseFaceShape:return 350
        case .chooseRegion:return 205
        default:return 180
        }
    }
    private var faceShapeChip:some View {
        HStack {
            Text(model.assessment.shape.title).font(.caption.weight(.semibold))
            Text(model.assessment.origin == .manual ? "Selected manually" : "Analysis result").font(.caption2).foregroundStyle(.secondary)
            Spacer()
            // -Nimah: The saved scan determines the shape; no manual replacement in try-on.
        }
    }
    // -Nimah: Missing scan data asks for the existing face-scan flow, not a manual shape picker.
    private var faceShapeChoices:some View {
        Text("Complete your face scan first. If this shape has no reference yet, makeup stays off.")
            .font(.subheadline)
    }
    // -Nimah: Display the assigned result, not a picker of all research references.
    private var referenceChoices:some View {
        VStack(alignment:.leading,spacing:10) {
            if model.configuration.region == .eyebrows,let option=model.selectedBrow {
                FaceGuideStylePreview(brow:option.style,forehead:nil).frame(width:108,height:62)
                Text(option.title).font(.headline)
                Text(model.sourceNote).font(.caption).foregroundStyle(AppColors.rose)
            } else if model.configuration.region == .blush,let option=model.selectedBlush {
                BlushPlacementSketch(style:option.style).frame(width:108,height:82)
                Text(option.title).font(.headline)
                Text(option.style.instruction).font(.caption)
                Text(model.sourceNote).font(.caption).foregroundStyle(AppColors.rose)
            } else {
                Text("No saved recommendation for this face shape").font(.headline)
                Text("Complete your face scan first. If this shape has no reference yet, makeup stays off.").font(.caption)
            }
        }
    }
    private func blushCard(title:String,style:BlushPlacementStyle,selected:Bool,action:@escaping () -> Void) -> some View {
        Button(action:action) {
            VStack(spacing:6) {
                BlushPlacementSketch(style:style).frame(width:96,height:82)
                Text(title).font(.caption).lineLimit(2).frame(width:108,height:32)
            }.padding(5).overlay(RoundedRectangle(cornerRadius:12).stroke(selected ? AppColors.rose : .clear,lineWidth:1.5))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func action(_ title:String,disabled:Bool,action:@escaping () -> Void) -> some View {
        Button(action:action) { Text(title).font(.subheadline.weight(.semibold)).frame(maxWidth:.infinity).padding(13)
            .background(disabled ? Color.gray.opacity(0.3) : AppColors.rose,in:RoundedRectangle(cornerRadius:12)).foregroundStyle(.white) }.disabled(disabled)
    }
    private func styleCard(title:String,selected:Bool,brow:EyebrowStyle?,forehead:ForeheadStyle?,action:@escaping () -> Void) -> some View {
        Button(action:action) {
            VStack(spacing:7) {
                FaceGuideStylePreview(brow:brow,forehead:forehead).frame(width:82,height:58)
                    .background(Color(red:0.97,green:0.91,blue:0.90),in:RoundedRectangle(cornerRadius:10))
                Text(title).font(.caption).lineLimit(1)
            }.padding(5).overlay(RoundedRectangle(cornerRadius:12).stroke(selected ? AppColors.rose : .clear,lineWidth:1.5))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var options:some View {
        NavigationStack {
            Form {
                Toggle("Show guide",isOn:$model.configuration.showGuide)
                Picker("Appearance",selection:$model.configuration.mode) { ForEach(EyebrowGuideMode.allCases) { Text($0.title).tag($0) } }
                Button("Refresh placement") { camera.refitFace(); showOptions=false }
                if let distance=camera.distanceHint { Text(distance).font(.caption) }
                #if DEBUG
                Toggle("Debug face mesh + landmarks",isOn:$model.configuration.debugMesh)
                Text(camera.eyebrowDebug).font(.caption.monospaced())
                #endif
                Text("Placement guides only. Tutorial steps advance manually; the app does not judge your makeup.").font(.caption)
            }.navigationTitle("Guide settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { showOptions=false } } }
        }
    }
    @ViewBuilder private var fallback:some View {
        VStack(spacing:14) {
            Image(systemName:"camera").font(.largeTitle)
            if case .unsupported=model.availability {
                Text("Live camera unavailable").font(.headline)
                Text("Run on a compatible iPhone for face-following guides. No face tracking is simulated here.").font(.subheadline)
            } else if camera.denied {
                Text("Allow camera access").font(.headline)
                Button("Open Settings") { if let url=URL(string:UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                Button("Check permission") { Task { await camera.requestPermission() } }
            } else if let failure=camera.failure {
                Text("Camera paused").font(.headline); Text(failure).font(.caption)
                Button("Retry") { camera.failure=nil; camera.refitFace() }
            } else { ProgressView("Preparing camera").tint(.white) }
        }.multilineTextAlignment(.center).foregroundStyle(.white)
    }
    private var faceFrame:some View {
        RoundedRectangle(cornerRadius:60).trim(from:0.02,to:0.22).stroke(.white.opacity(0.9),style:StrokeStyle(lineWidth:2,lineCap:.round))
            .overlay(RoundedRectangle(cornerRadius:60).trim(from:0.52,to:0.72).stroke(.white.opacity(0.9),style:StrokeStyle(lineWidth:2,lineCap:.round)))
    }
}

// -Nimah: Thumbnail vector menunjukkan shape style, bukan foto hasil makeup palsu.
private struct FaceGuideStylePreview:View {
    let brow:EyebrowStyle?
    let forehead:ForeheadStyle?
    var body:some View {
        GeometryReader { proxy in
            let w=proxy.size.width,h=proxy.size.height
            Path { path in
                if let brow {
                    // -Nimah: Closed upper/lower outline matches the live shape guide.
                    for edge in 0...1 {
                        for i in 0...30 {
                            let t=Float(edge==0 ? i : 30-i)/30
                            let p=EyebrowGuideGenerator.target(t:t,inner:.init(0,0,0),outer:.init(1,0,0),style:brow)
                            let thickness=CGFloat(0.07*(1-t)+0.012)*h*(brow == .thin ? 0.55 : 1)
                            let point=CGPoint(x:10+CGFloat(p.x)*(w-20),y:h*0.65-CGFloat(p.y)*h+(edge==0 ? -thickness : thickness))
                            if edge==0 && i==0 { path.move(to:point) } else { path.addLine(to:point) }
                        }
                    }
                    path.closeSubpath()
                } else if let forehead {
                    if forehead == .hairline {
                        for edge in 0...1 {
                            for i in 0...30 {
                                let t=CGFloat(edge==0 ? i : 30-i)/30
                                let y=h*(edge==0 ? 0.58-0.40*sin(.pi*t) : 0.72-0.30*sin(.pi*t))
                                let point=CGPoint(x:w*(0.15+0.70*t),y:y)
                                if edge==0 && i==0 { path.move(to:point) } else { path.addLine(to:point) }
                            }
                        }
                        path.closeSubpath()
                    } else if forehead == .temple {
                        path.addEllipse(in:CGRect(x:w*0.12,y:h*0.22,width:w*0.20,height:h*0.55))
                        path.addEllipse(in:CGRect(x:w*0.68,y:h*0.22,width:w*0.20,height:h*0.55))
                    } else {
                        let narrow=forehead == .centerHighlight
                        path.addEllipse(in:CGRect(x:w*(narrow ? 0.35 : 0.15),y:h*0.22,width:w*(narrow ? 0.30 : 0.70),height:h*0.55))
                    }
                }
            }.stroke(AppColors.rose,style:StrokeStyle(lineWidth:2,lineCap:.round,dash:[4,3]))
        }
    }
}
