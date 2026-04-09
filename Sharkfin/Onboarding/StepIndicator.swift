import SwiftUI

struct StepIndicator: View {
  let currentStep: OnboardingStep
  var onNavigate: (OnboardingStep) -> Void
  
  private let steps: [(step: OnboardingStep, label: String)] = [
    (.models, "Models"),
    (.directories, "Directories"),
    (.complete, "Done"),
  ]
  
  var body: some View {
    HStack(spacing: 6) {
      ForEach(Array(steps.enumerated()), id: \.offset) { index, item in
        if index > 0 {
          Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundStyle(.quaternary)
        }
        
        let isCompleted = item.step.rawValue < currentStep.rawValue
        let isCurrent = item.step == currentStep
        let canNavigate = isCompleted
        
        Button {
          if canNavigate {
            onNavigate(item.step)
          }
        } label: {
          HStack(spacing: 4) {
            if isCompleted {
              Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
            }
            
            Text(item.label)
              .font(.caption)
              .fontWeight(isCurrent ? .semibold : .regular)
          }
          .foregroundStyle(isCurrent ? .primary : .secondary)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(
            isCurrent ? Color.accentColor.opacity(0.12) : Color.clear,
            in: Capsule()
          )
        }
        .buttonStyle(.plain)
        .disabled(!canNavigate)
      }
    }
  }
}
