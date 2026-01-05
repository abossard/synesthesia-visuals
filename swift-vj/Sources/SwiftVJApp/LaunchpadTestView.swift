import SwiftUI
import SwiftVJCore

@MainActor
class TestViewModel: ObservableObject, LaunchpadTestIO {
    @Published var logs: [String] = []
    @Published var isRunning = false
    @Published var pendingQuestion: String?
    
    private var answerContinuation: CheckedContinuation<Bool, Never>?
    
    // MARK: - LaunchpadTestIO
    
    nonisolated func print(_ message: String) {
        Task { @MainActor in
            self.logs.append(message)
        }
    }
    
    nonisolated func askYesNo(_ prompt: String) async -> Bool {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                self.pendingQuestion = prompt
                self.answerContinuation = continuation
            }
        }
    }
    
    // MARK: - Actions
    
    func answer(_ response: Bool) {
        pendingQuestion = nil
        answerContinuation?.resume(returning: response)
        answerContinuation = nil
    }
    
    func runTest() {
        guard !isRunning else { return }
        isRunning = true
        logs.removeAll()
        
        Task.detached {
            let test = LaunchpadE2ETest(io: self)
            await test.run()
            await MainActor.run {
                self.isRunning = false
            }
        }
    }
}

struct LaunchpadTestView: View {
    @StateObject private var viewModel = TestViewModel()
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Launchpad E2E Test")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            // Logs
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(viewModel.logs.enumerated()), id: \.offset) { index, log in
                            Text(log)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding()
                }
                .background(Color.black)
                .onChange(of: viewModel.logs.count) { _ in
                    if let lastIndex = viewModel.logs.indices.last {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                }
            }
            
            // Interaction Area
            VStack {
                if let question = viewModel.pendingQuestion {
                    VStack(spacing: 12) {
                        Text(question)
                            .font(.title3)
                            .bold()
                        
                        HStack(spacing: 20) {
                            Button(action: { viewModel.answer(true) }) {
                                Label("Yes", systemImage: "checkmark")
                                    .frame(minWidth: 80)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .controlSize(.large)
                            
                            Button(action: { viewModel.answer(false) }) {
                                Label("No", systemImage: "xmark")
                                    .frame(minWidth: 80)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .controlSize(.large)
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                    .shadow(radius: 4)
                    .padding()
                } else if !viewModel.isRunning {
                    Button(action: { 
                        // Stop existing module to avoid MIDI conflicts
                        appState.launchpadModule?.stop()
                        viewModel.runTest() 
                    }) {
                        Label("Start Test Sequence", systemImage: "play.fill")
                            .font(.headline)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                } else {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Test running...")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 600, minHeight: 700)
        .onDisappear {
            // Restart module when closing test view
            _ = appState.launchpadModule?.start()
        }
    }
}
