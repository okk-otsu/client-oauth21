//
//  OAuth21Client.swift
//  cli-oauth21
//  Created by Dmitry Alexandrov on 27.10.2025.
//

import Foundation
import CryptoKit

public final class OAuthAPI {
    public static let clientIdDefaultsKey = "oauth_client_id"

    private let baseURL: String
    private let redirectURI = "demoapp://oauth-callback"

    public init(baseURL: String = "http://localhost:3000") {
        self.baseURL = baseURL
    }

    // MARK: - Client Registration

    @discardableResult
    public func registerClient(clientName: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/client-registration") else {
            throw APIError.badRequest(message: "Неверный URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "client_name": clientName,
            "redirect_uris": [redirectURI],
            "client_type": "public"
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await send(req)

        guard (200...299).contains(http.statusCode) else {
            throw mapHTTPError(http, data: data)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let clientId = json["client_id"] as? String
        else {
            throw APIError.decoding
        }

        UserDefaults.standard.set(clientId, forKey: Self.clientIdDefaultsKey)
        return clientId
    }

    private func ensureClientId(clientName: String) async throws -> String {
        if let saved = UserDefaults.standard.string(forKey: Self.clientIdDefaultsKey),
           !saved.isEmpty {
            return saved
        }
        return try await registerClient(clientName: clientName)
    }

    // MARK: - User Registration

    public func registerUser(username: String, password: String) async throws {
        guard let url = URL(string: "\(baseURL)/user/register") else {
            throw APIError.badRequest(message: "Неверный URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "username": username,
            "password": password
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await send(req)

        guard http.statusCode == 201 else {
            throw mapHTTPError(http, data: data)
        }
    }

    // MARK: - OAuth 2.1 Authentication Flow

    @discardableResult
    func authenticate(
        username: String,
        password: String,
        clientNameForAutoRegistration: String = "Demo iOS App"
    ) async throws -> OAuthTokens {
        var clientId = try await ensureClientId(clientName: clientNameForAutoRegistration)

        let (verifier, challenge) = generatePKCE()

        do {
            let authJSON = try await requestAuthorizationCode(
                username: username,
                password: password,
                clientId: clientId,
                codeChallenge: challenge
            )

            guard let authCode = authJSON["authorization_code"] as? String else {
                throw APIError.decoding
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
                throw APIError.decoding
            }

            let tokens = OAuthTokens(accessToken: accessToken, refreshToken: refreshToken)
            try TokenStorage.shared.save(tokens: tokens)
            return tokens

        } catch let apiErr as APIError {
            if case .badRequest = apiErr {
                clientId = try await registerClient(clientName: clientNameForAutoRegistration)

                let authJSON = try await requestAuthorizationCode(
                    username: username,
                    password: password,
                    clientId: clientId,
                    codeChallenge: challenge
                )

                guard let authCode = authJSON["authorization_code"] as? String else {
                    throw APIError.decoding
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
                    throw APIError.decoding
                }

                let tokens = OAuthTokens(accessToken: accessToken, refreshToken: refreshToken)
                try TokenStorage.shared.save(tokens: tokens)
                return tokens
            }

            throw apiErr
        }
    }

    // MARK: - User Info

    public func fetchUserInfo() async throws -> [String: Any] {
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

    // MARK: - Manual refresh / revoke

    public func refreshTokensManually(clientNameForAutoRegistration: String = "Demo iOS App") async throws {
        _ = try await ensureClientId(clientName: clientNameForAutoRegistration)
        try await refreshAccessToken()
    }

    public func revokeAccessToken(clientNameForAutoRegistration: String = "Demo iOS App") async throws {
        guard let tokens = TokenStorage.shared.loadTokens() else { return }

        let clientId = try await ensureClientId(clientName: clientNameForAutoRegistration)

        guard let url = URL(string: "\(baseURL)/oauth/revoke") else {
            throw APIError.badRequest(message: "Неверный URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "token": tokens.accessToken,
            "token_type_hint": "access_token",
            "client_id": clientId
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await send(req)
        guard (200...299).contains(http.statusCode) else {
            throw mapHTTPError(http, data: data)
        }
    }

    // MARK: - Token helpers (UI)

    public func accessTokenExpirationDate() -> Date? {
        guard let tokens = TokenStorage.shared.loadTokens() else { return nil }
        return JWT.expirationDate(from: tokens.accessToken)
    }

    public func secondsUntilAccessTokenExpires(from now: Date = Date()) -> Int? {
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
            throw APIError.badRequest(message: "Неверный URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "username": username,
            "password": password,
            "client_id": clientId,
            "redirect_uri": redirectURI,
            "code_challenge": codeChallenge,
            "code_challenge_method": "S256",
            "scope": "openid profile"
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await send(req)

        guard (200...299).contains(http.statusCode) else {
            throw mapHTTPError(http, data: data)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decoding
        }
        return json
    }

    private func exchangeCodeForTokens(
        authCode: String,
        clientId: String,
        codeVerifier: String
    ) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/oauth/token") else {
            throw APIError.badRequest(message: "Неверный URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "grant_type": "authorization_code",
            "code": authCode,
            "client_id": clientId,
            "redirect_uri": redirectURI,
            "code_verifier": codeVerifier
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await send(req)

        guard (200...299).contains(http.statusCode) else {
            throw mapHTTPError(http, data: data)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decoding
        }
        return json
    }

    // MARK: - Refresh

    private func refreshAccessToken() async throws {
        guard let tokens = TokenStorage.shared.loadTokens() else {
            throw APIError.unauthorized
        }

        guard let clientId = UserDefaults.standard.string(forKey: Self.clientIdDefaultsKey) else {
            throw APIError.badRequest(message: "client_id не найден")
        }

        guard let url = URL(string: "\(baseURL)/oauth/token") else {
            throw APIError.badRequest(message: "Неверный URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
            "client_id": clientId
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await send(req)

        guard (200...299).contains(http.statusCode) else {
            throw mapHTTPError(http, data: data)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let newAccess = json["access_token"] as? String,
            let newRefresh = json["refresh_token"] as? String
        else {
            throw APIError.decoding
        }

        try TokenStorage.shared.save(tokens: .init(accessToken: newAccess, refreshToken: newRefresh))
    }

    // MARK: - Authorized wrapper

    private func performAuthorizedRequest(
        _ makeRequest: (String) throws -> URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        guard let tokens = TokenStorage.shared.loadTokens() else {
            throw APIError.unauthorized
        }

        let req1 = try makeRequest(tokens.accessToken)
        let (data1, http1) = try await send(req1)

        if http1.statusCode != 401 {
            return (data1, http1)
        }

        try await TokenRefresher.shared.refreshOnce {
            try await self.refreshAccessToken()
        }

        guard let updated = TokenStorage.shared.loadTokens() else {
            throw APIError.unauthorized
        }

        let req2 = try makeRequest(updated.accessToken)
        let (data2, http2) = try await send(req2)

        if http2.statusCode == 401 {
            TokenStorage.shared.clear()
            throw APIError.unauthorized
        }

        return (data2, http2)
    }

    // MARK: - Networking

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, resp) = try await URLSession.shared.data(for: request)
            guard let http = resp as? HTTPURLResponse else {
                throw APIError.server(status: 0, message: "Invalid response")
            }
            return (data, http)
        } catch _ as URLError {
            throw APIError.network
        }
    }

    private func mapHTTPError(_ http: HTTPURLResponse, data: Data?) -> APIError {
        let status = http.statusCode

        var message: String? = nil
        if let data,
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            message = (obj["message"] as? String) ?? (obj["error"] as? String)
        } else if let data,
                  let s = String(data: data, encoding: .utf8),
                  !s.isEmpty {
            message = s
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
}
