// -Nimah: One active implementation per feature, following the tech lead's ownership decision.
import SwiftUI

struct MakeupRecommendationsView:View {
    @ObservedObject var store:FaceShapeStore
    var onScanFace:()->Void
    // -Nimah: Connect Khalish's separate eye-scan route without restoring removed filters.
    var onScanEyes:()->Void = {}
    var body:some View {
        List {
            Section("Face scan") {
                if let result=store.latest {
                    Label { Text(result.shape.title) } icon:{ Image(systemName:result.shape.symbol) }
                    Text("Scan estimate · confidence \(Int(result.confidence*100))%").font(.caption).foregroundStyle(AppColors.subtle)
                    Button("View result / scan again",action:onScanFace)
                } else {
                    Text("Scan your face to get a face-shape estimate and eye measurements.")
                    Button("Scan face",action:onScanFace)
                }
            }
            Section("Eye scan") {
                if let eyes=store.eyes {
                    HStack { Text(eyes.openness.title); Text(eyes.tilt.title); Text(eyes.spacing.title) }
                }
                Button("View eye result / scan again",action:onScanEyes)
            }
            Section("Eyebrow & Blush") {
                NavigationLink(value:AppRoute.browBlush(.eyebrows)) { Label("Eyebrow",systemImage:"eyebrow") }
                NavigationLink(value:AppRoute.browBlush(.blush)) { Label("Blush",systemImage:"paintbrush.pointed") }
                if let shape=store.latest?.shape {
                    let mapped=shape == .triangle ? MakeupFaceShape.pear : MakeupFaceShape(rawValue:shape.rawValue) ?? .unknown
                    if let brow=MakeupPreferenceCatalog.browOptions(for:mapped).first { Text("Eyebrow starting style: \(brow.title)").font(.caption) }
                    if let blush=MakeupPreferenceCatalog.blushOptions(for:mapped).first { Text("Blush starting placement: \(blush.title)").font(.caption) }
                    Text("Based on your saved face shape. Try on directly, then follow the tutorial.").font(.caption).foregroundStyle(AppColors.subtle)
                } else {
                    Text("Choose a face shape manually if no scan result is available.").font(.caption).foregroundStyle(AppColors.subtle)
                }
            }
            Section("Eyeliner") {
                let plan=store.latest.map { MakeupPlan(scan:$0,eyeScan:store.eyes) } ?? MakeupPlan(shape:.oval,eyeScan:store.eyes)
                Text(plan.eyeliner.isNeutral ? "No clear eye result · neutral starting style" : "Recommended from your eye scan").font(.caption).foregroundStyle(AppColors.subtle)
                Text(plan.eyeliner.reason).font(.caption).foregroundStyle(AppColors.subtle)
                ForEach(plan.madeForYou) { item in
                    NavigationLink(value:AppRoute.makeupTryOn(plan:plan,applied:[item])) {
                        VStack(alignment:.leading) { Text(item.name);Text(item.detail).font(.caption).foregroundStyle(AppColors.subtle) }
                    }
                }
                Text("Other eyeliner styles remain available inside try-on. Rescan only when you want to update the saved result.").font(.caption).foregroundStyle(AppColors.subtle)
            }
        }.scrollContentBackground(.hidden).background(AppColors.background).navigationTitle("Try On")
    }
}

// -Nimah: Shared shade control retained for Hanum eyeliner.
struct ShadeDot: View {
    let shade: MakeupShade

    var body: some View {
        Circle()
            .fill(Color(red: shade.red, green: shade.green, blue: shade.blue))
            .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 2))
    }
}
