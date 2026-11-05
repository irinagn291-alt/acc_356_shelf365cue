import SwiftUI

enum ShelfInk {
    static let paper = Color(red: 0.979, green: 0.963, blue: 0.903)
    static let label = Color(red: 1, green: 0.994, blue: 0.953)
    static let blue = Color(red: 0.09, green: 0.20, blue: 0.66)
    static let navy = Color(red: 0.085, green: 0.104, blue: 0.197)
    static let line = Color(red: 0.79, green: 0.79, blue: 0.72)
    static let lime = Color(red: 0.86, green: 0.96, blue: 0.49)
    static let danger = Color(red: 0.62, green: 0.18, blue: 0.13)
}

struct ShelfKicker: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.monospaced().bold()).tracking(1.4)
    }
}

struct ShelfAction: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var secondary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).padding(.horizontal, 15).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(secondary ? ShelfInk.blue : .white)
            .background(secondary ? ShelfInk.label : ShelfInk.blue, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(ShelfInk.blue, lineWidth: 1) }
            .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.4)
    }
}

/// Four colored packages, printed as a two-ink shelf illustration.
struct ShelfPrint: View {
    var body: some View {
        Canvas { ctx, size in
            let scale = min(size.width / 148, size.height / 101)
            ctx.translateBy(x: (size.width - 148 * scale) / 2, y: (size.height - 101 * scale) / 2)
            ctx.scaleBy(x: scale, y: scale)
            let paper = ShelfInk.paper
            let blue = ShelfInk.blue
            let lime = ShelfInk.lime
            func rectangle(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat = 0) -> Path {
                Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: radius)
            }
            func ink(_ p: Path, _ color: Color) { ctx.fill(p, with: .color(color)) }
            func stroke(_ p: Path, _ color: Color, _ w: CGFloat = 1.5) { ctx.stroke(p, with: .color(color), lineWidth: w) }
            func poly(_ points: [CGPoint]) -> Path {
                var p = Path()
                p.addLines(points)
                p.closeSubpath()
                return p
            }
            // Tin with a lemon and two rolled rims.
            ink(rectangle(6, 47, 36, 41, 4), paper)
            ink(rectangle(6, 53, 36, 30), lime)
            ink(Path(ellipseIn: CGRect(x: 13, y: 60, width: 22, height: 13)), blue)
            stroke(rectangle(6, 47, 36, 41, 4), blue)
            // Folded milk carton.
            ink(poly([.init(x: 44,y: 33),.init(x: 52,y: 21),.init(x: 81,y: 21),.init(x: 87,y: 32),
                      .init(x: 87,y: 88),.init(x: 44,y: 88)]), paper)
            ink(rectangle(52, 16, 29, 5), lime)
            ink(rectangle(44, 42, 43, 23), lime)
            stroke(rectangle(44, 33, 43, 1), blue)
            ink(poly([.init(x: 54,y: 60),.init(x: 63,y: 44),.init(x: 72,y: 60)]), blue)
            for index in 0..<7 {
                ink(rectangle(CGFloat(51 + index * 4), 72, index.isMultiple(of: 2) ? 2 : 1, 9), blue)
            }
            // Preserving jar with a checkerboard label.
            ink(rectangle(96, 43, 34, 46, 6), paper)
            ink(rectangle(99, 36, 28, 8, 2), lime)
            ink(rectangle(96, 54, 34, 23), lime)
            for row in 0..<2 {
                for col in 0..<4 where (col + row).isMultiple(of: 2) {
                    ink(rectangle(CGFloat(100 + col * 7), CGFloat(59 + row * 7), 7, 7), blue)
                }
            }
            ink(rectangle(0, 89, 145, 4, 2), paper)
            ink(rectangle(8, 95, 128, 1), paper)
        }.accessibilityHidden(true)
    }
}

struct ShelfExpiry: View {
    let batch: ShelfBatch
    let today: Date
    private var days: Int? { batch.expiry?.distance(from: today) }
    var body: some View {
        let urgent = (days ?? Int.max) <= 3
        let text: String = {
            guard let days else { return "Undated" }
            if days < 0 { return days == -1 ? "1 day past date" : "\(-days) days past date" }
            if days == 0 { return "Check today" }
            if days == 1 { return "Check tomorrow" }
            return "Date · \(batch.expiry!.label)"
        }()
        Label(text, systemImage: urgent ? "clock.badge.exclamationmark" : "calendar")
            .font(.caption.weight(.semibold))
            .foregroundStyle(urgent ? ShelfInk.danger : ShelfInk.navy)
    }
}
