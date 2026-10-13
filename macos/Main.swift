import AppKit
import SwiftUI
import ServiceManagement

struct Verse: Decodable, Identifiable {
    let number: Int
    let surah_number: Int
    let surah_name: String
    let ayah: Int
    let arabic: String
    let english: String
    let tafsir: String
    var id: Int { number }
}
struct Quran: Decodable { let verses: [Verse] }
struct Preferences: Codable {
    var index = 0
    var readCount = 0
    var count = 1
    var translation = true
    var interval = 300
    var fontSize = 32.0
    var customBackground = false
}
func searchText(_ text: String) -> String {
    text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ar"))
        .replacingOccurrences(of: "ٱ", with: "ا").replacingOccurrences(of: "ى", with: "ي")
        .replacingOccurrences(of: "ـ", with: "")
}

@MainActor final class ReadingStore: ObservableObject {
    let verses: [Verse]
    let folder: URL
    @Published private(set) var preferences: Preferences
    @Published var error: String?
    var displayed: [Verse] { Array(verses.dropFirst(preferences.index).prefix(preferences.count)) }
    var chapters: [Verse] { verses.filter { $0.ayah == 1 } }
    var background: NSImage? {
        let custom = folder.appendingPathComponent("background.png")
        let bundled = Bundle.main.url(forResource: "background", withExtension: "png")
        return (preferences.customBackground ? custom : bundled).flatMap { NSImage(contentsOf: $0) }
    }
    init(folder: URL? = nil) throws {
        guard let resource = Bundle.main.url(forResource: "verses", withExtension: "json") else {
            throw NSError(domain: "QuranReminder", code: 1, userInfo: [NSLocalizedDescriptionKey: "ملف الآيات غير موجود"])
        }
        verses = try JSONDecoder().decode(Quran.self, from: Data(contentsOf: resource)).verses
        guard verses.count == 6236, verses.enumerated().allSatisfy({ $0.element.number == $0.offset + 1 }) else {
            throw NSError(domain: "QuranReminder", code: 2, userInfo: [NSLocalizedDescriptionKey: "بيانات القرآن غير كاملة"])
        }
        self.folder = try folder ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("QuranReminder")
        try FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
        let saved = self.folder.appendingPathComponent("preferences.json")
        preferences = FileManager.default.fileExists(atPath: saved.path) ? try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: saved)) : Preferences()
        try validate(preferences)
    }
    func validate(_ next: Preferences) throws {
        guard (0...verses.count).contains(next.index), (1...20).contains(next.count), next.interval >= 10,
              next.readCount >= 0, (18...64).contains(next.fontSize) else {
            throw NSError(domain: "QuranReminder", code: 3, userInfo: [NSLocalizedDescriptionKey: "إعدادات القراءة غير صحيحة"])
        }
    }
    func save(_ next: Preferences) throws {
        try validate(next)
        try JSONEncoder().encode(next).write(to: folder.appendingPathComponent("preferences.json"), options: .atomic)
        preferences = next
    }
    func confirm() throws {
        var next = preferences
        next.index += displayed.count
        next.readCount += displayed.count
        try save(next)
    }
    func importBackground(_ source: URL) throws {
        guard let image = NSImage(contentsOf: source), let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "QuranReminder", code: 4, userInfo: [NSLocalizedDescriptionKey: "اختَر صورة PNG أو JPG سليمة"])
        }
        try png.write(to: folder.appendingPathComponent("background.png"), options: .atomic)
    }
}

