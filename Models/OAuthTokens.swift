//
//  OAuthTokens.swift
//  cli-oauth21
//
//  Created by MacBook on 01.03.2026.
//

struct OAuthTokens: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
}
