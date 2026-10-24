import AppKit
import SwiftUI

struct ReleaseVersion: Comparable {
    let components: [Int]
    init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        components = numbers
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
}
struct GitHubRelease: Decodable {
    let tag_name: String
    let html_url: String
    let draft: Bool
    let prerelease: Bool
}
struct AvailableUpdate {
    let tag: String
    let url: URL
}
func availableUpdate(_ release: GitHubRelease, currentVersion: String) -> AvailableUpdate? {
    guard !release.draft, !release.prerelease, release.tag_name.first == "v",
          let candidate = ReleaseVersion(String(release.tag_name.dropFirst())),
          let installed = ReleaseVersion(currentVersion), candidate > installed else { return nil }
    let expected = "https://github.com/AhmedMohamedAbdEllatif/quran-reminder-windows/releases/tag/\(release.tag_name)"
    guard release.html_url == expected, let url = URL(string: expected) else { return nil }
    return AvailableUpdate(tag: release.tag_name, url: url)
}
struct UpdateNoticeView: View {
    let release: AvailableUpdate
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("نسخة جديدة من تذكير القرآن").font(.system(size: 20, weight: .semibold))
            Text("الإصدار \(release.tag) متاح. إعداداتك وتقدمك محفوظان عند التحديث.").font(.system(size: 15)).foregroundStyle(.secondary)
            HStack {
                Button("تحميل التحديث") { NSWorkspace.shared.open(release.url); close() }.buttonStyle(.borderedProminent)
                Button("إغلاق", action: close).buttonStyle(.bordered)
            }.controlSize(.large)
        }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.96, green: 0.98, blue: 0.98))
            .foregroundStyle(Color(red: 0.10, green: 0.24, blue: 0.29))
            .tint(Color(red: 0.14, green: 0.35, blue: 0.42))
            .cornerRadius(16).environment(\.layoutDirection, .rightToLeft)
            .preferredColorScheme(.light)
    }
}
@MainActor final class UpdateChecker {
    private let defaults: UserDefaults
    private var initialCheck: Timer?
    private var checkTimer: Timer?
    private var checking = false
    private var notice: NSPanel?
    private var dismissal: DispatchWorkItem?
    var isNoticeVisible: Bool { notice?.isVisible ?? false }
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func start() {
        initialCheck = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
        checkTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }
    func check() async {
        guard !checking else { return }
        if let next = defaults.object(forKey: "updates.nextCheck") as? Date, next > Date(), next.timeIntervalSinceNow <= 86400 { return }
        checking = true
        defer { checking = false }
        let endpoint = URL(string: "https://api.github.com/repos/AhmedMohamedAbdEllatif/quran-reminder-windows/releases/latest")!
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("QuranReminder/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, bytes.count <= 262144 else { retryLater("HTTP response unavailable"); return }
            accept(try JSONDecoder().decode(GitHubRelease.self, from: bytes))
        } catch let error as URLError { retryLater(error.localizedDescription) }
        catch let error as DecodingError { retryLater(String(describing: error)) }
        catch { retryLater("Unexpected update response: \(error)") }
    }
    func retryLater(_ reason: String) {
        defaults.set(Date().addingTimeInterval(3600), forKey: "updates.nextCheck")
        NSLog("Update check unavailable; reading remains active: %@", reason)
    }
    func accept(_ release: GitHubRelease) {
        defaults.set(Date().addingTimeInterval(86400), forKey: "updates.nextCheck")
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        guard let available = availableUpdate(release, currentVersion: current), defaults.string(forKey: "updates.notifiedTag") != available.tag else { return }
        show(available)
        defaults.set(available.tag, forKey: "updates.notifiedTag")
    }
    func dismissNotice() { dismissal?.cancel(); notice?.close() }
    private func show(_ release: AvailableUpdate) {
        dismissNotice()
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let width = min(420, frame.width - 36)
        let panel = NSPanel(contentRect: NSRect(x: frame.maxX - width - 18, y: frame.minY + 24, width: width, height: 204), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: UpdateNoticeView(release: release, close: { [weak self] in self?.dismissNotice() }))
        notice = panel
        panel.orderFrontRegardless()
        let work = DispatchWorkItem { [weak panel] in panel?.close() }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
    }
}
