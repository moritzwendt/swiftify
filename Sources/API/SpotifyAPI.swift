import Foundation

struct APIResponse {
    let status: Int
    let data: Data

    var text: String { String(data: data, encoding: .utf8) ?? "" }
    var isSuccess: Bool { (200..<300).contains(status) }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }
}

struct SpotifyAPI {
    let auth: AuthManager

    func send(
        _ method: String,
        _ path: String,
        query: [String: String] = [:],
        body: [String: Any]? = nil
    ) async throws -> APIResponse {
        let token = try await auth.validAccessToken()
        var url = SpotifyConfig.apiBase.appending(path: path)
        if !query.isEmpty {
            url.append(queryItems: query.map { URLQueryItem(name: $0.key, value: $0.value) })
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return APIResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
    }
}

struct SpotifyDevice: Decodable, Identifiable {
    let id: String?
    let name: String
    let type: String
    let isActive: Bool
}

struct DevicesResponse: Decodable {
    let devices: [SpotifyDevice]
}

struct PlaylistsResponse: Decodable {
    struct Item: Decodable {
        let id: String
        let name: String
        let uri: String
    }
    let items: [Item]
}

struct PlayerState: Decodable {
    struct Track: Decodable {
        struct Artist: Decodable { let name: String }
        let name: String
        let artists: [Artist]
    }
    let isPlaying: Bool
    let item: Track?
    let device: SpotifyDevice?
}
