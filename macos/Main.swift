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
    var nextReadingDue: Date?
    var interval = 300
    var fontSize = 32.0
    var customBackground = false
}
func searchText(_ text: String) -> String {
    text.decomposedStringWithCanonicalMapping
        .replacingOccurrences(of: "\\p{M}|[\\u06D6-\\u06ED]", with: "", options: .regularExpression)
        .replacingOccurrences(of: "ٱ", with: "ا").replacingOccurrences(of: "ى", with: "ي")
        .replacingOccurrences(of: "ـ", with: "")
}

@MainActor final class ReadingStore: ObservableObject {
    let verses: [Verse]
    let chapters: [Verse]
    private var backgroundImage: NSImage?
    let folder: URL
    @Published private(set) var preferences: Preferences
    @Published var error: String?
    var showSaveConfirmation: ((String, String) -> Void)?
    var displayed: [Verse] { Array(verses.dropFirst(preferences.index).prefix(preferences.count)) }
    var background: NSImage? {
        guard preferences.customBackground else { return nil }
        if let backgroundImage { return backgroundImage }
        let custom = folder.appendingPathComponent("background.png")
        backgroundImage = NSImage(contentsOf: custom)
        return backgroundImage
    }
    init(folder: URL? = nil) throws {
        try QuranMarkers.load()
        guard let resource = Bundle.main.url(forResource: "verses", withExtension: "json") else {
            throw NSError(domain: "QuranReminder", code: 1, userInfo: [NSLocalizedDescriptionKey: "ملف الآيات غير موجود"])
        }
        verses = try JSONDecoder().decode(Quran.self, from: Data(contentsOf: resource)).verses
        chapters = verses.filter { $0.ayah == 1 }
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
        if preferences.customBackground != next.customBackground { backgroundImage = nil }
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
        backgroundImage = image
    }
}

