// -Nimah: Flow mengikuti referensi; langkah tutorial manual, bukan penilaian otomatis makeup.
import Foundation

enum FaceGuidePhase:Sendable { case positionFace,tracking,chooseFaceShape,chooseRegion,chooseStyle,tutorial }
struct FaceGuideLesson {
    let title:String
    let instruction:String
    static func steps(region:FaceGuideRegion,brow:EyebrowStyle,forehead:ForeheadStyle) -> [Self] {
        if region == .eyebrows {
            return [
                .init(title:"Mark your shape",instruction:"Check the three marks on your detected brow: head, arch and tail. Formula rays are optional references and may differ from your natural hair. Hold still and check the light if the outline does not follow your brow."),
                .init(title:"Define the upper edge",instruction:"Sketch lightly along the upper dashed outline. Keep the tail soft and tapered."),
                .init(title:"Define the lower edge",instruction:"Follow the lower outline with light pressure. Keep the front of the brow soft."),
                .init(title:brow == .feathered ? "Add feathered strokes" : "Fill & soften",instruction:brow == .feathered ? "Use short upward strokes following the small direction guides. Brush through to soften." : "Fill sparse areas inside the outline, then brush through. The guide does not check your application.")]
        }
        let placement:String
        switch forehead {
        case .hairline:placement="Place a small amount inside the upper contour band. Adjust its top edge to visible skin near your hairline."
        case .temple:placement="Place a small amount inside the two temple zones. Keep the center of the forehead clear."
        case .softSculpt:placement="Use a small amount inside the upper forehead area for a soft contour."
        case .centerHighlight:placement="Apply a little highlight inside the center oval. Keep it above the brows."
        case .softGlow:placement="Use a light layer inside the central area. Keep the edges sheer."
        }
        return [.init(title:"Check placement",instruction:placement),
                .init(title:"Blend softly",instruction:forehead.category == .contour ? "Blend outward toward the hairline or temples. Stay on visible skin and soften the boundary." : "Tap gently to blend the highlight. Preserve a soft edge and avoid a hard stripe."),
                .init(title:"Review your finish",instruction:"Hide the guide to check the result, then turn it back on if needed. Continue manually when the placement feels right.")]
    }
}
