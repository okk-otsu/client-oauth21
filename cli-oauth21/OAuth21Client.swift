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
    
    public init() {}
    
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
        
        // Debug output
        if let responseString = String(data: data, encoding: .utf8) {
            print("User registration response: \(responseString)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.serverError("Invalid response from server")
        }
        
        print("User registration status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode == 201 {
            print("User \(username) registered successfully")
        } else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OAuthError.serverError("User registration failed: \(errorMessage)")
        }
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
        if let accessToken = tokens["access_token"] as? String {
            KeychainHelper.shared.save(accessToken, for: "access_token")
            print("Access token saved")
        }
        if let refreshToken = tokens["refresh_token"] as? String {
            KeychainHelper.shared.save(refreshToken, for: "refresh_token")
            print("Refresh token saved")
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
        guard let accessToken = KeychainHelper.shared.load(for: "access_token") else {
            throw OAuthError.notAuthenticated
        }
        
        guard let url = URL(string: "\(baseURL)/userinfo") else {
            throw OAuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Debug output
        if let responseString = String(data: data, encoding: .utf8) {
            print("=== USERINFO RESPONSE ===")
            print("Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            print("Response: \(responseString)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.serverError("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OAuthError.serverError("Failed to fetch user info: \(errorMessage)")
        }
        
        guard let userInfo = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthError.serverError("Invalid user info response format")
        }
        
        await MainActor.run {
            self.userInfo = userInfo
        }
        
        return userInfo
    }
    
    public func logout() {
        KeychainHelper.shared.delete(for: "access_token")
        KeychainHelper.shared.delete(for: "refresh_token")
        
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

// MARK: - Keychain Helper
class KeychainHelper {
    static let shared = KeychainHelper()
    
    private init() {}
    
    func save(_ data: String, for key: String) {
        let data = Data(data.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    func load(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        guard status == errSecSuccess, let data = dataTypeRef as? Data else {
            return nil
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    func delete(for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