struct ReadingView: View {
    @ObservedObject var store: ReadingStore
    @ObservedObject var memorization: MemorizationStore
    let hide: () -> Void
    @State private var settings = false
    @State private var tafsir = false
    @State private var memorizationSettings = false
    var body: some View {
        ZStack {
            ReminderSurface(store: store)
            VStack(spacing: 20) {
                Text("تذكير القرآن").font(.title2.weight(.semibold))
                Text("الآيات التي أكدت قراءتها: \(store.preferences.readCount)").font(.caption).foregroundStyle(ReminderPalette.secondary)
                ScrollView {
                    VStack(spacing: 24) {
                        if store.displayed.isEmpty { Text("وصلت إلى نهاية المصحف").font(.title) }
                        ForEach(store.displayed) { verse in
                            VStack(spacing: 14) {
                                readingVerseText(verse, size: store.preferences.fontSize).font(.custom("AmiriQuran-Regular", size: store.preferences.fontSize))
                                    .accessibilityLabel(verse.arabic + "، الآية " + arabicVerseNumber(verse.ayah))
                                if store.preferences.translation {
                                    Text(verse.english).font(.system(size: 19)).environment(\.layoutDirection, .leftToRight)
                                }
                                Text("\(verse.surah_name) · الآية \(verse.ayah)").font(.caption)
                                Divider().overlay(ReminderPalette.edge)
                            }.multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        }
                    }.padding(.horizontal, 12)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 10) {
                    Button(store.displayed.count > 1 ? "✓ قرأتها كلها" : "✓ قرأتها") {
                        do { try store.confirm(); hide() } catch { store.error = error.localizedDescription }
                    }.buttonStyle(.borderedProminent).foregroundStyle(.white).disabled(store.displayed.isEmpty)
                    Button("التفسير") { tafsir = true }.disabled(store.displayed.isEmpty)
                    Button("الإعدادات") { settings = true }
                    Button("خطة الحفظ") { memorizationSettings = true }
                    Button("إخفاء", action: hide)
                }.controlSize(.large).buttonStyle(.bordered)
            }.padding(28).foregroundStyle(ReminderPalette.ink)
        }.preferredColorScheme(.light).clipped().tint(Color(red: 0.15, green: 0.36, blue: 0.43))
        .environment(\.layoutDirection, .rightToLeft)
        .sheet(isPresented: $settings) { SettingsView(store: store, memorization: memorization) }
        .sheet(isPresented: $memorizationSettings) { SettingsView(store: store, memorization: memorization, initialTab: 1) }
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
            }.padding(28).frame(width: min(680, (NSScreen.main?.visibleFrame.width ?? 720) - 40), height: min(560, (NSScreen.main?.visibleFrame.height ?? 640) - 60)).environment(\.layoutDirection, .rightToLeft)
        }
        .alert("تعذر إتمام العملية", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("حسنًا") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

struct SettingsView: View {
    @ObservedObject var store: ReadingStore
    @ObservedObject var memorization: MemorizationStore
    @State private var selectedTab: Int
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Preferences
    @State private var surahValid = true
    @State private var changeStart = false
    @State private var chapter: Int
    @State private var ayah: Int
    @State private var selectedImage: URL?
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var failure: String?
    init(store: ReadingStore, memorization: MemorizationStore, initialTab: Int = 0) {
        self.memorization = memorization
        _selectedTab = State(initialValue: initialTab)
        self.store = store
        _draft = State(initialValue: store.preferences)
        let verse = store.verses[min(store.preferences.index, store.verses.count - 1)]
        _chapter = State(initialValue: verse.surah_number)
        _ayah = State(initialValue: verse.ayah)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("على طريقتك").font(.title.bold())
            Picker("الإعدادات", selection: $selectedTab) {
                Text("القراءة").tag(0)
                Text("الحفظ").tag(1)
                Text("الخلفية").tag(2)
            }.pickerStyle(.segmented)
            ZStack {
                MemorizationSettingsView(store: memorization, chapters: store.chapters, saved: {
                    let title = memorization.plan.enabled ? "خطة الحفظ اشتغلت" : "تم حفظ الخطة متوقفة"
                    let message = memorization.plan.enabled ? "أول تذكير بعد \(memorization.plan.interval) ثانية." : "التذكير بالحفظ غير مفعّل. فعّله من تبويب الحفظ لتبدأ."
                    store.showSaveConfirmation?(title, message)
                })
                    .opacity(selectedTab == 1 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 1)
                    .accessibilityHidden(selectedTab != 1)
            VStack(alignment: .leading, spacing: 18) {
            Form {
                if selectedTab == 2 {
                Section("خلفية الآيات") {
                    if let image = selectedImage.flatMap({ NSImage(contentsOf: $0) }) ?? (draft.customBackground ? store.background : nil) {
                        Image(nsImage: image).resizable().scaledToFill().frame(height: 90).clipped().overlay(ReminderPalette.paper.opacity(0.86)).cornerRadius(10)
                    } else {
                        Text("الخلفية الافتراضية — أوف وايت دافئ").frame(maxWidth: .infinity).frame(height: 90)
                            .foregroundStyle(ReminderPalette.ink).background(ReminderPalette.paper).cornerRadius(10)
                    }
                    Button("استعادة الخلفية الافتراضية") { selectedImage = nil; draft.customBackground = false }
                    Button("اختيار صورة من الجهاز") {
                        let picker = NSOpenPanel()
                        picker.canChooseDirectories = false
                        picker.allowsMultipleSelection = false
                        if picker.runModal() == .OK { selectedImage = picker.url; draft.customBackground = true }
                    }
                }
                } else {
                Section("عرض الآيات") {
                    Stepper("عدد الآيات: \(draft.count)", value: $draft.count, in: 1...20)
                    Toggle("إظهار الترجمة الإنجليزية", isOn: $draft.translation)
                    Slider(value: $draft.fontSize, in: 18...64, step: 1) { Text("حجم الخط") }
                    Stepper("التذكير كل \(draft.interval / 60) دقائق", value: $draft.interval, in: 60...3600, step: 60)
                }
                Section("بداية القراءة") {
                    Toggle("اختيار سورة وآية جديدة", isOn: $changeStart)
                    if changeStart {
                        SurahSelector(chapters: store.chapters, selection: $chapter, validSelection: $surahValid)
                            .frame(height: 32).onChange(of: chapter) { _ in ayah = 1 }
                        Picker("الآية", selection: $ayah) {
                            ForEach(store.verses.filter { $0.surah_number == chapter }) { Text("الآية \($0.ayah)").tag($0.ayah) }
                        }
                    }
                }
                Section("بدء التشغيل") {
                    Toggle("التشغيل عند تسجيل الدخول", isOn: $loginEnabled)
                    Text("ضع التطبيق في Applications. قد تحتاج للموافقة من إعدادات النظام ← عام ← عناصر الدخول.").font(.caption).foregroundStyle(.secondary)
                }
                }
            }.formStyle(.grouped)
            if let failure { Text(failure).foregroundStyle(.red).font(.caption) }
            HStack {
                Button("حفظ وعرض الآيات", action: apply).buttonStyle(.borderedProminent)
                Button("إلغاء") { dismiss() }
            }.controlSize(.large)
            }.opacity(selectedTab == 1 ? 0 : 1)
             .allowsHitTesting(selectedTab != 1)
             .accessibilityHidden(selectedTab == 1)
            }
        }.padding(24).frame(width: min(640, (NSScreen.main?.visibleFrame.width ?? 720) - 40), height: min(780, (NSScreen.main?.visibleFrame.height ?? 840) - 60)).environment(\.layoutDirection, .rightToLeft)
    }
    func apply() {
        do {
            if changeStart {
                guard surahValid,
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
            store.showSaveConfirmation?("تم حفظ الإعدادات", "وقت القراءة: \(draft.interval / 60) دقيقة بعد إخفاء الآيات أو تأكيد قراءتها.")
        } catch { failure = error.localizedDescription }
    }
}

@MainActor final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var store: ReadingStore!
    private var window: NSWindow!
    private var status: NSStatusItem!
    private var timer: Timer?
    private var memorization: MemorizationStore!
    private var memorizationWindow: NSWindow!
    private var memorizationTimer: Timer?
    private let confirmation = SaveConfirmationController()
    private var updates: UpdateChecker!
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let checkFolder = CommandLine.arguments.contains("--ui-check") ? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) : nil
            store = try ReadingStore(folder: checkFolder)
            memorization = try MemorizationStore(folder: store.folder)
        }
        catch { showFatal(error); return }
        let updateDefaults = CommandLine.arguments.contains("--ui-check") ? UserDefaults(suiteName: "QuranReminder-UpdateCheck-" + UUID().uuidString)! : .standard
        updates = UpdateChecker(defaults: updateDefaults)
        store.showSaveConfirmation = { [weak self] title, message in self?.confirmation.show(title: title, message: message) }
        window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 940, height: 720), styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 440, height: 360)
        window.title = "تذكير القرآن"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: ReadingView(store: store, memorization: memorization, hide: { [weak self] in self?.hideReminder() }))
        memorizationWindow = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 940, height: 720), styleMask: [.titled, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        memorizationWindow.minSize = NSSize(width: 440, height: 360)
        memorizationWindow.title = "الحفظ والمراجعة"
        memorizationWindow.level = .floating
        memorizationWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        memorizationWindow.contentView = NSHostingView(rootView: MemorizationSessionView(store: memorization, appearance: store, dismissWindow: { [weak self] in self?.memorizationWindow.orderOut(nil); self?.scheduleMemorization() }))
        memorization.scheduleChanged = { [weak self] in self?.scheduleMemorization() }
        scheduleMemorization()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "☾"
        status.button?.toolTip = "تذكير القرآن"
        let menu = NSMenu()
        menu.addItem(withTitle: "عرض الآيات", action: #selector(showReminder), keyEquivalent: "")
        menu.addItem(withTitle: "تحميل آخر إصدار", action: #selector(openLatestRelease), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "إغلاق البرنامج", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        status.menu = menu
        showDueReading()
        if !CommandLine.arguments.contains("--ui-check") { updates.start() }
        if CommandLine.arguments.contains("--ui-check") {
            let futureUpdate = GitHubRelease(tag_name: "v9.0.0", html_url: "https://github.com/AhmedMohamedAbdEllatif/quran-reminder-windows/releases/tag/v9.0.0", draft: false, prerelease: false)
            updates.accept(futureUpdate)
            guard updates.isNoticeVisible else { fputs("Update notice failed to open\n", stderr); exit(1) }
            updates.dismissNotice()
            let restoredUpdates = UpdateChecker(defaults: updateDefaults)
            restoredUpdates.accept(futureUpdate)
            guard !restoredUpdates.isNoticeVisible else { fputs("Update notice was repeated\n", stderr); exit(1) }
            updates.retryLater("Offline test")
            guard let retryDate = updateDefaults.object(forKey: "updates.nextCheck") as? Date, (3500...3700).contains(retryDate.timeIntervalSinceNow) else { fputs("Update retry was not scheduled\n", stderr); exit(1) }
            do { try checkSurahSelectorInteraction(store.chapters) }
            catch { fputs("Integrated selector interaction failed: \(error)\n", stderr); exit(1) }
            do {
                var scheduledPlan = memorization.plan
                scheduledPlan.enabled = true
                scheduledPlan.nextDue = Date().addingTimeInterval(1)
                try memorization.save(scheduledPlan)
            } catch { fputs("Memorization schedule setup failed: \(error)\n", stderr); exit(1) }
            confirmation.show()
            let settingsProbe = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
            window.beginSheet(settingsProbe) { [weak self] _ in
                Task { @MainActor in self?.scheduleMemorization() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, !self.memorizationWindow.isVisible else { fputs("Memorization interrupted settings\n", stderr); exit(1) }
                self.window.endSheet(settingsProbe)
                settingsProbe.orderOut(nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self, self.window.isVisible, !self.confirmation.isVisible else { fputs("macOS UI launch or toast dismissal failed\n", stderr); exit(1) }
                guard self.memorizationWindow.isVisible else { fputs("Due memorization was blocked by reading\n", stderr); exit(1) }
                self.window.orderOut(nil)
                self.showReminder()
                guard self.window.isVisible, self.memorizationWindow.isVisible else { fputs("Reading was blocked by memorization\n", stderr); exit(1) }
                guard self.window.contentLayoutRect.size == self.memorizationWindow.contentLayoutRect.size else { fputs("Reminder windows have inconsistent dimensions\n", stderr); exit(1) }
                print("macOS UI check passed: independent reading and memorization windows; confirmation dismissed automatically.")
                NSApplication.shared.terminate(nil)
            }
        }
    }
    @objc func showReminder() {
        if store.preferences.nextReadingDue != nil {
            do {
                var next = store.preferences
                next.nextReadingDue = nil
                try store.save(next)
            } catch { store.error = error.localizedDescription; return }
        }
        timer?.invalidate()
        fitReminderWindow(window)
        window.orderFrontRegardless()
    }
    func fitReminderWindow(_ target: NSWindow) {
        if let screen = NSScreen.main {
            let available = screen.visibleFrame
            target.setContentSize(NSSize(width: min(940, available.width - 40), height: min(720, available.height - 80)))
        }
        target.center()
    }
    func hideReminder() {
        do {
            var next = store.preferences
            next.nextReadingDue = Date().addingTimeInterval(TimeInterval(next.interval))
            try store.save(next)
        } catch { store.error = error.localizedDescription; return }
        window.orderOut(nil)
        timer?.invalidate()
        guard store.preferences.index < store.verses.count else { return }
        scheduleReading()
    }
    func scheduleReading() {
        let remaining = store.preferences.nextReadingDue?.timeIntervalSinceNow ?? 0
        timer = Timer.scheduledTimer(withTimeInterval: max(1, min(30, remaining)), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.showDueReading() }
        }
    }
    func showDueReading() {
        if let deadline = store.preferences.nextReadingDue, deadline > Date() { scheduleReading() }
        else { showReminder() }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hideReminder(); return false }
    func scheduleMemorization() {
        memorizationTimer?.invalidate()
        guard memorization.plan.enabled else { return }
        let remaining = (memorizationWindow.isVisible || window.attachedSheet != nil) ? 30 : memorization.plan.nextDue.timeIntervalSinceNow
        memorizationTimer = Timer.scheduledTimer(withTimeInterval: max(1, min(30, remaining)), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.showDueMemorization()
                self?.scheduleMemorization()
            }
        }
    }
    func showDueMemorization() {
        guard memorization.plan.enabled, memorization.plan.nextDue <= Date(), window.attachedSheet == nil, !memorizationWindow.isVisible, !memorization.currentLines.isEmpty else { return }
        fitReminderWindow(memorizationWindow)
        memorizationWindow.orderFrontRegardless()
    }
    @objc func openLatestRelease() {
        NSWorkspace.shared.open(URL(string: "https://github.com/AhmedMohamedAbdEllatif/quran-reminder-windows/releases/latest")!)
    }
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
@MainActor static func require(_ condition: Bool, _ scenario: String) throws {
    if !condition { throw NSError(domain: "QuranReminderChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: scenario]) }
}
@MainActor static func main() {
if CommandLine.arguments.contains("--check") {
    do {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try ReadingStore(folder: temporary)
        try require(store.chapters.count == 114, "Expected all 114 surahs")
        try require(store.background == nil, "Default reminder surface must use the paper color")
        try store.importBackground(Bundle.main.url(forResource: "background", withExtension: "png")!)
        var backgroundChoice = store.preferences
        backgroundChoice.customBackground = true
        try store.save(backgroundChoice)
        try require(store.background != nil, "Custom reminder image did not load")
        let customRestored = try ReadingStore(folder: temporary)
        try require(customRestored.background != nil, "Custom background choice did not survive reopening")
        backgroundChoice.customBackground = false
        try store.save(backgroundChoice)
        let paperRestored = try ReadingStore(folder: temporary)
        try require(paperRestored.background == nil && FileManager.default.fileExists(atPath: temporary.appendingPathComponent("background.png").path), "Restoring default removed the custom image or did not persist")
        for (tag, draft, preview, expected) in [
            ("v1.10.0", false, false, true), ("v1.9.0", false, false, false),
            ("v1.8.9", false, false, false), ("v1.10.0", true, false, false),
            ("v1.10.0", false, true, false), ("v2.0.0-beta", false, false, false)
        ] {
            let release = GitHubRelease(tag_name: tag, html_url: "https://github.com/AhmedMohamedAbdEllatif/quran-reminder-windows/releases/tag/\(tag)", draft: draft, prerelease: preview)
            try require((availableUpdate(release, currentVersion: "1.9.0") != nil) == expected, "Incorrect update selection: \(tag)")
        }
        let externalRelease = GitHubRelease(tag_name: "v9.0.0", html_url: "https://example.com/not-our-release", draft: false, prerelease: false)
        try require(availableUpdate(externalRelease, currentVersion: "1.6.0") == nil, "External update URL was accepted")
        try require(matchingSurahs(store.chapters, query: "مريم").map(\.surah_number) == [19], "Integrated name filtering failed")
        try require(matchingSurahs(store.chapters, query: "19").map(\.surah_number) == [19], "Integrated number filtering failed")
        try require(matchingSurahs(store.chapters, query: "غيرموجود").isEmpty, "Unknown surah must have no matches")
        try require(searchText(store.chapters[0].surah_name).contains(searchText("الفاتحة")), "Unvocalized surah search failed")
        var batch = store.preferences
        batch.count = 3
        try store.save(batch)
        try require(store.displayed.map(\.number) == [1, 2, 3], "Group must contain the first three verses")
        try store.confirm()
        try require(store.preferences.index == 3 && store.preferences.readCount == 3, "Group confirmation must advance by three")
        batch = store.preferences
        batch.index = 6234
        try store.save(batch)
        try require(store.displayed.count == 2, "Final group must contain only two remaining verses")
        try store.confirm()
        try require(store.displayed.isEmpty, "No verses should remain after final confirmation")
        let restored = try ReadingStore(folder: temporary)
        try require(restored.preferences.index == 6236, "Reading position must survive reopening")
        try require(store.verses.allSatisfy { !$0.english.isEmpty && !$0.tafsir.isEmpty }, "Every verse needs translation and tafsir")
        let memorization = try MemorizationStore(folder: temporary)
        var endMarkers = 0
        for line in memorization.pages.flatMap({ $0.lines }) {
            let segments = mushafSegments(line.text)
            try require(segments.map(\.sourceText).joined() == line.text, "Verse ornament changed source text")
            for segment in segments { if case .endNumber = segment { endMarkers += 1 } }
        }
        try require(endMarkers == 6236, "Every ayah must retain its end number")
        for (number, digits) in [(1, "١"), (9, "٩"), (10, "١٠"), (99, "٩٩"), (100, "١٠٠"), (286, "٢٨٦")] {
            try require(arabicVerseNumber(number) == digits, "Arabic verse digits are incorrect")
            for size in [18.0, 64.0] {
                try require(QuranMarkers.image(digits, size: size).tiffRepresentation != nil, "Verse ornament failed to render")
            }
        }
        var plan = memorization.plan
        plan.page = 3; plan.linesPerPart = 4; plan.repeats = 2; plan.interval = 17; plan.enabled = true
        try memorization.save(plan)
        try require(memorization.parts.map { $0.count } == [4,4,4,3], "Page must split into actual Mushaf lines")
        try memorization.hide()
        try require(memorization.plan.completedRepeats == 0, "Hiding must not count a review")
        try memorization.confirm()
        try require(memorization.plan.part == 0 && memorization.plan.completedRepeats == 1, "Part must repeat before advancing")
        try memorization.confirm()
        try require(memorization.plan.part == 1 && store.preferences.index == 6236, "Memorization must not change reading progress")
        plan = memorization.plan; plan.part = 3; plan.completedRepeats = 1
        try memorization.save(plan); try memorization.confirm()
        try require(!memorization.plan.enabled && memorization.plan.part == 4, "Completed memorization plan must stop")
        var scheduledReading = store.preferences
        scheduledReading.nextReadingDue = Date().addingTimeInterval(600)
        try store.save(scheduledReading)
        let reloadedReading = try ReadingStore(folder: store.folder)
        try require(abs((reloadedReading.preferences.nextReadingDue ?? .distantPast).timeIntervalSince(scheduledReading.nextReadingDue!)) < 0.01, "Reading deadline must survive restart")
        let restoredPlan = try MemorizationStore(folder: temporary)
        try require(restoredPlan.plan.part == 4, "Memorization progress must persist")
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
