//
//  TokenRefresher.swift
//  cli-oauth21
//
//  Created by MacBook on 16.02.2026.
//

import Foundation

actor TokenRefresher {
    static let shared = TokenRefresher()
    private var inFlight: Task<Void, Error>?

    func refreshOnce(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        if let inFlight {
            try await inFlight.value
            return
        }

        let task = Task { try await operation() }
        inFlight = task
        defer { inFlight = nil }

        try await task.value
    }
}
