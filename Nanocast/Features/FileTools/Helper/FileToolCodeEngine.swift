import Foundation
import Vision

nonisolated enum FileToolCodeEngine {
    static func run(_ request: FileToolRequest) async throws {
        guard let source = request.sources.first else { throw FileToolEngine.Failure.unsupported }
        let image = try FileToolImageEngine.decode(source, option: nil).image
        let observations = try await DetectBarcodesRequest().perform(on: image)
        let payloads = observations.compactMap(\.payloadString)
        try Data(payloads.joined(separator: "\n").utf8).write(to: request.destination)
    }
}
