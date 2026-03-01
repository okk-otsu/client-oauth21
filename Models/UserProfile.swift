//
//  UserProfile.swift
//  cli-oauth21
//
//  Created by MacBook on 01.03.2026.
//


import Foundation

struct UserProfile: Codable, Equatable {
    let sub: String
    let preferred_username: String?
    let name: String?
    let updated_at: TimeInterval?

    var displayUsername: String {
        preferred_username ?? name ?? "—"
    }

    var updatedAtText: String {
        guard let updated_at else { return "—" }
        let date = Date(timeIntervalSince1970: updated_at)
        return date.formatted(date: .numeric, time: .omitted)
    }

    init(sub: String, preferred_username: String?, name: String?, updated_at: TimeInterval?) {
        self.sub = sub
        self.preferred_username = preferred_username
        self.name = name
        self.updated_at = updated_at
    }

    init?(from userInfo: [String: Any]) {
        guard let sub = userInfo["sub"] as? String else { return nil }

        let preferred = userInfo["preferred_username"] as? String
        let name = userInfo["name"] as? String

        var updated: TimeInterval? = nil
        if let intVal = userInfo["updated_at"] as? Int {
            updated = TimeInterval(intVal)
        } else if let doubleVal = userInfo["updated_at"] as? Double {
            updated = doubleVal
        } else if let stringVal = userInfo["updated_at"] as? String, let doubleFromString = Double(stringVal) {
            updated = doubleFromString
        }

        self.init(sub: sub, preferred_username: preferred, name: name, updated_at: updated)
    }
}