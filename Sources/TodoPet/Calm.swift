import CoreGraphics
import Foundation

/// How the pet avoids breaking your concentration. Based on interruption research:
/// - Interrupting at a natural pause instead of mid-task lowers frustration and resumption time
///   (Adamczyk & Bailey 2004; Iqbal & Bailey 2008).
/// - Fewer, batched notifications improve attention and well-being (Fitz et al. 2019).
/// - Motion at the edge of vision grabs attention, so the pet keeps still while you type (Bartram et al. 2003).
/// - Calm technology: stay in the periphery and only move to the center when it matters (Weiser & Brown 1996).
enum CalmRules {
    /// Typing within this many seconds means you're in the middle of something.
    static let typingWindow: Double = 8
    /// Steady typing for this long counts as "being in the zone"; non-urgent bubbles wait.
    static let flowMinutes: Double = 10
    /// Two minutes without a keystroke ends the zone.
    static let flowEndsAfter: Double = 120

    /// You're actively working: typing recently, at the computer, and not in a distracting app or site.
    static func engaged(secondsSinceKey: Double, idleSeconds: Double, distracted: Bool) -> Bool {
        secondsSinceKey < 45 && idleSeconds < 60 && !distracted
    }

    /// When engaged work started (nil when you're not engaged), with a little hysteresis so short pauses don't reset it.
    static func engagedSince(_ current: Date?, engaged: Bool, secondsSinceKey: Double, now: Date) -> Date? {
        if engaged { return current ?? now }
        return secondsSinceKey > flowEndsAfter ? nil : current
    }

    static func inFlow(engagedSince: Date?, now: Date, minutes: Double = flowMinutes) -> Bool {
        guard let start = engagedSince else { return false }
        return now.timeIntervalSince(start) >= minutes * 60
    }

    /// A natural pause: you stopped typing for a moment, or just switched apps.
    static func atBreakpoint(secondsSinceKey: Double, secondsSinceAppSwitch: Double) -> Bool {
        secondsSinceKey >= typingWindow || secondsSinceAppSwitch < 10
    }

    /// Unsolicited bubbles are spaced out: at most one per `minGap` minutes.
    static func withinBudget(lastBubbleAt: Date, now: Date, minGap: Double) -> Bool {
        now.timeIntervalSince(lastBubbleAt) >= minGap * 60
    }

    static func secondsSinceKey() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
    }
}
