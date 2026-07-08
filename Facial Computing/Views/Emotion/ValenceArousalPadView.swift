//
//  ValenceArousalPadView.swift
//  Facial Computing
//
//  The circumplex model of affect: a 2D pad plotting valence (x) against
//  arousal (y) with a fading trail of recent readings.
//

import SwiftUI

#if os(visionOS)
struct ValenceArousalPadView: View {
    let valence: Double
    let arousal: Double
    /// Recent (valence, arousal) points, oldest first, each in −1…1.
    let trail: [CGPoint]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Circumplex — Valence · Arousal")
                .font(.footnote.bold())
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    Canvas { ctx, sz in
                        // Axes.
                        var axes = Path()
                        axes.move(to: CGPoint(x: sz.width / 2, y: 0))
                        axes.addLine(to: CGPoint(x: sz.width / 2, y: sz.height))
                        axes.move(to: CGPoint(x: 0, y: sz.height / 2))
                        axes.addLine(to: CGPoint(x: sz.width, y: sz.height / 2))
                        ctx.stroke(axes, with: .color(.white.opacity(0.15)), lineWidth: 1)

                        // Unit circle guide.
                        let inset = CGRect(x: sz.width * 0.08, y: sz.height * 0.08,
                                           width: sz.width * 0.84, height: sz.height * 0.84)
                        ctx.stroke(Path(ellipseIn: inset), with: .color(.white.opacity(0.10)), lineWidth: 1)

                        // Fading trail.
                        if trail.count > 1 {
                            for i in 1..<trail.count {
                                var segment = Path()
                                segment.move(to: Self.mapped(trail[i - 1], in: sz))
                                segment.addLine(to: Self.mapped(trail[i], in: sz))
                                let alpha = 0.45 * Double(i) / Double(trail.count)
                                ctx.stroke(segment, with: .color(color.opacity(alpha)), lineWidth: 2)
                            }
                        }
                    }

                    Circle()
                        .fill(color)
                        .frame(width: 14, height: 14)
                        .shadow(color: color.opacity(0.9), radius: 8)
                        .position(Self.mapped(CGPoint(x: valence, y: arousal), in: size))
                        .animation(.smooth(duration: 0.25), value: valence)
                        .animation(.smooth(duration: 0.25), value: arousal)

                    // Quadrant labels.
                    Text("Excited").font(.caption2).foregroundStyle(.tertiary)
                        .position(x: size.width / 2, y: 10)
                    Text("Calm").font(.caption2).foregroundStyle(.tertiary)
                        .position(x: size.width / 2, y: size.height - 10)
                    Text("−").font(.caption2).foregroundStyle(.tertiary)
                        .position(x: 10, y: size.height / 2)
                    Text("+").font(.caption2).foregroundStyle(.tertiary)
                        .position(x: size.width - 10, y: size.height / 2)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    /// Map circumplex coordinates (−1…1, y-up) into view space.
    private static func mapped(_ va: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: (va.x + 1) / 2 * size.width,
            y: (1 - (va.y + 1) / 2) * size.height
        )
    }
}
#endif
