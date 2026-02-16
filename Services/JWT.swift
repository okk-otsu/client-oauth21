//
//  JWT.swift
//  cli-oauth21
//
//  Created by MacBook on 16.02.2026.
//

import Foundation

enum JWT {
    static func payload(from token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        let payloadPart = String(parts[1])
        guard let data = base64URLDecode(payloadPart) else { return nil }

        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func expirationDate(from token: String) -> Date? {
        guard let payload = payload(from: token) else { return nil }

        // exp обычно Int (секунды unix time)
        if let exp = payload["exp"] as? TimeInterval {
            return Date(timeIntervalSince1970: exp)
        }
        if let expInt = payload["exp"] as? Int {
            return Date(timeIntervalSince1970: TimeInterval(expInt))
        }
        return nil
    }

    private static func base64URLDecode(_ input: String) -> Data? {
        var base64 = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        return Data(base64Encoded: base64)
    }
}
