import Foundation
import Supabase

enum SupabaseInfrastructureError: Error, Equatable, Sendable, LocalizedError {
    case notConfigured
    case notAuthenticated
    case network
    case unauthorized
    case server
    case decode
    case invalidResponse
    case accountChanged

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Supabase is not configured."
        case .notAuthenticated:
            "A Supabase session is required for synchronization."
        case .network:
            "The network request could not be completed."
        case .unauthorized:
            "The Supabase session is not authorized."
        case .server:
            "The Supabase server could not complete the request."
        case .decode:
            "The Supabase response could not be decoded."
        case .invalidResponse:
            "The Supabase response was invalid."
        case .accountChanged:
            "The authenticated Supabase account changed during synchronization."
        }
    }

    static func categorize(_ error: Error) -> SupabaseInfrastructureError {
        if let error = error as? SupabaseInfrastructureError {
            return error
        }
        if error is DecodingError {
            return .decode
        }
        if error is URLError {
            return .network
        }
        if let error = error as? AuthError {
            switch error {
            case .sessionMissing:
                return .notAuthenticated
            case let .api(_, _, _, response):
                return response.statusCode == 401 || response.statusCode == 403 ? .unauthorized : .server
            default:
                return .server
            }
        }
        if let error = error as? HTTPError {
            return error.response.statusCode == 401 || error.response.statusCode == 403 ? .unauthorized : .server
        }
        if let error = error as? PostgrestError {
            return error.code == "42501" || error.code == "PGRST301" ? .unauthorized : .server
        }
        return .server
    }
}

/// Safe diagnostic detail retained for a failed push RPC without retaining the
/// original SDK error, response body, request body, or headers.
struct SupabasePushTransportFailure: Error, Sendable {
    let category: SupabaseInfrastructureError
    let httpStatusCode: Int?
    let safeDescription: String

    init(error: Error) {
        // A decoding failure after a successful push RPC represents a malformed
        // server response.
        category = error is DecodingError ? .invalidResponse : SupabaseInfrastructureError.categorize(error)

        if let error = error as? HTTPError {
            httpStatusCode = error.response.statusCode
            safeDescription = "HTTP request failed"
            return
        }

        if let error = error as? AuthError {
            if case let .api(_, _, _, response) = error {
                httpStatusCode = response.statusCode
            } else {
                httpStatusCode = nil
            }
            safeDescription = "Supabase authentication request failed"
            return
        }

        if let error = error as? PostgrestError {
            httpStatusCode = nil
            let code = error.code.map { " code=\($0)" } ?? ""
            safeDescription = "PostgREST\(code): \(Self.safePostgrestMessage(error.message))"
            return
        }

        httpStatusCode = nil
        if error is DecodingError {
            safeDescription = "Supabase response decoding failed"
        } else if let error = error as? URLError {
            safeDescription = "Network request failed (\(error.code.rawValue))"
        } else if let error = error as? SupabaseInfrastructureError {
            safeDescription = error.errorDescription ?? "Supabase infrastructure request failed"
        } else {
            safeDescription = "Supabase request failed"
        }
    }

    private static func safePostgrestMessage(_ message: String) -> String {
        let normalized = message
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sensitiveTerms = ["token", "authorization", "bearer", "apikey", "password", "otp", "session", "jwt", "credential"]
        guard !sensitiveTerms.contains(where: { normalized.localizedCaseInsensitiveContains($0) }) else {
            return "server message redacted"
        }
        return String(normalized.prefix(240))
    }
}

struct SupabaseRemoteSyncRecord: Codable, Equatable, Sendable {
    let key: SyncEntityKey
    let payloadSchemaVersion: Int
    let payload: SyncPayload
    let serverRevision: Int64
    let serverUpdatedAt: Date

    var envelope: SyncPayloadEnvelope {
        SyncPayloadEnvelope(schemaVersion: payloadSchemaVersion, payload: payload)
    }

