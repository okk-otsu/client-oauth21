//
//  OAuthError.swift
//  cli-oauth21
//
//  Created by MacBook on 01.03.2026.
//


import Foundation

enum OAuthError: LocalizedError, Equatable {
    case invalidURL
    case clientNotRegistered
    case invalidResponse
    case notAuthenticated
    case internalError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Неверный URL сервера."
        case .clientNotRegistered:
            return "Клиент не зарегистрирован. Попробуйте сбросить и начать заново."
        case .invalidResponse:
            return "Неожиданный ответ сервера."
        case .notAuthenticated:
            return "Вы не авторизованы."
        case .internalError(let msg):
            return msg
        }
    }
}
