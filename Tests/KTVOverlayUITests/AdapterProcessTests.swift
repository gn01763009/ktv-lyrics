import Foundation
import KTVCore
@testable import KTVOverlayUI
import Testing

@Suite struct AdapterProcessTests {
    private let json = #"{"type":"data","diff":false,"payload":{"title":"簡單愛","artist":"周杰倫","durationMicros":270987000,"elapsedTimeMicros":100005000,"timestampEpochMicros":1000000000000,"playbackRate":1,"playing":true,"bundleIdentifier":"com.spotify.client"}}"#

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storedEvents: [AdapterEvent] = []
        private var storedStatuses: [AdapterStatus] = []
        var events: [AdapterEvent] { lock.withLock { storedEvents } }
        var statuses: [AdapterStatus] { lock.withLock { storedStatuses } }
        func add(_ event: AdapterEvent) { lock.withLock { storedEvents.append(event) } }
        func add(_ status: AdapterStatus) { lock.withLock { storedStatuses.append(status) } }
    }

    private func make(
        _ executable: String,
        _ arguments: [String],
        recorder: Recorder
    ) -> AdapterProcess {
        AdapterProcess(
            executable: executable,
            arguments: arguments,
            onEvent: recorder.add,
            onStatus: recorder.add,
            restartDelay: { _ in 0.01 }
        )
    }

    // Generous: main-actor rendering tests in this target can keep the main queue busy for seconds.
    private func waitUntil(timeout: Double = 30, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    @Test @MainActor func deliversEventsThenRestarts() async {
        let recorder = Recorder()
        let process = make("/bin/sh", ["-c", "printf '%s\\n' '\(json)'; exit 1"], recorder: recorder)
        process.start()
        let seen = await waitUntil {
            recorder.statuses.contains(.restarting(attempt: 0))
                && recorder.events.contains { if case .playing = $0 { return true } else { return false } }
        }
        process.stop()
        #expect(seen)
        #expect(recorder.statuses.first == .running)
    }

    @Test @MainActor func missingExecutableReportsFailure() async {
        let recorder = Recorder()
        let process = make("/no/such", [], recorder: recorder)
        process.start()
        let seen = await waitUntil {
            recorder.statuses.contains { if case .restarting = $0 { return true } else { return $0 == .failed } }
        }
        process.stop()
        #expect(seen)
    }

    @Test @MainActor func missingExecutableEventuallyFails() async {
        let recorder = Recorder()
        let process = make("/no/such", [], recorder: recorder)
        process.start()
        let failed = await waitUntil { recorder.statuses.contains(.failed) }
        process.stop()
        #expect(failed)
        #expect(recorder.statuses.filter { if case .restarting = $0 { return true } else { return false } }.count == 7)
    }

    @Test @MainActor func deliveredEventResetsFailureCount() async {
        let recorder = Recorder()
        let process = make("/bin/sh", ["-c", "printf '%s\\n' '\(json)'; exit 1"], recorder: recorder)
        process.start()
        let seen = await waitUntil { recorder.statuses.filter { $0 == .running }.count >= 12 }
        process.stop()
        #expect(seen)
        #expect(!recorder.statuses.contains(.failed))
        #expect(!recorder.statuses.contains(.restarting(attempt: 1)))
    }

    @Test @MainActor func stopPreventsRestart() async {
        let recorder = Recorder()
        let process = make("/bin/sh", ["-c", "sleep 30"], recorder: recorder)
        process.start()
        _ = await waitUntil { recorder.statuses.contains(.running) }
        process.stop()
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(!recorder.statuses.contains { if case .restarting = $0 { return true } else { return false } })
        #expect(!recorder.statuses.contains(.failed))
    }
}
