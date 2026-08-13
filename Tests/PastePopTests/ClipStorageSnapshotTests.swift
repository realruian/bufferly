import Testing
@testable import PastePop

@Suite("ClipStorageSnapshot")
struct ClipStorageSnapshotTests {
    @Test("存储摘要包含历史数量、当前附件和容量上限")
    func formatsCompactSummary() {
        let snapshot = ClipStorageSnapshot(
            clipCount: 12,
            attachmentBytes: 1_024 * 1_024
        )

        #expect(snapshot.summary.contains("12 条"))
        #expect(snapshot.summary.contains("1 MB"))
        #expect(snapshot.summary.contains("200 MB"))
    }
}
