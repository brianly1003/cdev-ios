import SwiftUI

/// Manager for showing copy feedback toasts globally
/// Use this to trigger the CopiedToast from anywhere (e.g., context menus)
@MainActor
final class CopyToastManager: ObservableObject {
    static let shared = CopyToastManager()

    @Published var isPresented: Bool = false
    @Published var message: String = "Copied to clipboard"

    private init() {}

    /// Show copy toast with optional custom message
    func show(message: String = "Copied to clipboard") {
        self.message = message
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isPresented = true
        }

        // Auto-dismiss after 1.5 seconds
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeOut(duration: 0.2)) {
                isPresented = false
            }
        }
    }
}

/// Global toast wrapper that uses the existing CopiedToast design
/// Place this in your root view to show copy feedback from context menus
struct CopyToast: View {
    @StateObject private var manager = CopyToastManager.shared

    var body: some View {
        if manager.isPresented {
            // Reuse existing CopiedToast from CopyButton.swift
            CopiedToast(message: manager.message)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        ColorSystem.terminalBg
            .ignoresSafeArea()

        VStack {
            Spacer()
            CopyToast()
                .padding(.bottom, 100)
        }
    }
    .onAppear {
        CopyToastManager.shared.show()
    }
}
