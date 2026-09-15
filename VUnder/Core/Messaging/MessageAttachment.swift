import Foundation

enum MessageAttachment: Codable, Equatable, Sendable {
    case audio(Track)
    case voice(VoiceMessage)
    case other(String)

    init?(json: JSONObject) {
        guard let type = json.string("type") else { return nil }
        switch type {
        case "audio":
            guard let track = json.object("audio").flatMap(Track.init(json:)) else { return nil }
            self = .audio(track)
        case "audio_message":
            guard let voice = json.object("audio_message").flatMap(VoiceMessage.init(json:)) else { return nil }
            self = .voice(voice)
        default:
            self = .other(type)
        }
    }

    var previewText: String {
        switch self {
        case .audio(let track): return "Audio: \(track.artist) - \(track.title)"
        case .voice(let voice): return "Voice message \(voice.formattedDuration)"
        case .other(let type): return "Attachment: \(type)"
        }
    }

    var track: Track? {
        if case .audio(let track) = self { return track }
        return nil
    }
}
