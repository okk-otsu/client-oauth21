//
//  OAuth21Client.swift
//  cli-oauth21
//  Created by Dmitry Alexandrov on 27.10.2025.
//
import Foundation
import CryptoKit
// MARK: - OAuth 2.1 Client
public class OAuth21Client: ObservableObject {
    private let baseURL = "http://localhost:3000"
    private var clientId: String?
    private var codeVerifier: String?
    
    @Published public var isAuthenticated = false
    @Published public var userInfo: [String: Any]?
    @Published public var errorMessage: String?
    
    public init() {
        if TokenStorage.shared.loadTokens() != nil {
            self.isAuthenticated = true
        }
    }
    
    // MARK: - Client Registration
    public func registerClient(clientName: String) async throws {
        guard let url = URL(string: "\(baseURL)/client-registration") else {
            throw OAuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "client_name": clientName,
            "redirect_uris": ["demoapp://oauth-callback"],
            "client_type": "public"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Debug output
        if let responseString = String(data: data, encoding: .utf8) {
            print("Client registration response: \(responseString)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.serverError("Invalid response from server")
        }
        
        print("Client registration status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode == 200 {
            let clientInfo = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            clientId = clientInfo?["client_id"] as? String
            
            if let clientId = clientId {
                print("Client registered successfully: \(clientId)")
                // Сохраняем clientId для повторного использования
                UserDefaults.standard.set(clientId, forKey: "oauth_client_id")
            } else {
                throw OAuthError.serverError("Client ID not found in response")
            }
        } else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OAuthError.serverError("Client registration failed: \(errorMessage)")
        }
    }
    
    // MARK: - User Registration
    public func registerUser(username: String, password: String) async throws {
        guard let url = URL(string: "\(baseURL)/user/register") else {
            throw OAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "username": username,
            "password": password
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let responseString = String(data: data, encoding: .utf8) {
            print("User registration response: \(responseString)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.serverError("Invalid response from server")
        }

        print("User registration status: \(httpResponse.statusCode)")

        if httpResponse.statusCode == 201 {
            print("User \(username) registered successfully")
            return
        }

        throw mapHTTPError(httpResponse, data: data)
    }
    // MARK: - OAuth 2.1 Authentication Flow
    public func authenticate(username: String, password: String) async throws -> [String: Any] {
        // Восстанавливаем clientId если он был сохранен
        if clientId == nil {
            clientId = UserDefaults.standard.string(forKey: "oauth_client_id")
        }
        
        guard let clientId = clientId else {
            throw OAuthError.clientNotRegistered
        }
        
        print("=== AUTHENTICATION STARTED ===")
        print("Username: \(username)")
        print("Client ID: \(clientId)")
        
        // Generate PKCE code verifier and challenge
        let (codeVerifier, codeChallenge) = generatePKCE()
        self.codeVerifier = codeVerifier
        
        // Step 1: Get authorization code
        print("=== STEP 1: REQUESTING AUTHORIZATION CODE ===")
        let authResponse = try await requestAuthorizationCode(
            username: username,
            password: password,
            clientId: clientId,
            codeChallenge: codeChallenge
        )
        
        guard let authCode = authResponse["authorization_code"] as? String else {
            print("No authorization code in response: \(authResponse)")
            throw OAuthError.invalidResponse
        }
        
        print("Received authorization code: \(authCode)")
        
        // Step 2: Exchange code for tokens
        print("=== STEP 2: EXCHANGING CODE FOR TOKENS ===")
        let tokens = try await exchangeCodeForTokens(
            authCode: authCode,
            clientId: clientId,
            codeVerifier: codeVerifier
        )
        
        print("=== AUTHENTICATION SUCCESSFUL ===")
        print("Tokens received: \(tokens.keys)")
        
        // Store tokens and update state
        if let accessToken = tokens["access_token"] as? String,
           let refreshToken = tokens["refresh_token"] as? String {

            try? TokenStorage.shared.save(
                tokens: OAuthTokens(
                    accessToken: accessToken,
                    refreshToken: refreshToken
                )
            )
        }
        
        await MainActor.run {
            self.isAuthenticated = true
        }
        
        return tokens
    }
    
    // MARK: - PKCE Implementation
    private func generatePKCE() -> (verifier: String, challenge: String) {
        let verifier = generateRandomString(length: 43)
        let challenge = generateCodeChallenge(verifier: verifier)
        
        print("=== PKCE GENERATION ===")
        print("Code verifier: \(verifier)")
        print("Code challenge: \(challenge)")
        print("Verifier length: \(verifier.count)")
        
        return (verifier, challenge)
    }

    private func generateCodeChallenge(verifier: String) -> String {
        let verifierData = Data(verifier.utf8)
        let hash = Data(SHA256.hash(data: verifierData))
        let challenge = base64URLEncode(hash)
        
        print("=== CODE CHALLENGE CALCULATION ===")
        print("Verifier data: \(verifierData.count) bytes")
        print("Hash: \(hash.count) bytes")
        print("Final challenge: \(challenge)")
        
        return challenge
    }
    
    private func generateRandomString(length: Int) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        return String((0..<length).map { _ in characters.randomElement()! })
    }
        
    private func base64URLEncode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    // MARK: - OAuth Endpoints
    private func requestAuthorizationCode(username: String, password: String, clientId: String, codeChallenge: String) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/oauth/authorize") else {
            throw OAuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "username": username,
            "password": password,
            "client_id": clientId,
            "redirect_uri": "demoapp://oauth-callback",
            "code_challenge": codeChallenge,
            "code_challenge_method": "S256",
            "scope": "openid profile"
        ]
        
        print("=== AUTHORIZATION REQUEST BODY ===")
        print("Body: \(body)")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Debug output
        if let responseString = String(data: data, encoding: .utf8) {
            print("=== AUTHORIZATION RESPONSE ===")
            print("Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            print("Response: \(responseString)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.serverError("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OAuthError.serverError("Authorization request failed: \(errorMessage)")
        }
        
        guard let responseData = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthError.serverError("Invalid authorization response format")
        }
        
        return responseData
    }
    
    private func exchangeCodeForTokens(authCode: String, clientId: String, codeVerifier: String) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/oauth/token") else {
            throw OAuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "grant_type": "authorization_code",
            "code": authCode,
            "client_id": clientId,
            "redirect_uri": "demoapp://oauth-callback",
            "code_verifier": codeVerifier
        ]
        
