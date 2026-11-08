import Foundation
import KTVCore
import os

public enum AdapterStatus: Equatable, Sendable {
    case running
    case restarting(attempt: Int)
    case failed
}

/// Runs the now-playing helper and restarts it with backoff when it exits.
/// Call `start()` and `stop()` from the main thread; callbacks arrive on the main queue.
public final class AdapterProcess {
    private static let logger = Logger(subsystem: "KTVLyrics", category: "AdapterProcess")
    private static let maxConsecutiveFailures = 8
    /// Seconds the helper must stay up before its earlier failures are forgotten. It prints a row as soon as it
    /// starts, so receiving a row says nothing about whether it is healthy.
    public static let stableUptimeSeconds: Double = 30
    private static let newline = UInt8(ascii: "\n")

    private let executable: String
    private let arguments: [String]
    private let onEvent: (AdapterEvent) -> Void
    private let onStatus: (AdapterStatus) -> Void
    private let restartDelay: (Int) -> Double
    private let stableUptime: Double

    private var process: Process?
    private var generation = 0
    private var consecutiveFailures = 0
    private var stopped = true
    private var launchedAt: Date?

    public init(
        executable: String,
        arguments: [String],
        onEvent: @escaping (AdapterEvent) -> Void,
        onStatus: @escaping (AdapterStatus) -> Void,
        restartDelay: @escaping (Int) -> Double = RestartPolicy.delay,
        stableUptime: Double = AdapterProcess.stableUptimeSeconds
    ) {
        self.executable = executable
        self.arguments = arguments
        self.onEvent = onEvent
        self.onStatus = onStatus
        self.restartDelay = restartDelay
        self.stableUptime = stableUptime
    }

    public func start() {
        guard stopped else { return }
        stopped = false
        consecutiveFailures = 0
        launch()
    }

    public func stop() {
        stopped = true
        generation += 1
        let running = process
        process = nil
        running?.terminationHandler = nil
        if running?.isRunning == true { running?.terminate() }
    }

    private func launch() {
        generation += 1
        let token = generation
        let child = Process()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = arguments
        let pipe = Pipe()
        child.standardOutput = pipe
        child.standardError = FileHandle.nullDevice
        do {
            try child.run()
        } catch {
            Self.logger.error("Cannot launch \(self.executable, privacy: .public): \(error.localizedDescription, privacy: .public)")
            handleExit(token: token)
            return
        }
        process = child
        launchedAt = Date()
        onStatus(.running)
        read(pipe.fileHandleForReading, token: token)
    }

    private func read(_ handle: FileHandle, token: Int) {
        var buffer = Data()
        handle.readabilityHandler = { [weak self] file in
            let chunk = file.availableData
            if chunk.isEmpty {
                file.readabilityHandler = nil
                let rest = buffer
                DispatchQueue.main.async {
                    if !rest.isEmpty { self?.deliver(rest, token: token) }
                    self?.handleExit(token: token)
                }
                return
            }
            buffer.append(chunk)
            var lines: [Data] = []
            while let end = buffer.firstIndex(of: Self.newline) {
                lines.append(buffer.subdata(in: buffer.startIndex..<end))
                buffer.removeSubrange(buffer.startIndex...end)
            }
            guard !lines.isEmpty else { return }
            DispatchQueue.main.async { lines.forEach { self?.deliver($0, token: token) } }
        }
    }

    private func deliver(_ line: Data, token: Int) {
        guard token == generation, !line.isEmpty else { return }
        switch AdapterMessage.parse(line) {
        case .ignored:
            Self.logger.debug("Ignored adapter row: \(String(decoding: line, as: UTF8.self), privacy: .public)")
        case let event:
            onEvent(event)
        }
    }

    /// A helper that ran for `stableUptime` seconds was healthy, so its exit starts the backoff from the beginning.
    private func forgetFailuresIfItStayedUp() {
        defer { launchedAt = nil }
        guard let launchedAt, Date().timeIntervalSince(launchedAt) >= stableUptime else { return }
        consecutiveFailures = 0
    }

    private func handleExit(token: Int) {
        guard token == generation, !stopped else { return }
        process = nil
        forgetFailuresIfItStayedUp()
        let attempt = consecutiveFailures
        consecutiveFailures += 1
        guard consecutiveFailures < Self.maxConsecutiveFailures else {
            Self.logger.error("Adapter failed \(self.consecutiveFailures) times in a row; giving up")
            stopped = true
            onStatus(.failed)
            return
        }
        onStatus(.restarting(attempt: attempt))
        DispatchQueue.main.asyncAfter(deadline: .now() + restartDelay(attempt)) { [weak self] in
            guard let self, !self.stopped, token == self.generation else { return }
            self.launch()
        }
    }
}
