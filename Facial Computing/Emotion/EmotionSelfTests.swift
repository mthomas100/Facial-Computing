//
//  EmotionSelfTests.swift
//  Facial Computing
//
//  Debug-build sanity checks for the pure emotion math (classifier prototypes
//  and temporal hysteresis), executed once at launch. Failures trap in debug
//  so regressions are caught the moment the app starts.
//

import Foundation

#if os(visionOS) && DEBUG

enum EmotionSelfTests {

    static func runAll() {
        classifierPrototypes()
        temporalHysteresis()
        distributionMath()
        print("✅ EmotionSelfTests: all checks passed")
    }

    private static func classifierPrototypes() {
        let cases: [(AUVector, Emotion)] = [
            ([.au12: 0.8, .au6: 0.5], .happiness),
            ([.au1: 0.6, .au2: 0.7, .au5: 0.7, .au26: 0.6], .surprise),
            ([.au4: 0.7, .au7: 0.5, .au23: 0.6], .anger),
            ([.au15: 0.6, .au1: 0.4, .au4: 0.3], .sadness),
            ([.au9: 0.7, .au15: 0.3, .au7: 0.2], .disgust),
            ([.au1: 0.5, .au2: 0.5, .au4: 0.5, .au5: 0.6, .au20: 0.6, .au26: 0.3], .fear),
            ([.auUnilateral: 0.7, .au23: 0.2], .contempt),
            ([:], .neutral),
        ]
        for (au, expected) in cases {
            let result = EmotionClassifier.classify(au).dominant.emotion
            assert(
                result == expected,
                "EmotionSelfTests: AU vector \(au) classified as \(result), expected \(expected)"
            )
        }
    }

    private static func temporalHysteresis() {
        var smoother = TemporalSmoother()
        let happy = EmotionDistribution(normalizing: [.happiness: 0.9, .neutral: 0.1])

        // A single frame must NOT flip the stable label (hysteresis).
        let afterOne = smoother.update(with: happy).dominant
        assert(afterOne == .neutral, "EmotionSelfTests: label flipped after a single frame")

        // A sustained signal must flip it within ~10 frames.
        var final: Emotion = afterOne
        for _ in 0..<10 {
            final = smoother.update(with: happy).dominant
        }
        assert(final == .happiness, "EmotionSelfTests: sustained happiness not adopted, got \(final)")
    }

    private static func distributionMath() {
        let d = EmotionDistribution(normalizing: [.happiness: 2, .neutral: 2])
        assert(abs(d[.happiness] - 0.5) < 1e-9, "EmotionSelfTests: normalization broken")

        let fused = d.fused(with: EmotionDistribution(normalizing: [.happiness: 1]), weight: 0.5)
        assert(fused.dominant.emotion == .happiness, "EmotionSelfTests: fusion broken")

        let va = EmotionDistribution(normalizing: [.happiness: 1]).valenceArousal
        assert(va.valence > 0.5, "EmotionSelfTests: valence anchor broken")
    }
}
#endif
