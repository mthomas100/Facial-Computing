//
//  FaceAnalyzer.swift
//  Facial Computing
//
//  Off-main-actor Vision work: runs face landmark detection on a frame and
//  reduces it to a Sendable `FrameAnalysis` value for the emotion engine.
//

import Foundation
import CoreVideo
import CoreGraphics

#if os(visionOS)
import Vision

nonisolated struct FrameAnalysis: Sendable {
    var extraction: FaceGeometry.Extraction?
    var imageSize: CGSize
}

/// Serializes Vision requests on its own executor so landmark detection never
/// blocks the main actor.
actor FaceAnalyzer {

    private let landmarksRequest = VNDetectFaceLandmarksRequest()

    func analyze(_ pixelBuffer: CVPixelBuffer) -> FrameAnalysis {
        let size = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([landmarksRequest])
        } catch {
            return FrameAnalysis(extraction: nil, imageSize: size)
        }

        // Track the largest detected face (the user's Persona fills the frame).
        let face = (landmarksRequest.results ?? []).max { a, b in
            a.boundingBox.width * a.boundingBox.height < b.boundingBox.width * b.boundingBox.height
        }
        guard let face else {
            return FrameAnalysis(extraction: nil, imageSize: size)
        }

        return FrameAnalysis(
            extraction: FaceGeometry.extract(from: face, imageSize: size),
            imageSize: size
        )
    }
}
#endif
