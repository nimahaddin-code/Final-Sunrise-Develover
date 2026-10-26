// -Nimah: Bundled research rules, decoded once. Integration enables calibration previews, not production approval.
import Foundation

struct MakeupRuleDatabase: Decodable, Sendable {
    struct Parameter: Decodable, Sendable {
        let value: Float
        let unit: String
        let basis: String
        let minimum: Float
        let maximum: Float
    }
    struct Assignment: Decodable, Sendable {
        let face_shape: String
        let eyebrow_preset_id: String?
        let blush_preset_id: String?
        let selected_reference_ids: [String]
        let supported: Bool
        let enabled_for_calibration: Bool
    }
    struct Preset: Decodable, Sendable {
        let id: String
        let parameters: [String:Parameter]
        func number(_ name: String) -> Float { parameters[name]!.value }
    }
    struct Palette: Decodable, Sendable {
        struct Channels: Decodable, Sendable { let value: [Double] }
        struct Intensity: Decodable, Sendable { let `default`: Parameter }
        let id: String
        let name: String
        let category: String
        let color: Channels
        let intensity: Intensity
    }
    struct Fitting: Decodable, Sendable { let parameters:[String:Parameter] }
    let runtime_fitting_rules:Fitting
    let recommendation_assignments: [Assignment]
    let eyebrow_presets: [Preset]
    let blush_presets: [Preset]
    let palettes: [Palette]
    // Missing/corrupt resources remain unavailable; never silently use the old A assignments.
    static let shared: MakeupRuleDatabase? = {
        guard let url=Bundle.main.url(forResource:"makeup-reference.database",withExtension:"json"),
              let data=try? Data(contentsOf:url) else { return nil }
        return try? decode(data)
    }()
    enum RuleError: Error { case invalid }
    static func decode(_ data: Data) throws -> Self {
        let rules=try JSONDecoder().decode(Self.self,from:data)
        let browKeys=["arch_t","arch_delta","tail_delta","max_displacement","half_thickness_design","thickness_scale","head_taper","arch_taper","tail_taper","head_fade_extent","edge_feather","max_alpha"]
        let blushKeys=["center_outward_offset","center_vertical_offset","major_radius","minor_radius","outward_up_angle","eye_margin","nose_margin","fallback_midline_exclusion_half_width","face_edge_margin","max_alpha","radial_power","blend_distance","mask_edge_feather","falloff_smoothstep_mix"]
        for (presets,keys) in [(rules.eyebrow_presets,browKeys),(rules.blush_presets,blushKeys)] {
            guard Set(presets.map(\.id)).count==presets.count else { throw RuleError.invalid }
            for preset in presets {
                guard keys.allSatisfy({ preset.parameters[$0] != nil }) else { throw RuleError.invalid }
                for (name,p) in preset.parameters {
                    let expectedUnit = name=="max_displacement" ? "meter" : name=="outward_up_angle" ? "degree" : name=="radial_power" ? "count" : "ratio"
                    guard p.unit==expectedUnit else { throw RuleError.invalid }
                    guard p.value.isFinite,p.minimum.isFinite,p.maximum.isFinite,p.minimum<=p.maximum,
                          (p.minimum...p.maximum).contains(p.value) else { throw RuleError.invalid }
                }
            }
        }
        guard Set(rules.recommendation_assignments.map(\.face_shape)).count==rules.recommendation_assignments.count else { throw RuleError.invalid }
        for a in rules.recommendation_assignments where a.supported {
            guard rules.eyebrow_presets.contains(where:{$0.id==a.eyebrow_preset_id}),
                  rules.blush_presets.contains(where:{$0.id==a.blush_preset_id}) else { throw RuleError.invalid }
        }
        guard rules.palettes.allSatisfy({ $0.color.value.count==3 && $0.color.value.allSatisfy { $0.isFinite && (0...1).contains($0) } }) else { throw RuleError.invalid }
        return rules
    }
    func assignment(_ shape: MakeupFaceShape) -> Assignment? {
        recommendation_assignments.first { $0.face_shape==shape.rawValue && $0.supported && $0.enabled_for_calibration }
    }
    static func browID(_ style: EyebrowStyle) -> String? {
        switch style {
        case .natural:return "brow.natural"
        case .softArch:return "brow.soft_arch"
        case .highArch:return "brow.high_arch"
        case .angular:return "brow.angular"
        case .rounded:return "brow.rounded"
        case .straight:return "brow.straight"
        case .lowArch:return "brow.low_arch"
        case .lifted:return "brow.lifted"
        case .thin,.feathered:return nil // Legacy studio modifiers are not assigned research presets.
        }
    }
    static func blushID(_ style: BlushPlacementStyle) -> String {
        switch style {
        case .apple:return "blush.apple"
        case .cheekbone:return "blush.cheekbone"
        case .outerSweep:return "blush.outer_sweep"
        case .highLift:return "blush.high_cheekbone"
        case .wideHorizontal:return "blush.horizontal"
        case .centerCheek:return "blush.center_cheek"
        case .centerDown:return "blush.center_down"
        case .upperInner:return "blush.upper_inner"
        case .templeSweep:return "blush.temple_sweep"
        case .diagonalBlend:return "blush.diagonal_blend"
        case .placementDots:return "blush.distributed_dots"
        case .innerCheek:return "blush.inner_blend"
        }
    }
    static func brow(_ style: EyebrowStyle) -> Preset? { shared?.eyebrow_presets.first { $0.id==browID(style) } }
    static func blush(_ style: BlushPlacementStyle) -> Preset? { shared?.blush_presets.first { $0.id==blushID(style) } }
}
