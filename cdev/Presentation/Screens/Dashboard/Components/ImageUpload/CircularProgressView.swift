import SwiftUI

/// Circular progress indicator following cdev design system
/// Uses: ColorSystem.primary (Cdev Teal) for progress arc
struct CircularProgressView: View {
    let progress: Double
    var size: CGFloat = 30
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            // Background circle - subtle white
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: lineWidth)

            // Progress arc - using ColorSystem.primary (Cdev Teal #4FD1C5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    ColorSystem.primary,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(Animations.stateChange, value: progress)

            // Percentage text - using rounded design for consistency
            Text("\(Int(progress * 100))")
                .font(.system(size: size * 0.35, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        CircularProgressView(progress: 0.25)
        CircularProgressView(progress: 0.50, size: 40)
        CircularProgressView(progress: 0.75, size: 50, lineWidth: 4)
        CircularProgressView(progress: 1.0)
    }
    .padding()
    .background(Color.black)
}
