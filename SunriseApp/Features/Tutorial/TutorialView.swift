import SwiftUI

struct TutorialView: View {
    let referenceID: String
    @StateObject private var model: TutorialViewModel
    init(referenceID: String) {
        self.referenceID = referenceID
        _model = StateObject(wrappedValue: TutorialViewModel(tutorial: Tutorial(referenceID: referenceID, steps: TutorialStep.allCases)))
    }
    var body: some View {
        FeaturePlaceholderView(title: "Tutorial flow", symbol: "list.number",
            explanation: "Only step navigation works. Tutorial instructions, completion tracking and all AR overlays remain unimplemented.") {
                if let step = model.currentStep {
                    Text(step.title).font(AppTypography.heading)
                    HStack {
                        Button("Previous step", action: model.previous).disabled(!model.canGoBack)
                        Spacer()
                        Button("Next step", action: model.next).disabled(!model.canGoNext)
                    }
                } else { EmptyStateView(title: "No steps", message: "This tutorial has no configured steps.") }
                NavigationLink("Explore live guide placeholder", value: AppRoute.liveGuide(referenceID: referenceID))
                NavigationLink("Explore comparison placeholder", value: AppRoute.comparison(referenceID: referenceID))
            }
    }
}
