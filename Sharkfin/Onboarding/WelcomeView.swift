import KeyboardShortcuts
import SwiftUI

struct WelcomeView: View {
  var onComplete: () -> Void
  
  @Environment(CLIPModelManager.self) private var modelManager
  @Environment(DirectoryStore.self) private var directoryStore
  @Environment(IndexingService.self) private var indexingService
  @Environment(AppState.self) private var appState
  
  @State private var currentStep: OnboardingStep = .welcome
  @State private var showSkipConfirmation = false
  @State private var navigatingForward = true
  
  var body: some View {
    VStack(spacing: 0) {
      if currentStep != .welcome {
        StepIndicator(currentStep: currentStep) { step in
          navigateTo(step)
        }
        .padding(.top, 24)
        .padding(.bottom, 8)
      }
      
      Group {
        switch currentStep {
        case .welcome:
          WelcomeStep(
            onGetStarted: { navigateTo(.models) },
            onSkip: { showSkipConfirmation = true }
          )
        case .models:
          ModelsStep(
            modelManager: modelManager,
            onContinue: { navigateTo(.directories) },
            onSkip: { navigateTo(.directories) }
          )
        case .directories:
          DirectoriesStep(
            directoryStore: directoryStore,
            indexingService: indexingService,
            onContinue: { navigateTo(.complete) },
            onSkip: { navigateTo(.complete) }
          )
        case .complete:
          CompleteStep(
            onComplete: {
              onComplete()
            }
          )
        }
      }
      .id(currentStep)
      .transition(.asymmetric(
        insertion: .move(edge: navigatingForward ? .trailing : .leading),
        removal: .move(edge: navigatingForward ? .leading : .trailing)
      ))
    }
    .frame(width: 480, height: 560)
    .clipped()
    .alert(
      "Skip Setup?",
      isPresented: $showSkipConfirmation
    ) {
      Button("Skip", role: .destructive) {
        onComplete()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("You can always configure models and directories in Settings later.")
    }
  }
  
  private func navigateTo(_ step: OnboardingStep) {
    navigatingForward = step.rawValue > currentStep.rawValue
    withAnimation(.easeInOut(duration: 0.3)) {
      currentStep = step
    }
  }
}
