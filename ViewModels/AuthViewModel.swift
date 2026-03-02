//
//  AuthFlowViewModel.swift
//  cli-oauth21
//
//  Created by MacBook on 01.03.2026.
//

import Foundation

@MainActor
final class AuthViewModel: ObservableObject {

    enum AuthMode {
        case login
        case register
    }

    @Published var username: String = ""
    @Published var password: String = ""

    @Published var isLoading: Bool = false
    @Published var isAuthenticated: Bool = false
    @Published var isCheckingSession: Bool = true

    @Published var userInfo: [String: Any]?
    @Published var errorMessage: String?
    @Published var successMessage: String?

    @Published var mode: AuthMode = .login

    private let api = OAuthAPI()

    init() {
        Task { await bootstrapOnLaunch() }
    }

    // MARK: - Launch Check

    func bootstrapOnLaunch() async {
        isCheckingSession = true
        defer { isCheckingSession = false }

        guard TokenStorage.shared.loadTokens() != nil else {
            isAuthenticated = false
            return
        }

        do {
            userInfo = try await api.fetchUserInfo()
            isAuthenticated = true
        } catch {
            TokenStorage.shared.clear()
            isAuthenticated = false
        }
    }

    // MARK: - Main Auth Flow

    func continueAuth() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if mode == .register {
                try await api.registerUser(username: username, password: password)
            }

            _ = try await api.authenticate(username: username, password: password)

            isAuthenticated = true
            errorMessage = nil

            if mode == .login {
                successMessage = String(localized: "success.loggedIn")
            } else {
                successMessage = String(localized: "success.registeredAndLoggedIn")
            }

            do {
                userInfo = try await api.fetchUserInfo()
            } catch {
                userInfo = nil
            }

        } catch {
            errorMessage = describe(error)
        }
    }

    // MARK: - Token Refresh

    func refreshTokenManually() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await api.refreshTokensManually()
            userInfo = try await api.fetchUserInfo()
            successMessage = String(localized: "success.tokenRefreshed")
        } catch {
            errorMessage = describe(error)
        }
    }

    // MARK: - Logout

    func logout() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await api.revokeAccessToken()
        } catch { }

        TokenStorage.shared.clear()
        userInfo = nil
        isAuthenticated = false
        errorMessage = nil
        successMessage = nil
    }

    // MARK: - Reset

    func resetAll() {
        TokenStorage.shared.clear()
        username = ""
        password = ""
        userInfo = nil
        isAuthenticated = false
        mode = .login
        errorMessage = nil
        successMessage = nil
    }

    // MARK: - Expiration

    func secondsUntilAccessTokenExpires(from now: Date = Date()) -> Int? {
        api.secondsUntilAccessTokenExpires(from: now)
    }

    // MARK: - Error Description

    private func describe(_ error: Error) -> String {
        if let le = error as? LocalizedError,
           let desc = le.errorDescription {
            return desc
        }
        return String(describing: error)
    }
}
