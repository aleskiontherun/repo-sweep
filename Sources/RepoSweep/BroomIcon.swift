import SwiftUI

/// A broom, drawn because SF Symbols doesn't have one. Filled with the
/// current foreground style, so it sits in a `Label` like a symbol does.
struct BroomIcon: View {
    var body: some View {
        BroomShape()
            .aspectRatio(1, contentMode: .fit)
            .frame(width: 15, height: 15)
            .accessibilityHidden(true)
    }
}

private struct BroomShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Drawn upright on a 16×16 grid, then leaned over.
        var path = Path()
        // Handle.
        path.addRoundedRect(in: CGRect(x: 7.2, y: 0, width: 1.6, height: 8.5),
                            cornerSize: CGSize(width: 0.8, height: 0.8))
        // Binding.
        path.addRoundedRect(in: CGRect(x: 5.2, y: 7.8, width: 5.6, height: 2.4),
                            cornerSize: CGSize(width: 0.6, height: 0.6))
        // Bristles: a flared fan of strands with gaps between them.
        let strands = 5
        let topLeft = 5.6, topRight = 10.4, bottomLeft = 2.6, bottomRight = 13.4
        let top = 10.6, bottom = 16.0
        for i in 0..<strands {
            let a = Double(i) / Double(strands), b = Double(i + 1) / Double(strands)
            let gap = 0.12
            let t0 = topLeft + (topRight - topLeft) * (a + gap / 2)
            let t1 = topLeft + (topRight - topLeft) * (b - gap / 2)
            let b0 = bottomLeft + (bottomRight - bottomLeft) * (a + gap / 2)
            let b1 = bottomLeft + (bottomRight - bottomLeft) * (b - gap / 2)
            path.move(to: CGPoint(x: t0, y: top))
            path.addLine(to: CGPoint(x: t1, y: top))
            path.addLine(to: CGPoint(x: b1, y: bottom))
            path.addLine(to: CGPoint(x: b0, y: bottom))
            path.closeSubpath()
        }

        let scale = min(rect.width, rect.height) / 16
        let transform = CGAffineTransform(translationX: -8, y: -8)
            .concatenating(CGAffineTransform(rotationAngle: .pi / 6))
            .concatenating(CGAffineTransform(scaleX: scale * 0.92, y: scale * 0.92))
            .concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY))
        return path.applying(transform)
    }
}
