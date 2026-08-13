import Foundation
import Testing
@testable import PastePop

@Suite("AppSettings")
struct AppSettingsTests {
    @Test("暂停记录支持定时和手动恢复")
    @MainActor
    func pausesAndResumesCapture() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let now = Date()

        settings.pauseCapture(for: .fifteenMinutes, now: now)
        #expect(settings.isCapturePaused)
        #expect(settings.capturePauseUntil == now.addingTimeInterval(15 * 60))

        settings.resumeCapture()
        #expect(!settings.isCapturePaused)
        #expect(settings.capturePauseUntil == nil)
    }

    @Test("固定内容分组会去空格并持久化")
    @MainActor
    func storesPinGroups() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        let group = settings.createPinGroup(named: "  工作  ")
        #expect(group?.name == "工作")
        #expect(settings.createPinGroup(named: "工作")?.id == group?.id)

        let restored = AppSettings(defaults: defaults)
        #expect(restored.pinGroups == settings.pinGroups)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "PastePopTests.AppSettings.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}
