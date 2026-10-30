import Foundation

/// Little gestures that make the pet feel alive. None of them play while you type, focus or are in a meeting.
struct PetGesture: Equatable {
    enum Kind: Equatable {
        /// You came back after a while.
        case wave
        /// Nothing going on for a while.
        case yawn
        /// Shaking itself off after being dragged.
        case shake
        /// A few quick pats (clicks).
        case giggle
        /// Too many pats.
        case dizzy
    }

    var kind: Kind
    var start: Date

    var duration: Double {
        switch kind {
        case .wave: 2.4
        case .yawn: 2.6
        case .shake: 0.9
        case .giggle: 1.6
        case .dizzy: 2.8
        }
    }

    /// 0…1 through the gesture, nil once it's over.
    func progress(at t: Date) -> Double? {
        let p = t.timeIntervalSince(start) / duration
        return p >= 0 && p < 1 ? p : nil
    }
}
