//
//  OAuth21Client.swift
//  cli-oauth21
//  Created by Dmitry Alexandrov on 27.10.2025.
//

import Foundation
import CryptoKit

final class OAuthAPI {
    static let clientIdDefaultsKey = "oauth_client_id"

    private let baseURL: String
    private var codeVerifier: String?

    init(baseURL: String = "http://localhost:3000") {
        self.baseURL = baseURL
    }

    // MARK: - Client Registration
    @discardableResult
    func registerClient(clientName: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/client-registration") else {
            throw OAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "client_name": clientName,
            "redirect_uris": ["demoapp://oauth-callback"],
            "client_type": "public"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OAuthError.serverError("Invalid response from server")
        }

        guard http.statusCode == 200 else {
            throw mapHTTPError(http, data: data)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let clientId = json["client_id"] as? String
        else {
            throw OAuthError.invalidResponse("Client ID not found in response")
        }

        UserDefaults.standard.set(clientId, forKey: Self.clientIdDefaultsKey)
        return clientId
    }

    // MARK: - User Registration
    func registerUser(username: String, password: String) async throws {
        guard let url = URL(string: "\(baseURL)/user/register") else {
            throw OAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "username": username,
            "password": password
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OAuthError.serverError("Invalid response from server")
        }

        guard http.statusCode == 201 else {
            throw mapHTTPError(http, data: data)
        }
    }

    // MARK: - OAuth 2.1 Authentication Flow
    @discardableResult
    func authenticate(username: String, password: String) async throws -> OAuthTokens {
        let clientId = try await getOrRegisterClientId(forceRegister: false)

        do {
            return try await authenticateOnce(username: username, password: password, clientId: clientId)
        } catch {
            let shouldRetry = true

            if shouldRetry {
                UserDefaults.standard.removeObject(forKey: Self.clientIdDefaultsKey)
                let newClientId = try await getOrRegisterClientId(forceRegister: true)
                return try await authenticateOnce(username: username, password: password, clientId: newClientId)
            }

            throw error
        }
    }
    // MARK: - User Info
    func fetchUserInfo() async throws -> [String: Any] {
        let (data, http) = try await performAuthorizedRequest { accessToken in
            guard let url = URL(string: "\(baseURL)/userinfo") else {
                throw APIError.badRequest(message: "Неверный URL")
            }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            return req
        }

        guard (200...299).contains(http.statusCode) else {
            throw mapHTTPError(http, data: data)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decoding
        }

        return json
    }

    // MARK: - Revoke
    func revokeAccessToken() async throws {
        guard let tokens = TokenStorage.shared.loadTokens() else { return }
        guard let clientId = UserDefaults.standard.string(forKey: Self.clientIdDefaultsKey) else { return }
        guard let url = URL(string: "\(baseURL)/oauth/revoke") else { throw OAuthError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "token": tokens.accessToken,
            "token_type_hint": "access_token",
            "client_id": clientId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OAuthError.serverError("Invalid response")
        }

        guard (200...299).contains(http.statusCode) else {
            throw mapHTTPError(http, data: data)
        }
    }

    // MARK: - Token helpers
    func accessTokenExpirationDate() -> Date? {
        guard let tokens = TokenStorage.shared.loadTokens() else { return nil }
        return JWT.expirationDate(from: tokens.accessToken)
    }

    func secondsUntilAccessTokenExpires(from now: Date = Date()) -> Int? {
        guard let exp = accessTokenExpirationDate() else { return nil }
        return Int(exp.timeIntervalSince(now))
    }

    // MARK: - PKCE
    private func generatePKCE() -> (verifier: String, challenge: String) {
        let verifier = generateRandomString(length: 43)
        let challenge = generateCodeChallenge(verifier: verifier)
        return (verifier, challenge)
    }

    private func generateCodeChallenge(verifier: String) -> String {
        let verifierData = Data(verifier.utf8)
        let hash = Data(SHA256.hash(data: verifierData))
        return base64URLEncode(hash)
    }

