import AppKit
import CoreText
import SwiftUI

enum MushafSegment {
    case body(String)
    case endNumber(String)
    var sourceText: String {
        switch self { case .body(let text), .endNumber(let text): return text }
    }
}
private let verseNumberPattern = try! NSRegularExpression(pattern: "[٠-٩]+")
func mushafSegments(_ text: String) -> [MushafSegment] {
    let source = text as NSString
    var segments: [MushafSegment] = []
    var cursor = 0
    for match in verseNumberPattern.matches(in: text, range: NSRange(location: 0, length: source.length)) {
        if match.range.location > cursor { segments.append(.body(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))) }
        segments.append(.endNumber(source.substring(with: match.range)))
        cursor = NSMaxRange(match.range)
    }
    if cursor < source.length { segments.append(.body(source.substring(from: cursor))) }
    return segments
}
func arabicVerseNumber(_ number: Int) -> String {
    String(number).map { Character(UnicodeScalar(0x0660 + $0.wholeNumberValue!)!) }.reduce("") { $0 + String($1) }
}
@MainActor enum QuranMarkers {
    private static var outline: CGPath?
    static func load() throws {
        if outline != nil { return }
        guard let url = Bundle.main.url(forResource: "AmiriQuran", withExtension: "ttf") else { throw failure("ملف خط فواصل الآيات غير موجود") }
        var registrationError: Unmanaged<CFError>?
        guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &registrationError) else {
            throw registrationError?.takeRetainedValue() as Error? ?? failure("تعذر تحميل خط فواصل الآيات")
        }
        let font = CTFontCreateWithName("AmiriQuran-Regular" as CFString, 40, nil)
        var character: UniChar = 0x06DD
        var glyph: CGGlyph = 0
        guard CTFontCopyPostScriptName(font) as String == "AmiriQuran-Regular",
              CTFontGetGlyphsForCharacters(font, &character, &glyph, 1),
              let path = CTFontCreatePathForGlyph(font, glyph, nil), !path.boundingBoxOfPath.isEmpty else { throw failure("علامة نهاية الآية غير متاحة في الخط") }
        outline = path
    }
    private static func failure(_ description: String) -> NSError {
        NSError(domain: "QuranMarkers", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
    }
    static func image(_ digits: String, size: Double) -> NSImage {
        let path = outline!
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rectangle in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let ink = NSColor(ReminderPalette.ink)
            drawOutline(path, in: rectangle, context: context, ink: ink)
            let factor = digits.count >= 3 ? 0.36 : 0.42
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size * factor), .foregroundColor: ink]
            let number = digits as NSString
            let extent = number.size(withAttributes: attributes)
            number.draw(at: NSPoint(x: (rectangle.width - extent.width) / 2, y: (rectangle.height - extent.height) / 2), withAttributes: attributes)
            return true
        }
    }
    private nonisolated static func drawOutline(_ path: CGPath, in rectangle: NSRect, context: CGContext, ink: NSColor) {
        let bounds = path.boundingBoxOfPath
        let scale = min(rectangle.width / bounds.width, rectangle.height / bounds.height)
        context.saveGState()
        context.translateBy(x: (rectangle.width - bounds.width * scale) / 2 - bounds.minX * scale, y: (rectangle.height - bounds.height * scale) / 2 - bounds.minY * scale)
        context.scaleBy(x: scale, y: scale)
        context.addPath(path)
        context.setFillColor(ink.cgColor)
        context.fillPath()
        context.restoreGState()
    }
    static func text(_ digits: String, size: Double) -> Text {
        Text(Image(nsImage: image(digits, size: size)).renderingMode(.original)).baselineOffset(-size * 0.12)
    }
}
@MainActor func mushafLineText(_ text: String, size: Double) -> Text {
    mushafSegments(text).reduce(Text("")) { accumulated, segment in
        switch segment {
        case .body(let body): return accumulated + Text(verbatim: body)
        case .endNumber(let digits): return accumulated + QuranMarkers.text(digits, size: size)
        }
    }
}
@MainActor func readingVerseText(_ verse: Verse, size: Double) -> Text {
    Text(verbatim: verse.arabic) + Text(" ") + QuranMarkers.text(arabicVerseNumber(verse.ayah), size: size)
}
