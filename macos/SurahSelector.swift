import AppKit
import SwiftUI

func matchingSurahs(_ chapters: [Verse], query: String) -> [Verse] {
    let normalized = searchText(query.trimmingCharacters(in: .whitespacesAndNewlines))
    return chapters.filter { normalized.isEmpty || searchText($0.surah_name).contains(normalized) || String($0.surah_number) == normalized }
}

struct SurahSelector: NSViewRepresentable {
    let chapters: [Verse]
    @Binding var selection: Int
    @Binding var validSelection: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSComboBox {
        let combo = NSComboBox()
        combo.usesDataSource = true
        combo.dataSource = context.coordinator
        combo.delegate = context.coordinator
        combo.isEditable = true
        combo.completes = false
        combo.hasVerticalScroller = true
        combo.numberOfVisibleItems = 10
        combo.font = .systemFont(ofSize: 16)
        combo.alignment = .right
        combo.placeholderString = "اكتب اسم السورة أو اخترها"
        combo.setAccessibilityLabel("السورة — اكتب الاسم للبحث")
        return combo
    }
    func updateNSView(_ combo: NSComboBox, context: Context) {
        context.coordinator.parent = self
        guard !context.coordinator.editing else { return }
        context.coordinator.results = chapters
        combo.reloadData()
        combo.stringValue = chapters.first(where: { $0.surah_number == selection })?.surah_name ?? ""
    }
    final class Coordinator: NSObject, NSComboBoxDataSource, NSComboBoxDelegate {
        var parent: SurahSelector
        var results: [Verse]
        var editing = false
        init(_ parent: SurahSelector) { self.parent = parent; results = parent.chapters }
        func numberOfItems(in comboBox: NSComboBox) -> Int { results.count }
        func comboBox(_ comboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? { results[index].surah_name }
        func controlTextDidChange(_ notification: Notification) {
            guard let combo = notification.object as? NSComboBox else { return }
            editing = true
            let typed = combo.stringValue
            results = matchingSurahs(parent.chapters, query: typed)
            combo.reloadData()
            combo.stringValue = typed
            parent.validSelection = false
        }
        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let combo = notification.object as? NSComboBox, results.indices.contains(combo.indexOfSelectedItem) else { return }
            let verse = results[combo.indexOfSelectedItem]
            editing = false
            combo.stringValue = verse.surah_name
            parent.selection = verse.surah_number
            parent.validSelection = true
        }
    }
}

struct SaveConfirmationView: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 36)).foregroundStyle(Color(red: 0.14, green: 0.35, blue: 0.42))
            VStack(alignment: .leading, spacing: 5) {
                Text("تم حفظ الخطة").font(.system(size: 18, weight: .semibold))
                Text("إعدادات الحفظ والمراجعة اتحفظت.").font(.system(size: 14)).foregroundStyle(.secondary)
            }
        }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.96, green: 0.98, blue: 0.98))
            .foregroundStyle(Color(red: 0.10, green: 0.24, blue: 0.29))
            .cornerRadius(16).environment(\.layoutDirection, .rightToLeft)
    }
}

@MainActor final class SaveConfirmationController {
    private var panel: NSPanel?
    private var dismissal: DispatchWorkItem?
    var isVisible: Bool { panel?.isVisible ?? false }
    func show() {
        dismissal?.cancel()
        panel?.close()
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let toast = NSPanel(contentRect: NSRect(x: frame.maxX - 450, y: frame.minY + 24, width: 420, height: 110), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        toast.isReleasedWhenClosed = false
        toast.isOpaque = false
        toast.backgroundColor = .clear
        toast.hasShadow = true
        toast.level = .floating
        toast.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        toast.contentView = NSHostingView(rootView: SaveConfirmationView())
        toast.orderFrontRegardless()
        panel = toast
        let work = DispatchWorkItem { [weak toast] in toast?.close() }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }
}
