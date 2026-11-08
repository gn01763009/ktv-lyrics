@testable import KTVCore
import Testing

@Suite struct RestartPolicyTests {
    @Test func backoffDoublesAndCaps() {
        #expect((0...6).map(RestartPolicy.delay) == [1, 2, 4, 8, 16, 30, 30])
    }

    @Test func hugeAttemptsStayCapped() {
        #expect(RestartPolicy.delay(attempt: 10_000) == 30)
        #expect(RestartPolicy.delay(attempt: -3) == 1)
    }
}
