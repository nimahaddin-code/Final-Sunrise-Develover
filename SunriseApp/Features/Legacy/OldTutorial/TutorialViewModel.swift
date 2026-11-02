import Combine

@MainActor final class TutorialViewModel: ObservableObject {
    let tutorial: Tutorial
    @Published private(set) var stepIndex = 0
    var currentStep: TutorialStep? { tutorial.steps.indices.contains(stepIndex) ? tutorial.steps[stepIndex] : nil }
    var canGoBack: Bool { stepIndex > 0 }
    var canGoNext: Bool { stepIndex + 1 < tutorial.steps.count }
    init(tutorial: Tutorial) { self.tutorial = tutorial }
    func next() { if canGoNext { stepIndex += 1 } }
    func previous() { if canGoBack { stepIndex -= 1 } }
}
