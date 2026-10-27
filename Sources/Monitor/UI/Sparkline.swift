import SwiftUI

struct Sparkline: View {
    let values: [Double]
    let color: Color
    var height: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let line = path(in: geo.size)
            ZStack {
                if values.count > 1 {
                    var area = line
                    let _ = area.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    let _ = area.addLine(to: CGPoint(x: 0, y: geo.size.height))
                    area.fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                }
                line.stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: height)
    }

    private func path(in size: CGSize) -> Path {
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let span = max(hi - lo, 0.0001)
        return Path { p in
            for (i, v) in values.enumerated() {
                let x = values.count > 1 ? size.width * CGFloat(i) / CGFloat(values.count - 1) : 0
                let y = size.height * (1 - CGFloat((v - lo) / span)) * 0.9 + size.height * 0.05
                i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
            }
        }
    }
}
