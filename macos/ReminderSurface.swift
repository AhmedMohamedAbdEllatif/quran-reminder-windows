import SwiftUI

enum ReminderPalette {
    static let paper = Color(red: 241 / 255, green: 235 / 255, blue: 224 / 255)
    static let ink = Color(red: 48 / 255, green: 43 / 255, blue: 34 / 255)
    static let secondary = Color(red: 93 / 255, green: 85 / 255, blue: 71 / 255)
    static let edge = Color(red: 214 / 255, green: 204 / 255, blue: 186 / 255)
    static let accent = Color(red: 65 / 255, green: 57 / 255, blue: 46 / 255)
}
private struct PaperShadows: Shape {
    func path(in rectangle: CGRect) -> Path {
        var shadows = Path()
        shadows.move(to: CGPoint(x: -80, y: -60))
        shadows.addCurve(to: CGPoint(x: 310, y: 280), control1: CGPoint(x: 80, y: -40), control2: CGPoint(x: 60, y: 120))
        shadows.addCurve(to: CGPoint(x: -80, y: -60), control1: CGPoint(x: 120, y: 240), control2: CGPoint(x: 10, y: 90)); shadows.closeSubpath()
        shadows.move(to: CGPoint(x: 30, y: -90))
        shadows.addCurve(to: CGPoint(x: 390, y: 150), control1: CGPoint(x: 180, y: -50), control2: CGPoint(x: 160, y: 80))
        shadows.addCurve(to: CGPoint(x: 30, y: -90), control1: CGPoint(x: 200, y: 160), control2: CGPoint(x: 70, y: 20)); shadows.closeSubpath()
        shadows.move(to: CGPoint(x: -90, y: 20))
        shadows.addCurve(to: CGPoint(x: 200, y: 350), control1: CGPoint(x: 20, y: 80), control2: CGPoint(x: -20, y: 200))
        shadows.addCurve(to: CGPoint(x: -90, y: 20), control1: CGPoint(x: 10, y: 290), control2: CGPoint(x: -50, y: 140)); shadows.closeSubpath()
        shadows.move(to: CGPoint(x: -90, y: 170))
        shadows.addCurve(to: CGPoint(x: 180, y: 480), control1: CGPoint(x: 40, y: 230), control2: CGPoint(x: 10, y: 330))
        shadows.addCurve(to: CGPoint(x: -90, y: 170), control1: CGPoint(x: -20, y: 400), control2: CGPoint(x: -70, y: 290)); shadows.closeSubpath()
        shadows.move(to: CGPoint(x: 200, y: -90))
        shadows.addCurve(to: CGPoint(x: 570, y: 65), control1: CGPoint(x: 330, y: -50), control2: CGPoint(x: 350, y: 20))
        shadows.addCurve(to: CGPoint(x: 200, y: -90), control1: CGPoint(x: 380, y: 110), control2: CGPoint(x: 270, y: 0)); shadows.closeSubpath()
        return shadows.applying(CGAffineTransform(scaleX: rectangle.width / 1040, y: rectangle.height / 760))
    }
}
struct EditorialPaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 244 / 255, green: 239 / 255, blue: 229 / 255), Color(red: 232 / 255, green: 223 / 255, blue: 208 / 255)], startPoint: .topLeading, endPoint: .bottomTrailing)
            PaperShadows().fill(Color(red: 83 / 255, green: 74 / 255, blue: 60 / 255).opacity(0.12)).blur(radius: 19)
        }.clipped().environment(\.layoutDirection, .leftToRight)
    }
}
struct ReminderSurface: View {
    @ObservedObject var store: ReadingStore
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = store.background {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    ReminderPalette.paper.opacity(0.92)
                } else {
                    EditorialPaper()
                }
                RoundedRectangle(cornerRadius: 16).stroke(ReminderPalette.edge, lineWidth: 1).padding(1)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
