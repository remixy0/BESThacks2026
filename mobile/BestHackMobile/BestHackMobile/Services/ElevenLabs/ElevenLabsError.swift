import Foundation

/// An error response from ElevenLabs, turned into a message a person can act on.
///
/// ElevenLabs errors look like {"detail": {"status": "invalid_api_key", "message": "..."}} or {"detail": "..."}.
nonisolated struct ElevenLabsError: LocalizedError, Sendable {
    let httpStatus: Int
    /// ElevenLabs' reason code, e.g. "invalid_api_key", "missing_permissions", "quota_exceeded".
    let code: String?
    let message: String

    init(httpStatus: Int, body: Data) {
        self.httpStatus = httpStatus
        var code: String?
        var message = String(data: body, encoding: .utf8).map { String($0.prefix(200)) } ?? ""

        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let detail = json["detail"] as? [String: Any] {
                code = (detail["status"] as? String) ?? (detail["code"] as? String)
                message = (detail["message"] as? String) ?? code ?? message
            } else if let detail = json["detail"] as? String {
                message = detail
            }
        }

        self.code = code
        self.message = message.isEmpty ? "No details" : message
    }

    /// The key is valid but not allowed to do this (e.g. list voices).
    var isMissingPermission: Bool {
        code == "missing_permissions" || message.localizedCaseInsensitiveContains("missing the permission")
    }

    var errorDescription: String? {
        if code == "quota_exceeded" || message.localizedCaseInsensitiveContains("quota") {
            return "ElevenLabs quota used up for this month."
        }
        if isMissingPermission {
            return "\(message) Edit the key on elevenlabs.io → API keys and allow Text to Speech and Voices (Read)."
        }
        if code == "invalid_api_key" {
            return "ElevenLabs doesn't recognize this API key. Check that it was copied completely."
        }
        if code == "detected_unusual_activity" {
            return "ElevenLabs blocked free-tier use: \(message)"
        }
        return switch httpStatus {
        case 401: "ElevenLabs rejected the key: \(message)"
        case 429: "ElevenLabs is busy (rate limit), try again in a moment."
        default: "ElevenLabs error \(httpStatus): \(message)"
        }
    }
}
