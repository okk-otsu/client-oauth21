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
        case .badRequest(let message):

            if let message {
                if message.lowercased().contains("invalid credentials") {
                    return String(localized: "error.invalidCredentials")
                }
            }

            return message ?? String(localized: "error.badRequest.default")

        case .unauthorized:
            return String(localized: "error.unauthorized")

        case .rateLimited(let retryAfter):
            if let s = retryAfter {
                return String.localizedStringWithFormat(
                    String(localized: "error.rateLimited.retryAfter"),
                    s
                )
            }
            return String(localized: "error.rateLimited.default")

        case .server(let status, _):
            return String.localizedStringWithFormat(
                String(localized: "error.server"),
                status
            )

        case .network:
            return String(localized: "error.network")

        case .decoding:
            return String(localized: "error.decoding")
        }
    }
}
