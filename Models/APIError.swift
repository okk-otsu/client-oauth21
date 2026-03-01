//
//  APIError.swift
//  cli-oauth21
//
//  Created by MacBook on 16.02.2026.
//

import Foundation

enum APIError: LocalizedError, Equatable {
    case badRequest(message: String?)
    case unauthorized
    case rateLimited(retryAfter: Int?)
    case server(status: Int, message: String?)
    case network
    case decoding

    var errorDescription: String? {
        switch self {
        case .badRequest(let msg):
            return msg ?? "Неверный запрос. Проверьте введённые данные."
        case .unauthorized:
            return "Сессия истекла. Войдите снова."
        case .rateLimited(let retryAfter):
            if let s = retryAfter { return "Слишком много запросов. Подождите \(s) сек." }
            return "Слишком много запросов. Подождите немного и попробуйте снова."
        case .server(let status, _):
            return "Ошибка сервера (HTTP \(status)). Попробуйте позже."
        case .network:
            return "Проблема с интернетом. Проверьте соединение."
        case .decoding:
            return "Не удалось обработать ответ сервера."
        }
    }
}
