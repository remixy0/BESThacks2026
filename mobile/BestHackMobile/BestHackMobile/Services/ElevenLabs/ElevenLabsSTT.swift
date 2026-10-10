import Foundation

/// ElevenLabs speech-to-text (Scribe): sends a short recording, gets the words back.
/// Docs: https://elevenlabs.io/docs/api-reference/speech-to-text/convert
/// The API key needs the "Speech to Text" permission.
nonisolated struct ElevenLabsSTT: Sendable {
    let apiKey: String

    /// Newest first; the next one is tried if the server rejects the model name.
    static let models = ["scribe_v2", "scribe_v1"]
    private static let url = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!

    /// The text spoken in the audio file. `languageCode` like "pol" or "eng" (nil = detect).
    @concurrent
    func transcribe(fileURL: URL, languageCode: String?) async throws -> String {
        let audio = try Data(contentsOf: fileURL)
        var lastError: Error = ElevenLabsError(httpStatus: 0, body: Data())
        for (index, model) in Self.models.enumerated() {
            let boundary = "Boundary-\(UUID().uuidString)"
            var request = URLRequest(url: Self.url)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 20

            var fields = ["model_id": model, "tag_audio_events": "false"]
            if let languageCode { fields["language_code"] = languageCode }
            let body = Self.multipart(fields: fields, file: audio, fileName: fileURL.lastPathComponent,
                                      mimeType: "audio/mp4", boundary: boundary)

            let (data, response) = try await URLSession.shared.upload(for: request, from: body)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                struct Result: Decodable { let text: String }
                let text = try JSONDecoder().decode(Result.self, from: data).text
                print("[STT] heard: \(text)")
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let error = ElevenLabsError(httpStatus: status, body: data)
            print("[STT] \(model) failed: HTTP \(status) \(error.message)")
            lastError = error
            // A rejected model name comes back as 400/422: try the older model. Anything else is final.
            guard (status == 400 || status == 422), index < Self.models.count - 1 else { throw error }
        }
        throw lastError
    }

    private static func multipart(fields: [String: String], file: Data, fileName: String, mimeType: String, boundary: String) -> Data {
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        for (name, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(file)
        append("\r\n--\(boundary)--\r\n")
        return body
    }
}
