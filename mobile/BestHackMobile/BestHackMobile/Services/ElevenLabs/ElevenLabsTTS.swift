import Foundation

/// ElevenLabs text-to-speech over their REST API.
/// Docs: https://elevenlabs.io/docs/api-reference/text-to-speech/stream
nonisolated struct ElevenLabsTTS: Sendable {
    enum Model: String, CaseIterable, Identifiable, Sendable {
        /// Most lifelike, emotional delivery. Supports Polish, English and ~30 more languages.
        case multilingualV2 = "eleven_multilingual_v2"
        /// ~75 ms model latency, slightly less natural. Good when you want instant response.
        case flashV2_5 = "eleven_flash_v2_5"

        var id: Self { self }

        var title: String {
            switch self {
            case .multilingualV2: "Lifelike"
            case .flashV2_5: "Fast"
            }
        }
    }

    struct Voice: Identifiable, Hashable, Sendable, Decodable {
        let voiceID: String
        let name: String
        let category: String?
        let labels: [String: String]?

        var id: String { voiceID }

        /// e.g. "British · middle aged · male"
        var details: String {
            guard let labels else { return category ?? "" }
            if let description = labels["description"], labels["accent"] == nil { return description }
            return [labels["accent"], labels["age"], labels["gender"]]
                .compactMap { $0?.replacingOccurrences(of: "_", with: " ") }
                .joined(separator: " · ")
        }

        enum CodingKeys: String, CodingKey {
            case voiceID = "voice_id", name, category, labels
        }

        init(voiceID: String, name: String, details: String) {
            self.voiceID = voiceID
            self.name = name
            category = "premade"
            labels = ["description": details]
        }

        /// Lenient: an odd field (e.g. a non-text label) must not break the whole voice list.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            voiceID = try container.decode(String.self, forKey: .voiceID)
            name = (try? container.decode(String.self, forKey: .name)) ?? "Unnamed voice"
            category = try? container.decode(String.self, forKey: .category)
            labels = try? container.decode([String: String].self, forKey: .labels)
        }
    }

    /// The streaming audio format we ask for: raw 16-bit mono PCM at 24 kHz (available on every plan).
    static let sampleRate = 24_000.0
    /// A premade voice every account has ("George"). Used until the voice list has loaded,
    /// or for good when the key isn't allowed to list voices.
    static let defaultVoiceID = "JBFqnCBsd6RMkjVDRZzb"

    /// ElevenLabs' default voices, which every account can use. Shown when the key isn't allowed to list voices.
    static let premadeVoices: [Voice] = [
        Voice(voiceID: "JBFqnCBsd6RMkjVDRZzb", name: "George", details: "British · warm storyteller · male"),
        Voice(voiceID: "21m00Tcm4TlvDq8ikWAM", name: "Rachel", details: "American · calm · female"),
        Voice(voiceID: "EXAVITQu4vr4xnSDxMaL", name: "Sarah", details: "American · soft · female"),
        Voice(voiceID: "XB0fDUnXU5powFXDhCwa", name: "Charlotte", details: "Swedish-English · gentle · female"),
        Voice(voiceID: "pFZP5JQG7iQjIQuC4Bku", name: "Lily", details: "British · warm · female"),
        Voice(voiceID: "Xb7hH8MSUJpSbSDYk0k2", name: "Alice", details: "British · clear · female"),
        Voice(voiceID: "onwK4e9ZLuTAKqWW03F9", name: "Daniel", details: "British · news presenter · male"),
        Voice(voiceID: "nPczCjzI2devNBz1zQrb", name: "Brian", details: "American · deep · male"),
        Voice(voiceID: "N2lVS1w4EtoT3dr4eOWO", name: "Callum", details: "Transatlantic · husky · male"),
        Voice(voiceID: "IKne3meq5aSn9XLyUdCD", name: "Charlie", details: "Australian · casual · male"),
        Voice(voiceID: "TX3LPaxmHKxFdv7VOQHJ", name: "Liam", details: "American · articulate · male"),
        Voice(voiceID: "cjVigY5qzO86Huf0OWal", name: "Eric", details: "American · friendly · male"),
    ]

    let apiKey: String
    let voiceID: String
    let model: Model
    /// Speaking speed, 0.7…1.2 (1 = normal).
    var speed: Float = 1

    private static let baseURL = URL(string: "https://api.elevenlabs.io")!

    /// Plays speech for `text` into `output`.
    /// A sentence heard before (same voice, quality and speed) comes straight from the phone (`SpeechCache`), with
    /// no request at all; anything new is streamed from ElevenLabs, plays while it downloads, and is saved for next time.
    @concurrent
    func stream(_ text: String, into output: SpeechOutput, token: Int) async throws {
        var played = false
        do {
            try await play(SpeechCache.shared.clip(for: text, using: self), into: output, token: token, played: &played)
        } catch let error where !played && !Task.isCancelled && Self.isCancellation(error) {
            // The shared download was dropped just as we joined it (someone else stopped listening): ask again.
            try await play(SpeechCache.shared.clip(for: text, using: self), into: output, token: token, played: &played)
        }
    }

    private func play(_ clip: SpeechClip, into output: SpeechOutput, token: Int, played: inout Bool) async throws {
        let bytesPerSecond = Int(Self.sampleRate) * 2
        // From the phone: 1 s pieces. From the network: ~0.3 s buffered before the first piece so hiccups
        // don't cause gaps, then ~0.15 s pieces.
        let fromPhone = clip.isComplete
        var chunkSize = fromPhone ? bytesPerSecond : bytesPerSecond * 3 / 10
        var pending = Data()

        for try await piece in clip.audio() {
            guard output.isCurrent(token) else { return }
            pending.append(piece)
            var start = pending.startIndex
            while pending.endIndex - start >= chunkSize {
                output.enqueuePCM16(pending[start..<(start + chunkSize)], sampleRate: Self.sampleRate, token: token)
                played = true
                start += chunkSize
                if !fromPhone { chunkSize = bytesPerSecond * 15 / 100 }
            }
            if start > pending.startIndex { pending = Data(pending[start...]) }
        }
        try Task.checkCancellation()
        // Keep whole 16-bit samples only.
        if pending.count > 1, output.isCurrent(token) {
            output.enqueuePCM16(Data(pending.prefix(pending.count & ~1)), sampleRate: Self.sampleRate, token: token)
        }
    }

    /// The speed as ElevenLabs wants it: 0.7…1.2, rounded to hundredths. (A Float 1.2 becomes 1.2000000476837158 as a
    /// Double, which ElevenLabs rejects with HTTP 400; 0.7 becomes 0.6999999880790710.)
    static func apiSpeed(_ speed: Float) -> Double {
        let rounded = (Double(speed) * 100).rounded() / 100
        return min(max(rounded, 0.7), 1.2)
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    /// Downloads speech for `text` from ElevenLabs into `clip` as it arrives (`SpeechCache` calls this, once per
    /// sentence). Raw 16-bit mono PCM at 24 kHz.
    @concurrent
    func download(_ text: String, into clip: SpeechClip) async throws {
        var request = URLRequest(url: Self.baseURL.appending(path: "v1/text-to-speech/\(voiceID)/stream")
            .appending(queryItems: [URLQueryItem(name: "output_format", value: "pcm_24000")]))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text,
            "model_id": model.rawValue,
            "voice_settings": ["stability": 0.45, "similarity_boost": 0.8, "style": 0.15, "use_speaker_boost": true,
                               "speed": Self.apiSpeed(speed)],
        ])
        request.timeoutInterval = 20

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            let error = ElevenLabsError(httpStatus: status, body: body)
            print("[ElevenLabs] text-to-speech failed: HTTP \(status) \(error.code ?? "-") \(error.message)")
            throw error
        }

        // Hand it on in ~0.1 s pieces.
        let pieceSize = Int(Self.sampleRate) * 2 / 10
        var pending = Data()
        pending.reserveCapacity(pieceSize)
        for try await byte in bytes {
            pending.append(byte)
            if pending.count >= pieceSize {
                clip.append(pending)
                pending.removeAll(keepingCapacity: true)
            }
        }
        clip.append(pending)
    }

    /// Lists the voices this account can use (premade + any you've added in the Voice Library).
    /// Also the way the app checks that a key works.
    @concurrent
    static func fetchVoices(apiKey: String) async throws -> [Voice] {
        var request = URLRequest(url: baseURL.appending(path: "v2/voices")
            .appending(queryItems: [URLQueryItem(name: "page_size", value: "100")]))
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let error = ElevenLabsError(httpStatus: status, body: data)
            print("[ElevenLabs] voice list failed: HTTP \(status) \(error.code ?? "-") \(error.message)")
            throw error
        }

        struct LossyVoice: Decodable {
            let voice: Voice?
            init(from decoder: Decoder) throws { voice = try? Voice(from: decoder) }
        }
        struct Page: Decodable { let voices: [LossyVoice] }

        let voices = try JSONDecoder().decode(Page.self, from: data).voices.compactMap(\.voice)
        print("[ElevenLabs] connected, \(voices.count) voices")
        return voices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