    init(
        key: SyncEntityKey,
        payloadSchemaVersion: Int,
        payload: SyncPayload,
        serverRevision: Int64,
        serverUpdatedAt: Date,
    ) throws {
        let canonicalPayload = payload.canonicalizedTimestamps()
        guard canonicalPayload.key == key else {
            throw SupabaseInfrastructureError.invalidResponse
        }
        self.key = key
        self.payloadSchemaVersion = payloadSchemaVersion
        self.payload = canonicalPayload
        self.serverRevision = serverRevision
        self.serverUpdatedAt = serverUpdatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case entityType = "entity_type"
        case entityID = "entity_id"
        case payloadSchemaVersion = "payload_schema_version"
        case payload
        case serverRevision = "server_revision"
        case serverUpdatedAt = "server_updated_at"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let key = SyncEntityKey(
            entityType: try container.decode(SyncEntityType.self, forKey: .entityType),
            entityID: try container.decode(UUID.self, forKey: .entityID),
        )
        try self.init(
            key: key,
            payloadSchemaVersion: try container.decode(Int.self, forKey: .payloadSchemaVersion),
            payload: try container.decode(SyncPayload.self, forKey: .payload),
            serverRevision: try container.decode(Int64.self, forKey: .serverRevision),
            serverUpdatedAt: try container.decode(Date.self, forKey: .serverUpdatedAt),
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key.entityType, forKey: .entityType)
        try container.encode(key.entityID, forKey: .entityID)
        try container.encode(payloadSchemaVersion, forKey: .payloadSchemaVersion)
        try container.encode(payload, forKey: .payload)
        try container.encode(serverRevision, forKey: .serverRevision)
        try container.encode(serverUpdatedAt, forKey: .serverUpdatedAt)
    }
}

struct SupabasePushRequest: Encodable, Sendable {
    let entityType: SyncEntityType
    let entityID: UUID
    let payloadSchemaVersion: Int
    let payload: SyncPayload
    let expectedServerRevision: Int64?

    init(
        key: SyncEntityKey,
        envelope: SyncPayloadEnvelope,
        expectedServerRevision: Int64?,
    ) {
        entityType = key.entityType
        entityID = key.entityID
        payloadSchemaVersion = envelope.schemaVersion
        payload = envelope.payload.canonicalizedTimestamps()
        self.expectedServerRevision = expectedServerRevision
    }

    private enum CodingKeys: String, CodingKey {
        case entityType = "p_entity_type"
        case entityID = "p_entity_id"
        case payloadSchemaVersion = "p_payload_schema_version"
        case payload = "p_payload"
        case expectedServerRevision = "p_expected_server_revision"
    }
}

private struct SupabasePushRPCResponse: Decodable, Sendable {
    enum Outcome: String, Sendable {
        case accepted
        case conflict
        case missing
    }

    let outcome: Outcome
    private let currentRevision: Int64?
    private let currentUpdatedAt: Date?
    private let currentPayloadSchemaVersion: Int?
    private let currentPayload: SyncPayload?

    private enum CodingKeys: String, CodingKey {
        case result
        case currentRevision = "current_revision"
        case currentUpdatedAt = "current_updated_at"
        case currentPayloadSchemaVersion = "current_payload_schema_version"
        case currentPayload = "current_payload"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawOutcome = try container.decode(String.self, forKey: .result)
        guard let outcome = Outcome(rawValue: rawOutcome) else {
            throw SupabaseInfrastructureError.invalidResponse
        }

        self.outcome = outcome
        currentRevision = try container.decodeIfPresent(Int64.self, forKey: .currentRevision)
        currentUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .currentUpdatedAt)
        currentPayloadSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .currentPayloadSchemaVersion)
        currentPayload = try container.decodeIfPresent(SyncPayload.self, forKey: .currentPayload)
    }

    func pushResult(for key: SyncEntityKey) throws -> SupabasePushResult {
        switch outcome {
        case .accepted:
            return .accepted(try currentRecord(for: key))
        case .conflict:
            return .conflict(try currentRecord(for: key))
        case .missing:
            return .missing
        }
    }

    private func currentRecord(for key: SyncEntityKey) throws -> SupabaseRemoteSyncRecord {
        guard
            let currentRevision,
            let currentUpdatedAt,
            let currentPayloadSchemaVersion,
            let currentPayload
        else {
            throw SupabaseInfrastructureError.invalidResponse
        }
        return try SupabaseRemoteSyncRecord(
            key: key,
            payloadSchemaVersion: currentPayloadSchemaVersion,
            payload: currentPayload,
            serverRevision: currentRevision,
            serverUpdatedAt: currentUpdatedAt,
        )
    }
}

