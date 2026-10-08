import Foundation

struct APIError: LocalizedError {
    let status: Int
    let message: String

    var errorDescription: String? { message.isEmpty ? "HTTP \(status)" : message }
}

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

    func validate() throws {
        guard isSuccess else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let error = object?["error"] as? [String: Any]
            let message = (error?["message"] as? String) ?? ""
            throw APIError(status: status, message: message)
        }
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
        var attempt = 0
        while true {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            if http?.statusCode == 429, attempt < 2,
               let wait = http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init), wait <= 10 {
                attempt += 1
                try await Task.sleep(for: .seconds(wait + 0.2))
                continue
            }
            return APIResponse(status: http?.statusCode ?? 0, data: data)
        }
    }

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let response = try await send("GET", path, query: query)
        try response.validate()
        return try response.decode(T.self)
    }

    func perform(
        _ method: String,
        _ path: String,
        query: [String: String] = [:],
        body: [String: Any]? = nil
    ) async throws {
        let response = try await send(method, path, query: query, body: body)
        try response.validate()
    }

    func request<T: Decodable>(
        _ method: String,
        _ path: String,
        body: [String: Any]
    ) async throws -> T {
        let response = try await send(method, path, body: body)
        try response.validate()
        return try response.decode(T.self)
    }

    func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        let response = try await send("POST", path, body: body)
        try response.validate()
        return try response.decode(T.self)
    }
}
