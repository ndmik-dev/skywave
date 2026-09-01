import Foundation
import SkywaveKit

/// Drives Resilience with a millisecond policy, so the reconnect logic is
/// checked without sleeping a laptop or pulling a cable.
@MainActor
func resilienceChecks() async {
    let fast = Resilience.Policy(
        backoff: [.milliseconds(40), .milliseconds(120)],
        watchdogGrace: .milliseconds(100),
        watchdogPoll: .milliseconds(20),
        maxAttempts: 3
    )

    await check("reconnects after a stall") { resilience, reasons in
        resilience.noteStarted()
        resilience.noteStalled()
        try? await Task.sleep(for: .milliseconds(120))
        return reasons.value == [.stalled]
    }

    await check("does not reconnect when nothing was requested") { resilience, reasons in
        resilience.noteStalled()
        try? await Task.sleep(for: .milliseconds(120))
        return reasons.value.isEmpty
    }

    await check("a stop cancels a pending reconnect") { resilience, reasons in
        resilience.noteStarted()
        resilience.noteFailed()
        resilience.noteStopped()
        try? await Task.sleep(for: .milliseconds(120))
        return reasons.value.isEmpty
    }

    await check("backs off further on a second failure") { resilience, reasons in
        resilience.noteStarted()
        resilience.noteFailed()
        try? await Task.sleep(for: .milliseconds(80))
        resilience.noteFailed()
        // The second delay is 120ms, so nothing has fired yet at 60ms.
        try? await Task.sleep(for: .milliseconds(60))
        let backedOff = reasons.value.count == 1
        try? await Task.sleep(for: .milliseconds(120))
        return backedOff && reasons.value.count == 2
    }

    await check("confirmed playback resets the backoff") { resilience, reasons in
        resilience.noteStarted()
        resilience.noteFailed()
        try? await Task.sleep(for: .milliseconds(80))
        resilience.notePlaying()
        resilience.noteFailed()
        // Back to the 40ms delay rather than escalating to 120ms.
        try? await Task.sleep(for: .milliseconds(80))
        return reasons.value.count == 2
    }

    await check("gives up rather than retrying a dead station forever") { resilience, reasons in
        resilience.noteStarted()
        for _ in 0..<8 {
            resilience.noteFailed()
            try? await Task.sleep(for: .milliseconds(60))
        }
        // Two delays in the policy, three attempts allowed by the check below.
        return reasons.value.count <= 3
    }

    await check("the watchdog fires when playback never starts") { resilience, reasons in
        resilience.noteStarted()
        try? await Task.sleep(for: .milliseconds(300))
        return reasons.value.contains(.watchdog)
    }

    await check("no watchdog while playing") { resilience, reasons in
        resilience.noteStarted()
        resilience.notePlaying()
        try? await Task.sleep(for: .milliseconds(300))
        return reasons.value.isEmpty
    }

    @MainActor
    func check(
        _ name: String,
        _ body: (Resilience, Recorder) async -> Bool
    ) async {
        let resilience = Resilience(policy: fast)
        let reasons = Recorder()
        resilience.onReconnect = { reason, _ in reasons.value.append(reason) }
        resilience.start()
        let passed = await body(resilience, reasons)
        resilience.stop()
        Expect.suite("resilience") { Expect.that(passed, name) }
    }
}

/// Collects the reasons a run reconnected for.
@MainActor
final class Recorder {
    var value: [ReconnectReason] = []
}
