import KeyboardShortcuts
import SwiftUI

struct CompleteStep: View {
  var onComplete: () -> Void
  
  var body: some View {
    VStack(spacing: 0) {
      Spacer()
      
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 56))
        .foregroundStyle(.green)
      
      Spacer().frame(height: 20)
      
      Text("You're All Set!")
        .font(.title)
        .fontWeight(.bold)
      
      Spacer().frame(height: 8)
      
      Text("Customize the shortcut below, or use it to start searching.")
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      
      Spacer().frame(height: 32)
      
      VStack(spacing: 8) {
        Text("Search Shortcut")
          .font(.callout)
          .fontWeight(.medium)
        
        KeyboardShortcuts.Recorder(for: .activateSearch)
      }
      
      Spacer()
      
      VStack(spacing: 12) {
        Button("Complete") {
          onComplete()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        
        Button("Go to Settings") {
          onComplete()
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      
      Spacer().frame(height: 28)
    }
    .padding(.horizontal, 40)
    .onAppear {
      // Enable the keyboard shortcut to open search from this step
      // by marking onboarding as seen. The view remains visible until
      // the user navigates away or presses the shortcut.
      UserDefaults.standard.set(true, forKey: StorageKey.hasSeenWelcome)
    }
  }
}
