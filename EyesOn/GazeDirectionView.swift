import SwiftUI

struct GazeDirectionView: View {
    let direction: GazeDirection?

    private let gridSize: CGFloat = 72
    private let dotRadius: CGFloat = 9
    private let travel: CGFloat = 20  // max dot displacement from center

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black.opacity(0.65))
                    .frame(width: gridSize, height: gridSize)

                // Crosshair
                crosshair

                // Direction dot
                if let dir = direction {
                    Circle()
                        .fill(dotColor(for: dir))
                        .frame(width: dotRadius * 2, height: dotRadius * 2)
                        .offset(
                            x: dir.offset.x * travel,
                            y: dir.offset.y * travel
                        )
                        .shadow(color: dotColor(for: dir).opacity(0.8), radius: 4)
                        .animation(.spring(response: 0.18, dampingFraction: 0.7), value: dir)
                }
            }

            // Label
            Text(direction?.arrow ?? "—")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            Text(direction?.label ?? "")
                .font(.caption2.bold())
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private var crosshair: some View {
        ZStack {
            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(width: 1, height: gridSize - 16)
            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(width: gridSize - 16, height: 1)
            Circle()
                .stroke(.white.opacity(0.2), lineWidth: 1)
                .frame(width: travel * 2, height: travel * 2)
        }
    }

    private func dotColor(for direction: GazeDirection) -> Color {
        direction == .center ? .green : .orange
    }
}

#Preview {
    HStack(spacing: 20) {
        ForEach([GazeDirection.center, .left, .right, .up, .down], id: \.label) { dir in
            GazeDirectionView(direction: dir)
        }
    }
    .padding()
    .background(.black)
}