enum SupabasePushResult: Equatable, Sendable {
    case accepted(SupabaseRemoteSyncRecord)
    case conflict(SupabaseRemoteSyncRecord)
    case missing
}

/// Network-only transport for canonical sync payloads. It neither schedules work nor mutates SwiftData.
actor SupabaseSyncTransport {
    static let defaultPageSize = 200

    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func push(
        key: SyncEntityKey,
        envelope: SyncPayloadEnvelope,
        expectedServerRevision: Int64?,
        expectedAccountID: UUID,
    ) async throws -> SupabasePushResult {
        guard
            envelope.schemaVersion == SyncPayloadFormat.currentSchemaVersion,
            envelope.payload.key == key,
            expectedServerRevision == nil || expectedServerRevision! >= 0
        else {
            throw SupabaseInfrastructureError.invalidResponse
        }

        try await requireAuthenticatedSession(expectedAccountID: expectedAccountID)

        do {
            let request = SupabasePushRequest(
                key: key,
                envelope: envelope,
                expectedServerRevision: expectedServerRevision,
            )
            let response: PostgrestResponse<[SupabasePushRPCResponse]> = try await client
                .rpc("push_sync_record", params: request)
                .execute()
            try await requireAuthenticatedSession(expectedAccountID: expectedAccountID)
            guard response.value.count == 1, let row = response.value.first else {
                throw SupabaseInfrastructureError.invalidResponse
            }
            return try row.pushResult(for: key)
        } catch {
            throw SupabasePushTransportFailure(error: error)
        }
    }

    func fetchChanges(
        after revision: Int64,
        limit: Int = SupabaseSyncTransport.defaultPageSize,
        expectedAccountID: UUID,
    ) async throws -> [SupabaseRemoteSyncRecord] {
        guard revision >= 0, limit > 0 else {
            throw SupabaseInfrastructureError.invalidResponse
        }

        try await requireAuthenticatedSession(expectedAccountID: expectedAccountID)

        do {
            let response: PostgrestResponse<[SupabaseRemoteSyncRecord]> = try await client
                .from("sync_records")
                .select()
                .gt("server_revision", value: String(revision))
                .order("server_revision", ascending: true)
                .limit(limit)
                .execute()
            try await requireAuthenticatedSession(expectedAccountID: expectedAccountID)
            let records = response.value
            guard records.allSatisfy({ $0.serverRevision > revision }) else {
                throw SupabaseInfrastructureError.invalidResponse
            }
            guard zip(records, records.dropFirst()).allSatisfy({ $0.serverRevision < $1.serverRevision }) else {
                throw SupabaseInfrastructureError.invalidResponse
            }
            return records
        } catch {
            throw SupabaseInfrastructureError.categorize(error)
        }
    }

    /// Validates the exact session identity used by the next or just-completed
    /// request. A token refresh for the same account remains valid.
    private func requireAuthenticatedSession(expectedAccountID: UUID) async throws {
        guard client.auth.currentSession != nil else {
            throw SupabaseInfrastructureError.accountChanged
        }

        do {
            let session = try await client.auth.session
            guard !session.isExpired, session.user.id == expectedAccountID else {
                throw SupabaseInfrastructureError.accountChanged
            }
        } catch {
            if let error = error as? SupabaseInfrastructureError {
                throw error
            }
            let category = SupabaseInfrastructureError.categorize(error)
            if category == .notAuthenticated || category == .unauthorized {
                throw SupabaseInfrastructureError.accountChanged
            }
            throw category
        }
    }
}
