//
//  ImmersiveView.swift
//  Facial Computing
//
//  Created by IVAN CAMPOS on 8/26/25.
//

import SwiftUI
import RealityKit
import RealityKitContent
#if os(visionOS)
import UIKit
#endif

struct ImmersiveView: View {
    @Environment(AppModel.self) var appModel

    var body: some View {
        RealityView { content in
            // Add the initial RealityKit content
            if let immersiveContentEntity = try? await Entity(named: "SkyDome", in: realityKitContentBundle) {
                content.add(immersiveContentEntity)
            }
            #if os(visionOS)
            // Emotion aura: an inward-facing sphere around the user, tinted by
            // the currently detected emotion.
            let aura = ModelEntity(
                mesh: .generateSphere(radius: 7),
                materials: [ImmersiveView.auraMaterial(color: .white, opacity: 0)]
            )
            aura.name = "EmotionAura"
            aura.scale = SIMD3<Float>(-1, 1, 1) // flip winding so the interior renders
            aura.position = [0, 1.5, 0]
            content.add(aura)

            // Attach controls panel as a SwiftUI attachment in space.
            let attachmentEntity = Entity()
            let attachment = ViewAttachmentComponent(rootView: ImmersiveControlsView().environment(appModel))
            attachmentEntity.components.set(attachment)
            attachmentEntity.position = [0, 1.5, -1]
            content.add(attachmentEntity)
            #endif
        } update: { content in
            #if os(visionOS)
            if let aura = content.entities.first(where: { $0.name == "EmotionAura" }) as? ModelEntity {
                let reading = appModel.emotionEngine.reading
                // Aura strength follows expression INTENSITY (gated by
                // confidence) — the sky burns brighter the harder you emote.
                let strength = reading.intensity * min(1, reading.confidence * 1.6)
                let opacity: Float = reading.faceDetected ? Float(0.04 + 0.16 * strength) : 0
                aura.model?.materials = [
                    ImmersiveView.auraMaterial(color: UIColor(reading.dominant.color), opacity: opacity)
                ]
            }
            #endif
        }
        .onAppear {
        }
        .onDisappear {
        }
    }

    #if os(visionOS)
    static func auraMaterial(color: UIColor, opacity: Float) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return material
    }
    #endif
}

//#Preview(immersionStyle: .full) {
//    ImmersiveView()
//        .environment(AppModel())
//}
