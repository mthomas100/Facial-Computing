//
//  EmotionBarsView.swift
//  Facial Computing
//
//  Live animated probability bars for all emotion classes.
//

import SwiftUI

#if os(visionOS)
struct EmotionBarsView: View {
    let distribution: EmotionDistribution

    var body: some View {
        VStack(spacing: 7) {
            ForEach(Emotion.allCases) { emotion in
                let p = distribution[emotion]
                HStack(spacing: 10) {
                    Text(emotion.emoji)
                        .font(.system(size: 15))
                        .frame(width: 24)
                    Text(emotion.displayName)
                        .font(.callout)
                        .frame(width: 100, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(emotion.color.gradient)
                                .frame(width: max(4, geo.size.width * p))
                        }
                    }
                    .frame(height: 13)
                    Text("\(Int((p * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .animation(.smooth(duration: 0.25), value: distribution)
    }
}
#endif
