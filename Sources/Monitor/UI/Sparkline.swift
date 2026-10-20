import SwiftUI

struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let lo = values.min() ?? 0, hi = values.max() ?? 1
            let span = max(hi - lo, 0.0001)
            Path { p in
                for (i, v) in values.enumerated() {
                    let x = values.count > 1 ? geo.size.width * CGFloat(i) / CGFloat(values.count - 1) : 0
                    let y = geo.size.height * (1 - CGFloat((v - lo) / span)) * 0.9 + geo.size.height * 0.05
                    i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 22)
    }
}
