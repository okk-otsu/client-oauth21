//
//  AuthFlowViewModel.swift
//  cli-oauth21
//
//  Created by MacBook on 01.03.2026.
//

import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    enum AuthMode: String, CaseIterable, Identifiable {
        case login = "Login"
        case register = "Register"
        var id: String { rawValue }
    }

    @Published var username: String = ""
    @Published var password: String = ""
    @Published var clientName: String = "Demo iOS App"

    @Published var mode: AuthMode = .login

    @Published var isLoading: Bool = false
    @Published var isAuthenticated: Bool = false
    @Published var isCheckingSession: Bool = true
    @Published var userInfo: [String: Any]?
    @Published var error: String?

    private let api: OAuthAPI

    init(api: OAuthAPI = OAuthAPI()) {
        self.api = api
        Task { await bootstrapOnLaunch() }
    }

    private var isClientRegistered: Bool {
        UserDefaults.standard.string(forKey: OAuthAPI.clientIdDefaultsKey) != nil
    }

    // MARK: - Task 2: App bootstrap
    func bootstrapOnLaunch() async {
        isCheckingSession = true
        defer { isCheckingSession = false }

        if !isClientRegistered {
            do {
                _ = try await api.registerClient(clientName: clientName)
            } catch {
                self.error = Self.describe(error)
                self.isAuthenticated = false
                self.userInfo = nil
                return
            }
        }

        guard TokenStorage.shared.loadTokens() != nil else {
            isAuthenticated = false
            userInfo = nil
            return
        }

        do {
            let info = try await api.fetchUserInfo()
            userInfo = info
            isAuthenticated = true
        } catch {
            TokenStorage.shared.clear()
            userInfo = nil
            isAuthenticated = false
        }
    }

    // MARK: - Unified auth action (single screen)
    func continueAuth() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if mode == .register {
                try await api.registerUser(username: username, password: password)
            }

            _ = try await api.authenticate(username: username, password: password)

            isAuthenticated = true
            error = nil

            do {
                userInfo = try await api.fetchUserInfo()
            } catch {
                print("fetchUserInfo failed after auth:", error)
                userInfo = nil
            }
        } catch {
            self.error = Self.describe(error)
        }
    }

    func getUserInfo() async {
        await run { [self] in
            userInfo = try await api.fetchUserInfo()
        }
    }

    // MARK: - Logout (Task 2)
    func logout() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await api.revokeAccessToken()
        } catch {
            print("revoke failed:", error)
        }

        TokenStorage.shared.clear()
        userInfo = nil
        isAuthenticated = false
        error = nil
    }

    func resetAll() {
        TokenStorage.shared.clear()
        UserDefaults.standard.removeObject(forKey: OAuthAPI.clientIdDefaultsKey)

        username = ""
        password = ""
        userInfo = nil

        isAuthenticated = false
        mode = .login
        error = nil
    }

    func accessTokenExpirationDate() -> Date? {
        api.accessTokenExpirationDate()
    }

    func secondsUntilAccessTokenExpires(from now: Date = Date()) -> Int? {
        api.secondsUntilAccessTokenExpires(from: now)
    }

    // MARK: - Helpers
    private func run(_ work: @escaping () async throws -> Void) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await work()
            error = nil
        } catch {
            self.error = Self.describe(error)
        }
    }

    private static func describe(_ error: Error) -> String {
        if let le = error as? LocalizedError, let desc = le.errorDescription {
            return desc
        }
        return String(describing: error)
    }
    
    func refreshTokenManually() async {
        await run { [self] in
            try await api.refreshTokensManually()
            userInfo = try await api.fetchUserInfo()
        }
    }
}
