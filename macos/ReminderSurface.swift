import SwiftUI

enum ReminderPalette {
    static let paper = Color(red: 247 / 255, green: 243 / 255, blue: 234 / 255)
    static let ink = Color(red: 24 / 255, green: 53 / 255, blue: 68 / 255)
    static let secondary = Color(red: 56 / 255, green: 81 / 255, blue: 91 / 255)
    static let edge = Color(red: 216 / 255, green: 206 / 255, blue: 186 / 255)
}
struct ReminderSurface: View {
    @ObservedObject var store: ReadingStore
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ReminderPalette.paper
                if let image = store.background {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    ReminderPalette.paper.opacity(0.86)
                }
                RoundedRectangle(cornerRadius: 16).stroke(ReminderPalette.edge, lineWidth: 1).padding(1)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
