//
//  TokenStorage.swift
//  cli-oauth21
//
//  Created by MacBook on 16.02.2026.
//

import Foundation

struct OAuthTokens: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
}

final class TokenStorage {
    static let shared = TokenStorage()
    private init() {}

    private enum Keys {
        static let tokens = "oauth.tokens"
    }

    func save(tokens: OAuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        try KeychainService.shared.save(data, account: Keys.tokens)
    }

    func loadTokens() -> OAuthTokens? {
        do {
            let data = try KeychainService.shared.load(account: Keys.tokens)
            return try JSONDecoder().decode(OAuthTokens.self, from: data)
        } catch {
            return nil
        }
    }

    func clear() {
        try? KeychainService.shared.delete(account: Keys.tokens)
    }
}
