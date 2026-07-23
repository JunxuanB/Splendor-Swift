import Foundation
import LuminoreCore

enum InternetServerSettings {
    static let storageKey = "internetServerURL"
    static let defaultURL = URL(string: "https://luminore-api.junxuanb.com")!

    static var savedURL: URL {
        guard let value = UserDefaults.standard.string(forKey: storageKey),
              let url = try? normalizedURL(from: value)
        else { return defaultURL }
        return url
    }

    static func normalizedURL(from value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed), let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty
        else { throw MatchTransportError.invalidServer }
        let isLocal = host == "localhost" || host == "127.0.0.1" || host == "::1"
        guard scheme == "https" || (scheme == "http" && isLocal) else {
            throw MatchTransportError.invalidServer
        }
        components.scheme = scheme
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard components.path.isEmpty, components.query == nil, components.fragment == nil,
              let normalized = components.url
        else { throw MatchTransportError.invalidServer }
        return normalized
    }

    static func healthCheck(url: URL) async throws {
        let endpoint = url.appending(path: "v1/health")
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw MatchTransportError.invalidResponse
        }
        let health = try JSONDecoder().decode(InternetHealth.self, from: data)
        guard health.relayProtocolVersion == 1,
              health.gameProtocolVersion == WireEnvelope.currentProtocolVersion
        else { throw MatchTransportError.incompatibleServer }
    }
}

private struct InternetHealth: Decodable {
    let relayProtocolVersion: Int
    let gameProtocolVersion: Int
}
