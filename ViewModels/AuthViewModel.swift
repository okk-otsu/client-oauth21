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
    @Published var successMessage: String?

    private let api: OAuthAPI

    init(api: OAuthAPI = OAuthAPI()) {
        self.api = api
        Task { await bootstrapOnLaunch() }
    }

    private var isClientRegistered: Bool {
        UserDefaults.standard.string(forKey: OAuthAPI.clientIdDefaultsKey) != nil
    }

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

    func continueAuth() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if mode == .register {
                do {
                    try await api.registerUser(username: username, password: password)
                } catch let apiErr as APIError {
                    // ✅ UX: если юзер уже существует — не показываем "Неверный запрос"
                    // а даём нормальный текст и переключаемся на Login.
                    if case .badRequest(let message) = apiErr,
                       Self.looksLikeUserExists(message) {
                        self.mode = .login
                        self.error = "Пользователь уже существует. Войдите."
                        return
                    }
                    throw apiErr
                }
            }

            _ = try await api.authenticate(
                username: username,
                password: password,
                clientNameForAutoRegistration: clientName
            )

            isAuthenticated = true
            error = nil

            userInfo = try await api.fetchUserInfo()

            if mode == .login {
                successMessage = "Вы вошли в аккаунт."
            } else {
                successMessage = "Регистрация и вход выполнены."
            }
        } catch {
            self.error = Self.describe(error)
        }
    }

    func getUserInfo() async {
        await run {
            self.userInfo = try await self.api.fetchUserInfo()
        }
    }

    func refreshTokenManually() async {
        await run {
            try await self.api.refreshTokensManually(clientNameForAutoRegistration: self.clientName)
            self.userInfo = try await self.api.fetchUserInfo()
            self.successMessage = "Токен обновлён."
        }
    }

    func logout() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await api.revokeAccessToken(clientNameForAutoRegistration: clientName)
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
        successMessage = nil
    }

    func accessTokenExpirationDate() -> Date? {
        api.accessTokenExpirationDate()
    }

    func secondsUntilAccessTokenExpires(from now: Date = Date()) -> Int? {
        api.secondsUntilAccessTokenExpires(from: now)
    }

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

    private static func looksLikeUserExists(_ message: String?) -> Bool {
        guard let m = message?.lowercased() else { return false }
        return m.contains("exists") || m.contains("already") || m.contains("занят") || m.contains("существ")
    }

    private static func describe(_ error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .badRequest:
                return "Неверный запрос. Проверьте данные."
            case .unauthorized:
                return "Сессия истекла. Войдите снова."
            case .rateLimited:
                return "Слишком много попыток. Подождите немного."
            case .network:
                return "Нет соединения с сервером."
            case .server(let status, _):
                return "Ошибка сервера (HTTP \(status)). Попробуйте позже."
            case .decoding:
                return "Ошибка обработки ответа сервера."
            }
        }

        if let le = error as? LocalizedError, let desc = le.errorDescription {
            return desc
        }
        return String(describing: error)
    }
}