struct ReadingView: View {
    @ObservedObject var store: ReadingStore
    let hide: () -> Void
    @State private var settings = false
    @State private var tafsir = false
    var body: some View {
        ZStack {
            if let background = store.background { Image(nsImage: background).resizable().scaledToFill() }
            Color(red: 0.04, green: 0.12, blue: 0.16).opacity(0.72)
            VStack(spacing: 20) {
                Text("تذكير القرآن").font(.title2.weight(.semibold))
                Text("الآيات التي أكدت قراءتها: \(store.preferences.readCount)").font(.caption).opacity(0.8)
                ScrollView {
                    VStack(spacing: 24) {
                        if store.displayed.isEmpty { Text("وصلت إلى نهاية المصحف").font(.title) }
                        ForEach(store.displayed) { verse in
                            VStack(spacing: 14) {
                                Text(verse.arabic).font(.custom("Geeza Pro", size: store.preferences.fontSize))
                                if store.preferences.translation {
                                    Text(verse.english).font(.system(size: 19)).environment(\.layoutDirection, .leftToRight)
                                }
                                Text("\(verse.surah_name) · الآية \(verse.ayah)").font(.caption)
                                Divider().overlay(.white.opacity(0.25))
                            }.multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        }
                    }.padding(.horizontal, 12)
                }
                HStack(spacing: 12) {
                    Button(store.displayed.count > 1 ? "✓ قرأتها كلها" : "✓ قرأتها") {
                        do { try store.confirm(); hide() } catch { store.error = error.localizedDescription }
                    }.buttonStyle(.borderedProminent).disabled(store.displayed.isEmpty)
                    Button("التفسير") { tafsir = true }.disabled(store.displayed.isEmpty)
                    Button("الإعدادات") { settings = true }
                    Button("إخفاء", action: hide)
                }.controlSize(.large).buttonStyle(.bordered)
            }.padding(28).foregroundStyle(.white)
        }.clipped().tint(Color(red: 0.15, green: 0.36, blue: 0.43))
        .environment(\.layoutDirection, .rightToLeft)
        .sheet(isPresented: $settings) { SettingsView(store: store) }
        .sheet(isPresented: $tafsir) {
            VStack(alignment: .leading, spacing: 20) {
                Text("التفسير الميسر").font(.title2.bold())
                ScrollView {
                    ForEach(store.displayed) { verse in
                        VStack(alignment: .leading, spacing: 12) {
                            Text("\(verse.surah_name) · الآية \(verse.ayah)").font(.headline)
                            Text(verse.tafsir).font(.system(size: 20)).lineSpacing(10)
                            Divider()
                        }.padding(.bottom, 20).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Button("العودة للآيات") { tafsir = false }.buttonStyle(.borderedProminent)
            }.padding(28).frame(width: 680, height: 560).environment(\.layoutDirection, .rightToLeft)
        }
        .alert("تعذر إتمام العملية", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("حسنًا") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

struct SettingsView: View {
    @ObservedObject var store: ReadingStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Preferences
    @State private var search = ""
    @State private var changeStart = false
    @State private var chapter: Int
    @State private var ayah: Int
    @State private var selectedImage: URL?
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var failure: String?
    init(store: ReadingStore) {
        self.store = store
        _draft = State(initialValue: store.preferences)
        let verse = store.verses[min(store.preferences.index, store.verses.count - 1)]
        _chapter = State(initialValue: verse.surah_number)
        _ayah = State(initialValue: verse.ayah)
    }
    var matchingChapters: [Verse] {
        store.chapters.filter { search.isEmpty || searchText($0.surah_name).contains(searchText(search)) || String($0.surah_number).contains(search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("على طريقتك").font(.title.bold())
            Form {
                Section("خلفية الآيات") {
                    if let image = selectedImage.flatMap({ NSImage(contentsOf: $0) }) ?? store.background {
                        Image(nsImage: image).resizable().scaledToFill().frame(height: 90).clipped().cornerRadius(10)
                    }
                    Button("اختيار صورة من الجهاز") {
                        let picker = NSOpenPanel()
                        picker.canChooseDirectories = false
                        picker.allowsMultipleSelection = false
                        if picker.runModal() == .OK { selectedImage = picker.url }
                    }
                }
                Section("عرض الآيات") {
                    Stepper("عدد الآيات: \(draft.count)", value: $draft.count, in: 1...20)
                    Toggle("إظهار الترجمة الإنجليزية", isOn: $draft.translation)
                    Slider(value: $draft.fontSize, in: 18...64, step: 1) { Text("حجم الخط") }
                    Stepper("التذكير كل \(draft.interval / 60) دقائق", value: $draft.interval, in: 60...3600, step: 60)
                }
                Section("بداية القراءة") {
                    Toggle("اختيار سورة وآية جديدة", isOn: $changeStart)
                    if changeStart {
                        TextField("ابحث باسم السورة أو رقمها", text: $search)
                        Picker("السورة", selection: $chapter) {
                            ForEach(matchingChapters) { Text("\($0.surah_number) · \($0.surah_name)").tag($0.surah_number) }
                        }.onChange(of: chapter) { _ in ayah = 1 }
                        if matchingChapters.isEmpty { Text("لا توجد سورة مطابقة").foregroundStyle(.secondary) }
                        Picker("الآية", selection: $ayah) {
                            ForEach(store.verses.filter { $0.surah_number == chapter }) { Text("الآية \($0.ayah)").tag($0.ayah) }
                        }
                    }
                }
                Section("بدء التشغيل") {
                    Toggle("التشغيل عند تسجيل الدخول", isOn: $loginEnabled)
                    Text("ضع التطبيق في Applications. قد تحتاج للموافقة من إعدادات النظام ← عام ← عناصر الدخول.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            if let failure { Text(failure).foregroundStyle(.red).font(.caption) }
            HStack {
                Button("حفظ وعرض الآيات", action: apply).buttonStyle(.borderedProminent)
                Button("إلغاء") { dismiss() }
            }.controlSize(.large)
        }.padding(24).frame(width: 600, height: 700).environment(\.layoutDirection, .rightToLeft)
    }
    func apply() {
        do {
            if changeStart {
                guard matchingChapters.contains(where: { $0.surah_number == chapter }),
                      let verse = store.verses.first(where: { $0.surah_number == chapter && $0.ayah == ayah }) else {
                    failure = "اختَر سورة وآية من نتائج البحث"; return
                }
                draft.index = verse.number - 1
            }
            if let selectedImage { try store.importBackground(selectedImage); draft.customBackground = true }
            if loginEnabled && SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            if !loginEnabled && SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
            try store.save(draft)
            dismiss()
        } catch { failure = error.localizedDescription }
    }
}

@MainActor final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var store: ReadingStore!
    private var window: NSWindow!
    private var status: NSStatusItem!
    private var timer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        do { store = try ReadingStore() }
        catch { showFatal(error); return }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 680), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "تذكير القرآن"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: ReadingView(store: store, hide: { [weak self] in self?.hideReminder() }))
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "☾"
        status.button?.toolTip = "تذكير القرآن"
        let menu = NSMenu()
        menu.addItem(withTitle: "عرض الآيات", action: #selector(showReminder), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "إغلاق البرنامج", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        status.menu = menu
        showReminder()
    }
    @objc func showReminder() {
        timer?.invalidate()
        if let screen = NSScreen.main {
            let available = screen.visibleFrame
            window.setContentSize(NSSize(width: min(940, available.width - 40), height: min(720, available.height - 80)))
        }
        window.center()
        window.orderFrontRegardless()
    }
    func hideReminder() {
        window.orderOut(nil)
        timer?.invalidate()
        guard store.preferences.index < store.verses.count else { return }
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(store.preferences.interval), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.showReminder() }
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hideReminder(); return false }
    @objc func quit() { NSApplication.shared.terminate(nil) }
    func showFatal(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "تعذر فتح تذكير القرآن"
        alert.informativeText = error.localizedDescription
        alert.runModal()
        NSApplication.shared.terminate(nil)
    }
}

@main enum QuranReminderEntry {
@MainActor static func main() {
if CommandLine.arguments.contains("--check") {
    do {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try ReadingStore(folder: temporary)
        precondition(store.chapters.count == 114)
        precondition(searchText(store.chapters[0].surah_name).contains(searchText("الفاتحة")))
        var batch = store.preferences
        batch.count = 3
        try store.save(batch)
        precondition(store.displayed.map(\.number) == [1, 2, 3])
        try store.confirm()
        precondition(store.preferences.index == 3 && store.preferences.readCount == 3)
        batch = store.preferences
        batch.index = 6234
        try store.save(batch)
        precondition(store.displayed.count == 2)
        try store.confirm()
        precondition(store.displayed.isEmpty)
        let restored = try ReadingStore(folder: temporary)
        precondition(restored.preferences.index == 6236)
        precondition(store.verses.allSatisfy { !$0.english.isEmpty && !$0.tafsir.isEmpty })
        print("macOS checks passed: full data, surah search, grouped reading, final batch and persistence.")
    } catch { fputs("\(error)\n", stderr); exit(1) }
} else {
    let application = NSApplication.shared
    let controller = AppController()
    application.setActivationPolicy(.accessory)
    application.delegate = controller
    application.run()
}
}
}
