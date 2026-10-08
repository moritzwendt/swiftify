import AuthenticationServices
import Observation
import UIKit

enum AuthError: LocalizedError {
    case notSignedIn
    case stateMismatch
    case denied(String)
    case missingCode
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Not signed in"
        case .stateMismatch: "Authorization state mismatch"
        case .denied(let reason): "Authorization denied: \(reason)"
        case .missingCode: "Authorization code missing"
        case .server(let status, let body): "Token request failed (\(status)): \(body)"
        }
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
}

@MainActor
@Observable
final class AuthManager {
    private(set) var isAuthenticated: Bool
    private(set) var isSigningIn = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let store = TokenStore()
    @ObservationIgnored private var tokens: StoredTokens?
    @ObservationIgnored private var refreshTask: Task<StoredTokens, Error>?
    @ObservationIgnored private var webSession: ASWebAuthenticationSession?
    @ObservationIgnored private let presenter = PresentationAnchorProvider()

    init() {
        var saved = store.load()
        if let current = saved, current.scope != SpotifyConfig.scopeString {
            store.clear()
            saved = nil
            BootLog.shared.note("auth", "scopes changed, stored token cleared")
        }
        tokens = saved
        isAuthenticated = saved != nil
        if let saved {
            let remaining = Int(saved.expiresAt.timeIntervalSinceNow)
            BootLog.shared.note("auth", "keychain token found, access token \(remaining > 0 ? "valid for \(remaining) s" : "expired")")
        } else {
            BootLog.shared.note("auth", "no keychain token")
        }
    }

    func signIn() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        let verifier = PKCE.randomString()
        let state = PKCE.randomString(byteCount: 16)

        var components = URLComponents(url: SpotifyConfig.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: SpotifyConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: SpotifyConfig.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "scope", value: SpotifyConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state)
        ]

        do {
            let callback = try await authenticate(with: components.url!)
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let error = items.first(where: { $0.name == "error" })?.value {
                throw AuthError.denied(error)
            }
            guard items.first(where: { $0.name == "state" })?.value == state else {
                throw AuthError.stateMismatch
            }
            guard let code = items.first(where: { $0.name == "code" })?.value else {
                throw AuthError.missingCode
            }
            let response = try await requestTokens([
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": SpotifyConfig.redirectURI,
                "client_id": SpotifyConfig.clientID,
                "code_verifier": verifier
            ])
            guard let refreshToken = response.refreshToken else { throw AuthError.missingCode }
            persist(StoredTokens(
                accessToken: response.accessToken,
                refreshToken: refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
                scope: SpotifyConfig.scopeString
            ))
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        refreshTask?.cancel()
        refreshTask = nil
        tokens = nil
        store.clear()
        isAuthenticated = false
    }

    func validAccessToken() async throws -> String {
        guard let current = tokens else { throw AuthError.notSignedIn }
        if current.expiresAt > Date().addingTimeInterval(60) {
            return current.accessToken
        }
        if let refreshTask {
            return try await refreshTask.value.accessToken
        }
        let task = Task { try await refresh(current) }
        refreshTask = task
        defer { refreshTask = nil }
        BootLog.post("auth", "access token expired, refreshing")
        do {
            let updated = try await task.value
            BootLog.post("auth", "token refreshed, valid for \(Int(updated.expiresAt.timeIntervalSinceNow)) s")
            persist(updated)
            return updated.accessToken
        } catch let AuthError.server(status, _) where status == 400 || status == 401 {
            signOut()
            throw AuthError.notSignedIn
        }
    }

    private func refresh(_ current: StoredTokens) async throws -> StoredTokens {
        let response = try await requestTokens([
            "grant_type": "refresh_token",
            "refresh_token": current.refreshToken,
            "client_id": SpotifyConfig.clientID
        ])
        return StoredTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? current.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            scope: current.scope
        )
    }

    private func persist(_ updated: StoredTokens) {
        tokens = updated
        store.save(updated)
        isAuthenticated = true
    }

    private func requestTokens(_ form: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: SpotifyConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AuthError.server(status, String(data: data, encoding: .utf8) ?? "")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TokenResponse.self, from: data)
    }

    private func authenticate(with url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: SpotifyConfig.redirectScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? AuthError.missingCode)
                }
            }
            session.presentationContextProvider = presenter
            session.prefersEphemeralWebBrowserSession = false
            webSession = session
            session.start()
        }
    }
}

private final class PresentationAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
