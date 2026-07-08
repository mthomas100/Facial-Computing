//
//  EmotionDashboardView.swift
//  Facial Computing
//
//  The emotion-recognition dashboard: live Persona preview with landmark
//  overlay and calibration flow on the left; hero readout, probability bars,
//  circumplex pad, and FACS meters on the right.
//

import SwiftUI

#if os(visionOS)
struct EmotionDashboardView: View {
    let engine: EmotionEngine
    let persona: PersonaCaptureController

    @State private var showScience = true
    @State private var vaTrail: [CGPoint] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controlBar
            HStack(alignment: .top, spacing: 14) {
                leftColumn
                    .frame(width: 440)
                rightColumn
                    .frame(minWidth: 500, maxWidth: .infinity)
            }
        }
        .padding(4)
        .onChange(of: engine.reading.date) { _, _ in
            let r = engine.reading
            guard r.faceDetected else { return }
            vaTrail.append(CGPoint(x: r.valence, y: r.arousal))
            if vaTrail.count > 40 { vaTrail.removeFirst(vaTrail.count - 40) }
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 10) {
            Button {
                Task { @MainActor in
                    if persona.isRunning {
                        persona.stop()
                    } else {
                        try? await persona.start()
                    }
                }
            } label: {
                Label(persona.isRunning ? "Stop" : "Start", systemImage: persona.isRunning ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(persona.isRunning ? .red : .green)

            Button {
                engine.startCalibration()
            } label: {
                Label("Calibrate Neutral", systemImage: "face.dashed")
            }
            .disabled(!persona.isRunning)

            if engine.isCalibrated {
                Label("Calibrated", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Spacer()

            Toggle(isOn: $showScience) {
                Label("Science", systemImage: "waveform.path.ecg")
            }
            .toggleStyle(.button)

            Label(
                engine.appearanceModelActive ? "FACS + Neural fusion" : "FACS geometric engine",
                systemImage: "brain.head.profile"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Left column (preview + status + timeline)

    private var leftColumn: some View {
        VStack(spacing: 10) {
            ZStack {
                PixelBufferView(pixelBuffer: persona.latestPixelBuffer)
                FaceLandmarkOverlay(overlay: engine.overlay, tint: engine.reading.dominant.color)
                if case .collecting(let progress) = engine.calibrationPhase {
                    CalibrationOverlay(progress: progress)
                }
            }
            .frame(width: 440, height: 248)
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            statusRow
            EmotionTimelineView(samples: engine.history)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            Label(
                engine.reading.faceDetected ? "Face locked" : "No face",
                systemImage: engine.reading.faceDetected ? "faceid" : "questionmark.circle"
            )
            .font(.caption)
            .foregroundStyle(engine.reading.faceDetected ? Color.green : Color.secondary)

            Label(String(format: "%.0f Hz", engine.processedFPS), systemImage: "speedometer")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 5) {
                Text("Signal")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                ProgressView(value: engine.reading.quality)
                    .frame(width: 70)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Right column (readouts)

    private var rightColumn: some View {
        VStack(spacing: 12) {
            EmotionHeroView(reading: engine.reading)
            EmotionBarsView(distribution: engine.reading.distribution)
            HStack(alignment: .top, spacing: 12) {
                ValenceArousalPadView(
                    valence: engine.reading.valence,
                    arousal: engine.reading.arousal,
                    trail: vaTrail,
                    color: engine.reading.dominant.color
                )
                .frame(width: 215, height: 215)

                if showScience {
                    AUMetersView(au: engine.auVector)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.title)
                            .foregroundStyle(.tertiary)
                        Text("Turn on Science to watch the FACS Action Units driving each classification.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
    }
}

/// Dimmed overlay with a progress ring shown while the neutral baseline is captured.
struct CalibrationOverlay: View {
    let progress: Double

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: max(0.001, progress))
                        .stroke(Color.cyan, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.caption.bold())
                        .contentTransition(.numericText())
                }
                .frame(width: 64, height: 64)

                Text("Calibrating your neutral face")
                    .font(.headline)
                Text("Relax your face and look toward the camera")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.smooth(duration: 0.2), value: progress)
    }
}
#endif
