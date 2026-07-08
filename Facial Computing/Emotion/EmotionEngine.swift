//
//  EmotionEngine.swift
//  Facial Computing
//
//  The emotion-recognition orchestrator. Per frame:
//    camera frame → Vision landmarks → roll/scale-invariant metrics
//    → calibrated FACS Action Units → EMFACS emotion scores
//    (× optional Core ML appearance expert, log-linear fusion)
//    → temporal smoothing with hysteresis → published EmotionReading.
//
//  Accuracy pillars: per-user neutral-baseline calibration (auto on first
//  face, re-runnable), pose/confidence quality gating, and slow baseline
//  drift correction while the face is verifiably neutral.
//

import Foundation
import CoreVideo
import CoreGraphics
import SwiftUI

#if os(visionOS)

@MainActor
@Observable
final class EmotionEngine {

    enum CalibrationPhase: Equatable {
        case idle
        case collecting(progress: Double)
    }

    // MARK: - Published outputs

    private(set) var reading: EmotionReading = .empty
    private(set) var auVector: AUVector = [:]
    private(set) var overlay: FaceOverlayData?
    private(set) var processedFPS: Double = 0
    private(set) var history: [EmotionSample] = []
    private(set) var calibrationPhase: CalibrationPhase = .idle
    private(set) var isCalibrated: Bool
    /// True when a bundled Core ML appearance model is fused with the FACS expert.
    let appearanceModelActive: Bool

    // MARK: - Tunables

    /// Analysis cadence cap (~15 Hz); camera frames beyond this are dropped.
    var minProcessInterval: TimeInterval = 1.0 / 15.0
    private let calibrationTarget = 36
    private let mlFusionWeight = 0.35
    private let mlEveryNFrames = 3
    private let historyCap = 720

    // MARK: - Internals

    private let analyzer = FaceAnalyzer()
    private var smoother = TemporalSmoother()
    private var baseline: NeutralBaseline
    private var calibrationSamples: [FacialMetrics] = []
    private var autoCalibrationAttempted = false
    private var busy = false
    private var lastProcessTime: CFAbsoluteTime = 0
    private let mlScorer: CoreMLEmotionScorer?
    private var mlBusy = false
    private var latestMLDistribution: EmotionDistribution?
    private var frameCounter = 0
    private var neutralHoldStart: Date?
    private var fpsTimestamps: [CFAbsoluteTime] = []
    /// EMA-smoothed raw evidence scores (geometric expert) — the intensity signal.
    private var smoothedIntensities: [Emotion: Double] = [:]
    /// EMA-smoothed overall expression energy (intensity stand-in for neutral).
    private var smoothedEnergy: Double = 0
    private let intensityAlpha = 0.35

    init() {
        let saved = NeutralBaseline.loadSaved()
        baseline = saved ?? .default
        isCalibrated = saved?.isCalibrated ?? false
        let scorer = CoreMLEmotionScorer()
        mlScorer = scorer
        appearanceModelActive = scorer != nil
    }

    // MARK: - Input

    /// Feed a camera frame. Cheap to call at full camera rate; the engine
    /// throttles and drops frames internally.
    func ingest(_ pixelBuffer: CVPixelBuffer) {
        let now = CFAbsoluteTimeGetCurrent()
        guard !busy, now - lastProcessTime >= minProcessInterval else { return }
        busy = true
        lastProcessTime = now

        Task { [weak self] in
            guard let self else { return }
            let analysis = await self.analyzer.analyze(pixelBuffer)
            self.apply(analysis, pixelBuffer: pixelBuffer)
            self.busy = false
        }
    }

    /// Restart neutral-baseline calibration (user should hold a relaxed face).
    func startCalibration() {
        calibrationSamples = []
        calibrationPhase = .collecting(progress: 0)
    }

    func clearHistory() {
        history = []
    }

    // MARK: - Pipeline

