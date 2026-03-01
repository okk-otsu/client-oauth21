//
//  OAuthError.swift
//  cli-oauth21
//
//  Created by MacBook on 01.03.2026.
//


import Foundation

enum OAuthError: LocalizedError {
    case invalidURL
    case clientNotRegistered
    case serverError(String)
    case invalidResponse(String)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .clientNotRegistered:
            return "Client not registered (call Register Client)"
        case .serverError(let message):
            return "Server error: \(message)"
        case .invalidResponse(let details):
            return "Authorization failed: \(details)"
        case .notAuthenticated:
            return "Not authenticated"
        }
    }
}
