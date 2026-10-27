import AppKit
import SwiftUI

struct MushafLine: Decodable, Identifiable {
    let number: Int
    let text: String
    let references: [String]
    var id: Int { number }
}
struct MushafPage: Decodable, Identifiable {
    let number: Int
    let lines: [MushafLine]
    var id: Int { number }
}
struct MushafLayout: Decodable { let pages: [MushafPage] }
struct MemorizationPlan: Codable {
    var enabled = false
    var page = 1
    var linesPerPart = 5
    var repeats = 3
    var interval = 300
    var part = 0
    var completedRepeats = 0
    var nextDue = Date()
}
@MainActor final class MemorizationStore: ObservableObject {
    let pages: [MushafPage]
    var scheduleChanged: (() -> Void)?
    private let stateFile: URL
    @Published private(set) var plan: MemorizationPlan
    var parts: [[MushafLine]] { chunks(for: plan) }
    var currentLines: [MushafLine] { plan.part < parts.count ? parts[plan.part] : [] }
    init(folder: URL) throws {
        guard let resource = Bundle.main.url(forResource: "mushaf-lines", withExtension: "json") else {
            throw NSError(domain: "Memorization", code: 1, userInfo: [NSLocalizedDescriptionKey: "بيانات أسطر المصحف غير موجودة"])
        }
        pages = try JSONDecoder().decode(MushafLayout.self, from: Data(contentsOf: resource)).pages
        guard pages.count == 604, pages.enumerated().allSatisfy({ $0.element.number == $0.offset + 1 && !$0.element.lines.isEmpty }) else {
            throw NSError(domain: "Memorization", code: 2, userInfo: [NSLocalizedDescriptionKey: "بيانات الصفحات غير كاملة"])
        }
        stateFile = folder.appendingPathComponent("memorization.json")
        plan = FileManager.default.fileExists(atPath: stateFile.path) ? try JSONDecoder().decode(MemorizationPlan.self, from: Data(contentsOf: stateFile)) : MemorizationPlan()
        try validate(plan)
    }
    func chunks(for candidate: MemorizationPlan) -> [[MushafLine]] {
        let lines = pages[candidate.page - 1].lines
        return stride(from: 0, to: lines.count, by: candidate.linesPerPart).map {
            Array(lines[$0..<min($0 + candidate.linesPerPart, lines.count)])
        }
    }
    func validate(_ candidate: MemorizationPlan) throws {
        guard (1...604).contains(candidate.page), (1...15).contains(candidate.linesPerPart),
              (1...1000).contains(candidate.repeats), (1...86400).contains(candidate.interval),
              candidate.part >= 0, candidate.completedRepeats >= 0, candidate.completedRepeats < candidate.repeats else {
            throw NSError(domain: "Memorization", code: 3, userInfo: [NSLocalizedDescriptionKey: "راجع الصفحة والأسطر والتكرارات والوقت"])
        }
        guard candidate.part <= chunks(for: candidate).count else {
            throw NSError(domain: "Memorization", code: 4, userInfo: [NSLocalizedDescriptionKey: "موضع الحفظ غير صحيح"])
        }
    }
    func save(_ candidate: MemorizationPlan) throws {
        try validate(candidate)
        try JSONEncoder().encode(candidate).write(to: stateFile, options: .atomic)
        plan = candidate
        scheduleChanged?()
    }
    func confirm() throws {
        guard !currentLines.isEmpty else { return }
        var next = plan
        next.completedRepeats += 1
        if next.completedRepeats == next.repeats { next.part += 1; next.completedRepeats = 0 }
        if next.part == parts.count { next.enabled = false }
        next.nextDue = Date().addingTimeInterval(TimeInterval(next.interval))
        try save(next)
    }
    func hide() throws {
        var next = plan
        next.nextDue = Date().addingTimeInterval(TimeInterval(next.interval))
        try save(next)
    }
    func pages(for chapter: Int) -> [MushafPage] {
        pages.filter { $0.lines.contains { $0.references.contains { $0.hasPrefix("\(chapter):") } } }
    }
}
struct MemorizationSessionView: View {
    @ObservedObject var store: MemorizationStore
    @ObservedObject var appearance: ReadingStore
    let dismissWindow: () -> Void
    @State private var failure: String?
    private var selectedText: String { store.currentLines.map(\.text).joined(separator: " ") }
    var body: some View {
        VStack(spacing: 20) {
            Text("حفظ صفحة \(store.plan.page) · الجزء \(store.plan.part + 1) من \(store.parts.count)").font(.title2.weight(.semibold))
            Text("المراجعة \(store.plan.completedRepeats + 1) من \(store.plan.repeats) · مقطع من أسطر المصحف").font(.caption).foregroundStyle(ReminderPalette.secondary)
            ScrollView {
                mushafLineText(selectedText, size: appearance.preferences.fontSize)
                    .accessibilityLabel(selectedText)
                    .font(.custom("AmiriQuran-Regular", size: appearance.preferences.fontSize))
                    .multilineTextAlignment(.center).frame(maxWidth: 900)
                    .padding(.horizontal, 12).frame(maxWidth: .infinity)
            }
            Text("قد يبدأ المقطع أو ينتهي داخل آية. التكرار مستقل عن تقدم القراءة.").font(.caption).foregroundStyle(ReminderPalette.secondary)
            HStack {
                Button("✓ تمت المراجعة") { do { try store.confirm(); dismissWindow() } catch { failure = error.localizedDescription } }.buttonStyle(.borderedProminent).foregroundStyle(.white)
                Button("إخفاء دون تسجيل") { do { try store.hide(); dismissWindow() } catch { failure = error.localizedDescription } }
            }.controlSize(.large)
            if let failure { Text(failure).foregroundStyle(.red) }
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(ReminderPalette.ink).background { ReminderSurface(store: appearance) }
            .preferredColorScheme(.light).tint(ReminderPalette.accent)
            .environment(\.layoutDirection, .rightToLeft)
    }
}
struct MemorizationSettingsView: View {
    @ObservedObject var store: MemorizationStore
    let chapters: [Verse]
    let saved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MemorizationPlan
    @State private var chapter: Int
    @State private var restart = false
    @State private var intervalText: String
    @State private var unit = 0
    @State private var failure: String?
    @State private var surahValid = true
    init(store: MemorizationStore, chapters: [Verse], saved: @escaping () -> Void) {
        self.store = store; self.chapters = chapters
        self.saved = saved
        var initialPlan = store.plan
        initialPlan.enabled = true
        _draft = State(initialValue: initialPlan)
        let firstKey = store.pages[store.plan.page - 1].lines.first?.references.first ?? "1:1"
        _chapter = State(initialValue: Int(firstKey.split(separator: ":")[0]) ?? 1)
        _intervalText = State(initialValue: String(store.plan.interval))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("خطة حفظ مستقلة").font(.title.bold())
            Text("توقيت منفصل عن القراءة. التكرار يُسجل عند ضغط تمت المراجعة.").foregroundStyle(.secondary)
            Form {
                SurahSelector(chapters: chapters, selection: $chapter, validSelection: $surahValid).frame(height: 32)
                    .onChange(of: chapter) { _ in if let first = store.pages(for: chapter).first { draft.page = first.number } }
                Picker("الصفحة — مصحف المدينة", selection: $draft.page) { ForEach(store.pages(for: chapter)) { Text("الصفحة \($0.number)").tag($0.number) } }
                Stepper("عدد الأسطر في كل جزء: \(draft.linesPerPart)", value: $draft.linesPerPart, in: 1...15)
                Stepper("مرات مراجعة كل جزء: \(draft.repeats)", value: $draft.repeats, in: 1...1000)
                TextField("الفاصل الزمني", text: $intervalText)
                Picker("وحدة الوقت", selection: $unit) { Text("ثوانٍ").tag(0); Text("دقائق").tag(1); Text("ساعات").tag(2) }
                Toggle("ابدأ الخطة من أول الصفحة", isOn: $restart)
                Toggle("تفعيل التذكير بالحفظ", isOn: $draft.enabled)
                Text("الجزء الحالي: \(store.plan.part + 1) · المراجعات المكتملة: \(store.plan.completedRepeats)").font(.caption)
            }.formStyle(.grouped)
            if let failure { Text(failure).foregroundStyle(.red) }
            HStack { Button(draft.enabled ? "حفظ وتشغيل الخطة" : "حفظ الخطة بدون تشغيل", action: apply).buttonStyle(.borderedProminent); Button("إلغاء") { dismiss() } }.controlSize(.large)
        }.padding(24).environment(\.layoutDirection, .rightToLeft)
    }
    func apply() {
        do {
            guard surahValid else { failure = "اختَر سورة من نتائج البحث"; return }
            guard let enteredInterval = Double(intervalText), enteredInterval.isFinite else { failure = "اكتب وقتًا صحيحًا"; return }
            let seconds = enteredInterval * [1.0, 60.0, 3600.0][unit]
            guard (1...86400).contains(seconds) else { failure = "اختَر وقتًا من ثانية إلى ٢٤ ساعة"; return }
            draft.interval = Int(seconds.rounded())
            if restart || draft.page != store.plan.page || draft.linesPerPart != store.plan.linesPerPart || draft.repeats != store.plan.repeats { draft.part = 0; draft.completedRepeats = 0 }
            if draft.enabled && draft.part >= store.chunks(for: draft).count { failure = "الخطة مكتملة. فعّل البدء من أول الصفحة"; return }
            draft.nextDue = Date().addingTimeInterval(TimeInterval(draft.interval))
            try store.save(draft)
            dismiss()
            saved()
        } catch { failure = error.localizedDescription }
    }
}