        print("=== TOKEN REQUEST BODY ===")
        print("Auth code: \(authCode)")
        print("Client ID: \(clientId)")
        print("Code verifier: \(codeVerifier)")
        print("Body: \(body)")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Debug output
        if let responseString = String(data: data, encoding: .utf8) {
            print("=== TOKEN RESPONSE ===")
            print("Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            print("Response: \(responseString)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.serverError("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OAuthError.serverError("Token exchange failed: \(errorMessage)")
        }
        
        guard let tokens = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthError.serverError("Invalid token response format")
        }
        
        return tokens
    }
    
    // MARK: - User Info
    public func fetchUserInfo() async throws -> [String: Any] {
        do {
            let (data, http) = try await performAuthorizedRequest { accessToken in
                guard let url = URL(string: "\(baseURL)/userinfo") else {
                    throw APIError.badRequest(message: "Неверный URL")
                }
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                return request
            }

            guard (200...299).contains(http.statusCode) else {
                throw mapHTTPError(http, data: data)
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw APIError.decoding
            }
            return json
        } catch let urlErr as URLError {
            // таймаут/нет сети и т.п.
            if urlErr.code == .notConnectedToInternet || urlErr.code == .timedOut {
                throw APIError.network
            }
            throw urlErr
        }
    }
    public func logout() {
        TokenStorage.shared.clear()
        
        Task { @MainActor in
            isAuthenticated = false
            userInfo = nil
            // Не сбрасываем clientId, чтобы можно было повторно аутентифицироваться
        }
    }
    
    public func reset() {
        // Полный сброс, включая clientId
        logout()
        clientId = nil
        UserDefaults.standard.removeObject(forKey: "oauth_client_id")
    }
    
    // MARK: - refreshAccessToken
    private func refreshAccessToken() async throws {
        guard let tokens = TokenStorage.shared.loadTokens() else {
            throw OAuthError.notAuthenticated
        }
        guard let clientId = clientId else {
            throw OAuthError.serverError("Missing client_id")
        }

        let params: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
            "client_id": clientId
        ]

        let bodyString = params
            .map { "\($0.key)=\(urlEncode($0.value))" }
            .joined(separator: "&")

        guard let url = URL(string: "\(baseURL)/oauth/token") else {
            throw OAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OAuthError.serverError("Invalid response")
        }

        guard (200...299).contains(http.statusCode) else {
            throw mapHTTPError(http, data: data)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let newAccess = json["access_token"] as? String,
            let newRefresh = json["refresh_token"] as? String
        else {
            throw OAuthError.serverError("Invalid refresh token response format")
        }

        try TokenStorage.shared.save(tokens: .init(accessToken: newAccess, refreshToken: newRefresh))
    }
    // MARK: - urlEncode
    private func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }
    
    // MARK: - performAuthorizedRequest
    private func performAuthorizedRequest(_ makeRequest: (String) throws -> URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let tokens = TokenStorage.shared.loadTokens() else {
            throw OAuthError.notAuthenticated
        }

        // 1-я попытка
        var req = try makeRequest(tokens.accessToken)
        var (data, resp) = try await URLSession.shared.data(for: req)

        guard let http = resp as? HTTPURLResponse else {
            throw OAuthError.serverError("Invalid response")
        }

        // Если 401 — refresh и повтор
        if http.statusCode == 401 {
            try await TokenRefresher.shared.refreshIfNeeded {
                try await self.refreshAccessToken()
            }

            guard let updated = TokenStorage.shared.loadTokens() else {
                throw APIError.unauthorized
            }

            req = try makeRequest(updated.accessToken)
            let (data2, resp2) = try await URLSession.shared.data(for: req)
            guard let http2 = resp2 as? HTTPURLResponse else {
                throw APIError.server(status: 0, message: "Invalid response")
            }

            if http2.statusCode == 401 {
                TokenStorage.shared.clear()
                throw APIError.unauthorized
            }

            return (data2, http2)
        }

        return (data, http)
    }

    public func accessTokenExpirationDate() -> Date? {
        guard let tokens = TokenStorage.shared.loadTokens() else { return nil }
        return JWT.expirationDate(from: tokens.accessToken)
    }

    public func secondsUntilAccessTokenExpires(from now: Date = Date()) -> Int? {
        guard let exp = accessTokenExpirationDate() else { return nil }
        return Int(exp.timeIntervalSince(now))
    }
    
    private func mapHTTPError(_ http: HTTPURLResponse, data: Data?) -> APIError {
        let status = http.statusCode

        // Попробуем вытащить {"error": "..."} или {"message": "..."} из JSON
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
}

// MARK: - Error Handling
public enum OAuthError: LocalizedError {
    case invalidURL
    case clientNotRegistered
    case serverError(String)
    case invalidResponse
    case notAuthenticated
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL"
        case .clientNotRegistered: return "Client not registered"
        case .serverError(let message): return "Server error: \(message)"
        case .invalidResponse: return "Invalid server response"
        case .notAuthenticated: return "Not authenticated"
        }
    }
}

