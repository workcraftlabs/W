import XCTest
@testable import WCore
final class CoreTests: XCTestCase {
    func testProjectDisambiguatesIdenticalTitles() {
        let tasks = [WorkTask(id: "1", title: "Onboarding proposal", project: "Acme"), WorkTask(id: "2", title: "Onboarding proposal", project: "Other")]
        XCTAssertEqual(Matcher.ranked("working on the onboarding proposal for Acme", tasks: tasks).first?.task.id, "1")
    }
    func testTypoAndCompletedExclusion() {
        let tasks = [WorkTask(id: "1", title: "Onboarding proposal"), WorkTask(id: "2", title: "Onboarding proposal", done: true)]
        XCTAssertEqual(Matcher.ranked("onbording", tasks: tasks).map(\.task.id), ["1"])
        XCTAssertTrue(Matcher.ranked("grocery shopping", tasks: tasks).isEmpty)
        XCTAssertTrue(Matcher.ranked("working on the", tasks: tasks).isEmpty)
    }
    func testPauseResumeStopPreservesExactTime() {
        let t = Date(timeIntervalSince1970: 1000)
        var s = WorkSession(task: WorkTask(title: "Test"), now: t)
        s.pause(at: t.addingTimeInterval(61.5))
        XCTAssertEqual(s.elapsed(at: t.addingTimeInterval(400)), 61.5)
        s.resume(at: t.addingTimeInterval(500))
        s.resume(at: t.addingTimeInterval(510))
        s.stop(done: false, at: t.addingTimeInterval(520))
        XCTAssertEqual(s.accumulated, 81.5)
        XCTAssertFalse(s.completed)
        s.resume(at: t.addingTimeInterval(600))
        XCTAssertNil(s.runningSince)
    }
    func testExtensionRelativeToElapsedAndRoundtrip() throws {
        let t = Date(timeIntervalSince1970: 1000)
        var s = WorkSession(task: WorkTask(title: "Test"), now: t)
        s.extend(minutes: 5, at: t.addingTimeInterval(1500))
        XCTAssertEqual(s.checkInAt, 1800)
        var state = SavedState(); state.active = s
        state.pending = [PendingUpdate(pageID: "1", status: "In progress", start: t, settings: NotionSettings())]
        let restored = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored.active, s)
        XCTAssertEqual(restored.pending.first?.start, t)
    }
}
