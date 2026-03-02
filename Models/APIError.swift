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
    case decoding
    case network

    var errorDescription: String? {
        switch self {
        case .badRequest:
            return "Неверный запрос. Проверьте данные."
        case .unauthorized:
            return "Сессия истекла. Войдите снова."
        case .rateLimited(let retryAfter):
            if let s = retryAfter {
                return "Слишком много попыток. Подождите \(s) сек."
            } else {
                return "Слишком много попыток. Подождите немного."
            }
        case .server(let status, _):
            return "Ошибка сервера (HTTP \(status)). Попробуйте позже."
        case .decoding:
            return "Ошибка обработки ответа сервера."
        case .network:
            return "Нет соединения с сервером."
        }
    }
}
