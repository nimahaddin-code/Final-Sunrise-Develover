// -Nimah: Static placement sketches in selector cards, never a simulated tracking feed.
import SwiftUI

struct BlushPlacementSketch:View {
    let style:BlushPlacementStyle
    var body:some View {
        GeometryReader { proxy in
            let w=proxy.size.width,h=proxy.size.height
            ZStack {
                Ellipse().fill(Color(red:1,green:0.94,blue:0.90)).overlay(Ellipse().stroke(Color.brown.opacity(0.25))).frame(width:w*0.72,height:h*0.94)
                Path { p in
                    for sign:CGFloat in [-1,1] {
                        let x=w*0.5+sign*w*0.15
                        p.move(to:CGPoint(x:x-w*0.045,y:h*0.36));p.addQuadCurve(to:CGPoint(x:x+w*0.045,y:h*0.36),control:CGPoint(x:x,y:h*0.40))
                    }
                    p.move(to:CGPoint(x:w*0.46,y:h*0.76));p.addLine(to:CGPoint(x:w*0.54,y:h*0.76))
                }.stroke(Color.brown.opacity(0.55),lineWidth:1)
                ForEach([-1,1],id:\.self) { side in
                    let spec=placement
                    if style == .placementDots {
                        ForEach(0..<4) { i in
                            Circle().fill(Color.pink.opacity(0.65)).frame(width:w*0.045,height:w*0.045)
                                .position(x:w*(0.5+CGFloat(side)*(0.20+CGFloat(i%2)*0.06)),y:h*(0.53+CGFloat(i/2)*0.08))
                        }
                    } else {
                        Ellipse().fill(Color.pink.opacity(0.55)).frame(width:w*spec.2,height:h*spec.3)
                            .rotationEffect(.degrees(Double(side)*spec.4))
                            .position(x:w*(0.5+CGFloat(side)*spec.0),y:h*spec.1)
                    }
                }
            }.frame(width:w,height:h)
        }.accessibilityLabel("\(style.title) · illustrative placement sketch")
    }
    private var placement:(CGFloat,CGFloat,CGFloat,CGFloat,Double) {
        switch style {
        case .apple:return (0.20,0.57,0.15,0.16,0)
        case .centerCheek:return (0.20,0.56,0.18,0.17,0)
        case .cheekbone:return (0.23,0.49,0.22,0.11,-20)
        case .outerSweep:return (0.27,0.52,0.23,0.10,-20)
        case .highLift:return (0.24,0.45,0.22,0.09,-20)
        case .wideHorizontal:return (0.20,0.59,0.26,0.10,0)
        case .centerDown:return (0.20,0.60,0.15,0.21,15)
        case .upperInner:return (0.16,0.49,0.17,0.10,25)
        case .templeSweep:return (0.29,0.43,0.24,0.10,-50)
        case .diagonalBlend:return (0.24,0.51,0.23,0.12,-35)
        case .placementDots:return (0.20,0.57,0.15,0.16,0)
        case .innerCheek:return (0.18,0.55,0.23,0.10,0)
        }
    }
}
