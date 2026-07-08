//
//  EmotionHeroView.swift
//  Facial Computing
//
//  The headline readout: big emoji inside an animated confidence ring,
//  emotion name, confidence, and the FACS evidence hint.
//

import SwiftUI

#if os(visionOS)
struct EmotionHeroView: View {
    let reading: EmotionReading

    private var color: Color { reading.dominant.color }

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: max(0.001, reading.faceDetected ? reading.confidence : 0))
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0.45), color],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text(reading.faceDetected ? reading.dominant.emoji : "🔍")
                    .font(.system(size: 58))
                    .contentTransition(.opacity)
            }
            .frame(width: 124, height: 124)
            .animation(.smooth(duration: 0.3), value: reading.confidence)

            VStack(alignment: .leading, spacing: 5) {
                Text(reading.faceDetected ? reading.dominant.displayName : "Looking for you…")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(reading.faceDetected ? color : Color.secondary)
                    .contentTransition(.opacity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if reading.faceDetected {
                    Text("\(Int((reading.confidence * 100).rounded()))% confident")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    Text(reading.dominant.facsHint)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Start the camera and face it to begin")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(color.opacity(reading.faceDetected ? 0.35 : 0.08), lineWidth: 1.5)
        )
        .animation(.smooth(duration: 0.35), value: reading.dominant)
    }
}
#endif
