import SwiftUI

/// Main view with tab navigation and shared header
struct ContentView: View {
    @State private var selectedTab = 0
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content
            VStack(spacing: 0) {
                // Shared header
                VStack(spacing: 8) {
                    Text("LATINVM")
                        .font(.custom("Optima", size: 42))
                        .fontWeight(.medium)

                    HStack(spacing: 6) {
                        Text("Predictive Latin Keyboard")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Image(systemName: "keyboard")
                            .foregroundColor(.blue.opacity(0.7))
                            .font(.subheadline)
                    }
                }
                .padding(.top, 40)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { isTextFieldFocused = false }

                Divider()
                    .padding(.horizontal, 40)

                // Tab content below the divider
                TabView(selection: $selectedTab) {
                    SetupContentView()
                        .tag(0)

                    PracticeContentView(isTextFieldFocused: $isTextFieldFocused)
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Spacer for tab bar height
                Spacer().frame(height: 56)
            }
            .onTapGesture {
                isTextFieldFocused = false
            }

            // Tab bar at bottom
            HStack(spacing: 0) {
                TabButton(
                    title: "Setup",
                    systemImage: "gearshape",
                    isSelected: selectedTab == 0
                ) {
                    isTextFieldFocused = false
                    selectedTab = 0
                }

                TabButton(
                    title: "Practice",
                    systemImage: "keyboard",
                    isSelected: selectedTab == 1
                ) {
                    selectedTab = 1
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(Color(.systemBackground))
        }
        .ignoresSafeArea(.keyboard)
    }
}

/// Custom tab button
struct TabButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 22))
                Text(title)
                    .font(.caption)
            }
            .foregroundColor(isSelected ? .blue : .secondary)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Setup instructions content (below divider)
struct SetupContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Setup Instructions")
                        .font(.headline)
                        .padding(.top, 24)

                    SetupStepView(
                        number: 1,
                        title: "Open Settings",
                        description: "Go to Settings → General → Keyboard → Keyboards"
                    )

                    SetupStepView(
                        number: 2,
                        title: "Add Keyboard",
                        description: "Tap 'Add New Keyboard...' and select 'Latinum'"
                    )

                    SetupStepView(
                        number: 3,
                        title: "Start Typing",
                        description: "Switch to Latinum using the globe key"
                    )
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 40)
            }

            Spacer()

            // Privacy notice
            VStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.title2)
                    .foregroundColor(.green)

                Text("Privacy Guaranteed")
                    .font(.headline)

                Text("Latinum works offline. No data is collected, transmitted, or stored. Your keystrokes never leave your device.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.bottom, 24)
        }
    }
}

/// Typing practice content (below divider)
struct PracticeContentView: View {
    var isTextFieldFocused: FocusState<Bool>.Binding
    @State private var text = ""

    var body: some View {
        VStack(spacing: 16) {
            // Text editor
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(size: 18))
                    .padding(4)
                    .focused(isTextFieldFocused)

                if text.isEmpty {
                    Text("Scribe hic...")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.top, 24)

            // Clear button - always visible, disabled when empty
            Button(action: { text = "" }) {
                Label("Clear", systemImage: "trash")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .disabled(text.isEmpty)

            Spacer()
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