    private func generateRandomString(length: Int) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }

    private func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Endpoints
    private func requestAuthorizationCode(
        username: String,
        password: String,
        clientId: String,
        codeChallenge: String
    ) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/oauth/authorize") else {
            throw OAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "username": username,
            "password": password,
            "client_id": clientId,
            "redirect_uri": "demoapp://oauth-callback",
            "code_challenge": codeChallenge,
            "code_challenge_method": "S256",
            "scope": "openid profile"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OAuthError.serverError("Authorize: invalid response")
        }

        guard http.statusCode == 200 else {
            throw mapHTTPError(http, data: data)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthError.invalidResponse("Authorize returned non-JSON. Body: \(String(data: data, encoding: .utf8) ?? "<non-utf8>")")
        }

        return json
    }

    private func exchangeCodeForTokens(
        authCode: String,
        clientId: String,
        codeVerifier: String
    ) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/oauth/token") else {
            throw OAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "grant_type": "authorization_code",
            "code": authCode,
            "client_id": clientId,
            "redirect_uri": "demoapp://oauth-callback",
            "code_verifier": codeVerifier
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OAuthError.serverError("Token: invalid response")
        }

        guard http.statusCode == 200 else {
            throw mapHTTPError(http, data: data)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthError.invalidResponse("Token returned non-JSON. Body: \(String(data: data, encoding: .utf8) ?? "<non-utf8>")")
        }

        return json
    }

    // MARK: - Refresh
    private func refreshAccessToken() async throws {
        guard let tokens = TokenStorage.shared.loadTokens() else {
            throw OAuthError.notAuthenticated
        }
        guard let clientId = UserDefaults.standard.string(forKey: Self.clientIdDefaultsKey) else {
            throw OAuthError.serverError("Missing client_id")
        }
        guard let url = URL(string: "\(baseURL)/oauth/token") else {
            throw OAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
            "client_id": clientId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OAuthError.serverError("Invalid response")
        }

        guard http.statusCode == 200 else {
            throw mapHTTPError(http, data: data)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let accessToken = json["access_token"] as? String,
            let refreshToken = json["refresh_token"] as? String
        else {
            throw OAuthError.invalidResponse("refresh response missing tokens")
        }

        let newTokens = OAuthTokens(accessToken: accessToken, refreshToken: refreshToken)
        try TokenStorage.shared.save(tokens: newTokens)
    }

    // MARK: - Authorized request wrapper
    private func performAuthorizedRequest(
        _ makeRequest: (String) throws -> URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        guard let tokens = TokenStorage.shared.loadTokens() else {
            throw OAuthError.notAuthenticated
        }

        func send(_ accessToken: String) async throws -> (Data, HTTPURLResponse) {
            let req = try makeRequest(accessToken)
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw OAuthError.serverError("Invalid response")
            }
            return (data, http)
        }

        let (data1, http1) = try await send(tokens.accessToken)
        if http1.statusCode != 401 {
            return (data1, http1)
        }

        try await TokenRefresher.shared.refreshOnce {
            try await self.refreshAccessToken()
        }

        guard let updated = TokenStorage.shared.loadTokens() else {
            throw APIError.unauthorized
        }

        let (data2, http2) = try await send(updated.accessToken)

        if http2.statusCode == 401 {
            TokenStorage.shared.clear()
            throw APIError.unauthorized
        }

        return (data2, http2)
    }

    // MARK: - Error mapping
    private func mapHTTPError(_ http: HTTPURLResponse, data: Data?) -> APIError {
        let status = http.statusCode

        var message: String? = nil
        if let data,
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            message = (obj["message"] as? String) ?? (obj["error"] as? String)
        }

        switch status {
        case 400:
            return .badRequest(message: message)
        case 401:
            return .unauthorized
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            return .rateLimited(retryAfter: retryAfter)
        default:
            return .server(status: status, message: message)
        }
    }
    
    
    // MARK: Helper
    private func getOrRegisterClientId(forceRegister: Bool) async throws -> String {
        if !forceRegister, let existing = UserDefaults.standard.string(forKey: Self.clientIdDefaultsKey) {
            return existing
        }


        let clientId = try await registerClient(clientName: "Demo iOS App")
        return clientId
    }
    
    private func authenticateOnce(username: String, password: String, clientId: String) async throws -> OAuthTokens {
        let (verifier, challenge) = generatePKCE()
        self.codeVerifier = verifier

        let authJSON = try await requestAuthorizationCode(
            username: username,
            password: password,
            clientId: clientId,
            codeChallenge: challenge
        )

        let authCode =
            (authJSON["authorization_code"] as? String) ??
            (authJSON["code"] as? String) ??
            (authJSON["authorizationCode"] as? String)

        guard let authCode else {
            throw OAuthError.invalidResponse("missing authorization code")
        }

        let tokenJSON = try await exchangeCodeForTokens(
            authCode: authCode,
            clientId: clientId,
            codeVerifier: verifier
        )

        guard
            let accessToken = tokenJSON["access_token"] as? String,
            let refreshToken = tokenJSON["refresh_token"] as? String
        else {
            throw OAuthError.invalidResponse("token response missing tokens")
        }

        let tokens = OAuthTokens(accessToken: accessToken, refreshToken: refreshToken)
        try TokenStorage.shared.save(tokens: tokens)
        return tokens
    }
    
    func refreshTokensManually() async throws {
        try await TokenRefresher.shared.refreshOnce {
            try await self.refreshAccessToken()
        }
    }
}
