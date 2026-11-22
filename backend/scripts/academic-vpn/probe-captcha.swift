import CoreImage
import Foundation
import ImageIO
import Vision

let bytes = FileHandle.standardInput.readDataToEndOfFile()
guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else { exit(1) }
let context = CIContext()
let original = CIImage(cgImage: image)
let large = original.applyingFilter("CILanczosScaleTransform", parameters: ["inputScale": 4.0, "inputAspectRatio": 1.0])
let gray = large.applyingFilter("CIColorControls", parameters: ["inputSaturation": 0.0, "inputContrast": 1.3])
var results: [[String: Any]] = []
for variant in [original, large, gray] {
    guard let cg = context.createCGImage(variant, from: variant.extent) else { continue }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["en-US"]
    do {
        try VNImageRequestHandler(cgImage: cg, orientation: .up).perform([request])
        let observations = (request.results ?? []).sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        let candidates = observations.compactMap { $0.topCandidates(1).first }
        let text = candidates.map(\.string).joined().filter { !$0.isWhitespace }.lowercased()
        let confidence = candidates.map(\.confidence).min() ?? 0
        results.append(["text": text, "confidence": confidence])
    } catch { continue }
}
let encoded = try JSONSerialization.data(withJSONObject: results)
FileHandle.standardOutput.write(encoded)