    private func apply(_ analysis: FrameAnalysis, pixelBuffer: CVPixelBuffer) {
        let now = Date()
        tickFPS()

        guard let extraction = analysis.extraction, extraction.landmarkConfidence >= 0.25 else {
            overlay = nil
            auVector = [:]
            smoother.decayTowardRest()
            for (k, v) in smoothedIntensities { smoothedIntensities[k] = v * 0.85 }
            smoothedEnergy *= 0.85
            let dist = smoother.smoothed
            let va = dist.valenceArousal
            reading = EmotionReading(
                date: now,
                distribution: dist,
                dominant: smoother.stableDominant,
                confidence: dist[smoother.stableDominant],
                intensity: 0,
                intensities: smoothedIntensities,
                valence: va.valence,
                arousal: va.arousal,
                faceDetected: false,
                quality: 0
            )
            return
        }

        // Quality = landmark confidence × head-pose penalty (frontal is best).
        let yawPenalty: Double
        if let yaw = extraction.yaw {
            yawPenalty = max(0, cos(min(abs(yaw), .pi / 2) * 1.2))
        } else {
            yawPenalty = 1
        }
        let quality = min(1, extraction.landmarkConfidence) * yawPenalty

        // First good face with no saved baseline → calibrate automatically.
        if !isCalibrated, !autoCalibrationAttempted, calibrationPhase == .idle {
            autoCalibrationAttempted = true
            startCalibration()
        }

        // Calibration collection.
        if case .collecting = calibrationPhase {
            if extraction.landmarkConfidence >= 0.4 {
                calibrationSamples.append(extraction.metrics)
            }
            let progress = Double(calibrationSamples.count) / Double(calibrationTarget)
            if calibrationSamples.count >= calibrationTarget,
               let median = FacialMetrics.median(of: calibrationSamples) {
                baseline = NeutralBaseline(metrics: median, isCalibrated: true)
                baseline.save()
                isCalibrated = true
                calibrationPhase = .idle
                calibrationSamples = []
            } else {
                calibrationPhase = .collecting(progress: min(1, progress))
            }
        }

        // Geometry expert: metrics → AUs → EMFACS distribution.
        let au = AUComputer.compute(metrics: extraction.metrics, baseline: baseline.metrics)
        var frameDistribution = EmotionClassifier.classify(au)

        // Intensity signal: raw pre-softmax evidence scores. Deliberately
        // geometric-only — intensity measures how far the face is from rest,
        // which the appearance expert cannot grade.
        let rawScores = EmotionClassifier.scores(for: au)
        for e in Emotion.allCases {
            let prev = smoothedIntensities[e] ?? 0
            smoothedIntensities[e] = prev * (1 - intensityAlpha) + (rawScores[e] ?? 0) * intensityAlpha
        }
        smoothedEnergy = smoothedEnergy * (1 - intensityAlpha)
            + EmotionClassifier.expressionEnergy(for: au) * intensityAlpha

        // Appearance expert (optional): score every Nth frame asynchronously,
        // fuse the most recent result log-linearly.
        frameCounter += 1
        if let mlScorer, frameCounter % mlEveryNFrames == 0, !mlBusy {
            mlBusy = true
            let visionRect = visionRect(fromUIRect: extraction.overlay.faceRect)
            Task { [weak self] in
                let dist = await mlScorer.score(pixelBuffer: pixelBuffer, faceRect: visionRect)
                guard let self else { return }
                self.latestMLDistribution = dist
                self.mlBusy = false
            }
        }
        if let mlDist = latestMLDistribution {
            frameDistribution = frameDistribution.fused(with: mlDist, weight: mlFusionWeight)
        }

        let (smoothedDist, stableDominant) = smoother.update(with: frameDistribution)

        // Slow baseline drift correction: after 2 s of confident neutrality,
        // gently track the current metrics to absorb session drift.
        if stableDominant == .neutral, smoothedDist[.neutral] > 0.55, quality > 0.5 {
            if let start = neutralHoldStart {
                if now.timeIntervalSince(start) > 2 {
                    baseline.metrics = baseline.metrics.lerp(toward: extraction.metrics, alpha: 0.02)
                }
            } else {
                neutralHoldStart = now
            }
        } else {
            neutralHoldStart = nil
        }

        let va = smoothedDist.valenceArousal
        // For expressive emotions intensity = their evidence strength; for
        // neutral it degrades to overall expression energy (≈0 at rest).
        let intensity = stableDominant == .neutral
            ? smoothedEnergy
            : (smoothedIntensities[stableDominant] ?? 0)
        reading = EmotionReading(
            date: now,
            distribution: smoothedDist,
            dominant: stableDominant,
            confidence: smoothedDist[stableDominant],
            intensity: min(1, intensity),
            intensities: smoothedIntensities,
            valence: va.valence,
            arousal: va.arousal,
            faceDetected: true,
            quality: quality
        )
        auVector = au
        overlay = extraction.overlay

        history.append(EmotionSample(date: now, emotion: stableDominant, confidence: smoothedDist[stableDominant]))
        if history.count > historyCap {
            history.removeFirst(history.count - historyCap)
        }
    }

    // MARK: - Helpers

    private func tickFPS() {
        let now = CFAbsoluteTimeGetCurrent()
        fpsTimestamps.append(now)
        fpsTimestamps.removeAll { now - $0 > 2 }
        processedFPS = Double(fpsTimestamps.count) / 2
    }

    /// Convert a top-left-origin UI rect back into Vision's bottom-left space.
    private func visionRect(fromUIRect r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: 1 - r.minY - r.height, width: r.width, height: r.height)
    }
}
#endif
