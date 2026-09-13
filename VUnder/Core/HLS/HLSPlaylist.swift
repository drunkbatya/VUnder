import Foundation

struct HLSVariant {
    let url: URL
    let bandwidth: Int
}

struct HLSKey: Equatable {
    let url: URL?
    let iv: Data?

    var isEncrypted: Bool {
        url != nil
    }
}

struct HLSSegment {
    let url: URL
    let key: HLSKey
}

enum HLSPlaylist {
    case master([HLSVariant])
    case media([HLSSegment])

    init(text: String, baseURL: URL) throws {
        var variants: [HLSVariant] = []
        var segments: [HLSSegment] = []
        var key = HLSKey(url: nil, iv: nil)
        var pendingBandwidth: Int?
        var pendingSegment = false
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                pendingBandwidth = Int(HLSPlaylist.attributes(of: line)["BANDWIDTH"] ?? "") ?? 0
            } else if line.hasPrefix("#EXT-X-KEY:") {
                let attributes = HLSPlaylist.attributes(of: line)
                let method = attributes["METHOD"] ?? "NONE"
                if method == "NONE" {
                    key = HLSKey(url: nil, iv: nil)
                } else if method == "AES-128", let uri = attributes["URI"], let url = URL(string: uri, relativeTo: baseURL)?.absoluteURL {
                    key = HLSKey(url: url, iv: attributes["IV"].flatMap(HLSPlaylist.hexData))
                } else {
                    throw HLSError.unsupportedKey(method)
                }
            } else if line.hasPrefix("#EXTINF:") {
                pendingSegment = true
            } else if line.hasPrefix("#") {
                continue
            } else if let url = URL(string: line, relativeTo: baseURL)?.absoluteURL {
                if let bandwidth = pendingBandwidth {
                    variants.append(HLSVariant(url: url, bandwidth: bandwidth))
                    pendingBandwidth = nil
                } else if pendingSegment {
                    segments.append(HLSSegment(url: url, key: key))
                    pendingSegment = false
                }
            }
        }
        if !variants.isEmpty {
            self = .master(variants)
        } else if !segments.isEmpty {
            self = .media(segments)
        } else {
            throw HLSError.emptyPlaylist(baseURL)
        }
    }

    static func attributes(of line: String) -> [String: String] {
        guard let colon = line.firstIndex(of: ":") else { return [:] }
        var result: [String: String] = [:]
        var current = ""
        var inQuotes = false
        var parts: [String] = []
        for character in line[line.index(after: colon)...] {
            if character == "\"" {
                inQuotes.toggle()
            } else if character == ",", !inQuotes {
                parts.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        parts.append(current)
        for part in parts {
            guard let equals = part.firstIndex(of: "=") else { continue }
            let name = String(part[..<equals])
            let value = String(part[part.index(after: equals)...]).replacingOccurrences(of: "\"", with: "")
            result[name] = value
        }
        return result
    }

    static func hexData(_ text: String) -> Data? {
        var hex = text.lowercased()
        if hex.hasPrefix("0x") {
            hex.removeFirst(2)
        }
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}

enum HLSError: Error, LocalizedError {
    case unsupportedKey(String)
    case emptyPlaylist(URL)
    case badResponse(URL, Int)
    case keyLength(URL, Int)
    case decryptFailed(Int32)
    case noAudioStream

    var errorDescription: String? {
        switch self {
        case .unsupportedKey(let method): return "HLS key method \(method) is not supported"
        case .emptyPlaylist(let url): return "HLS playlist has no entries: \(url.absoluteString)"
        case .badResponse(let url, let status): return "HLS fetch failed http=\(status): \(url.absoluteString)"
        case .keyLength(let url, let length): return "HLS key has \(length) bytes: \(url.absoluteString)"
        case .decryptFailed(let status): return "HLS segment decrypt failed status=\(status)"
        case .noAudioStream: return "HLS transport stream has no audio PID"
        }
    }
}
