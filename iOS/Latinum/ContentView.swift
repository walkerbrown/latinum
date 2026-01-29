import SwiftUI

/// Main view providing keyboard setup instructions
struct ContentView: View {
    @State private var isKeyboardEnabled = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("LATINVM")
                        .font(.system(size: 36, weight: .bold, design: .serif))
                    Text("Predictive Latin Keyboard")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)

                Divider()
                    .padding(.horizontal, 40)

                // Setup instructions
                VStack(alignment: .leading, spacing: 16) {
                    Text("Setup Instructions")
                        .font(.headline)

                    SetupStepView(
                        number: 1,
                        title: "Open Settings",
                        description: "Go to Settings > General > Keyboard > Keyboards"
                    )

                    SetupStepView(
                        number: 2,
                        title: "Add Keyboard",
                        description: "Tap 'Add New Keyboard...' and select 'Latinum'"
                    )

                    SetupStepView(
                        number: 3,
                        title: "Allow Full Access",
                        description: "Tap 'Latinum' and enable 'Allow Full Access' for predictions"
                    )

                    SetupStepView(
                        number: 4,
                        title: "Start Typing",
                        description: "Switch to Latinum using the globe key"
                    )
                }
                .padding(.horizontal, 24)

                Spacer()

                // Privacy notice
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.title2)
                        .foregroundColor(.green)

                    Text("Privacy Guaranteed")
                        .font(.headline)

                    Text("Latinum works entirely offline. No data is collected, transmitted, or stored. Your keystrokes never leave your device.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.bottom, 40)
            }
            .navigationBarHidden(true)
        }
    }
}

/// Individual setup step view
struct SetupStepView: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Step number
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
