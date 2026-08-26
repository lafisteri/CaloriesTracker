import Foundation
import Supabase

struct SupabaseAuthSession: Equatable, Sendable {
    let userID: UUID
    let email: String?
    let expiresAt: Date

    init(session: Session) {
        userID = session.user.id
        email = session.user.email
        expiresAt = Date(timeIntervalSince1970: session.expiresAt)
    }
}

/// Passwordless email-OTP authentication for the optional Supabase transport.
actor SupabaseAuthService {
    typealias SessionLifecycleHandler = @Sendable () async -> Void

    private let client: SupabaseClient
    private var sessionAvailableHandler: SessionLifecycleHandler?
    private var sessionEndedHandler: SessionLifecycleHandler?

    init(client: SupabaseClient) {
        self.client = client
    }

    func setSessionLifecycleHandlers(
        onSessionAvailable: @escaping SessionLifecycleHandler,
        onSessionEnded: @escaping SessionLifecycleHandler,
    ) {
        sessionAvailableHandler = onSessionAvailable
        sessionEndedHandler = onSessionEnded
    }

    func requestOTP(email: String) async throws {
        do {
            try await client.auth.signInWithOTP(
                email: email,
                shouldCreateUser: true,
            )
        } catch {
            throw SupabaseInfrastructureError.categorize(error)
        }
    }

    @discardableResult
    func verifyOTP(email: String, token: String) async throws -> SupabaseAuthSession {
        do {
            let response = try await client.auth.verifyOTP(
                email: email,
                token: token,
                type: .email,
            )
            guard let session = response.session else {
                throw SupabaseInfrastructureError.invalidResponse
            }
            let authenticatedSession = SupabaseAuthSession(session: session)
            if let sessionAvailableHandler {
                await sessionAvailableHandler()
            }
            return authenticatedSession
        } catch {
            throw SupabaseInfrastructureError.categorize(error)
        }
    }

    /// Returns the restored, valid session when one is stored by the SDK.
    func currentSession() async throws -> SupabaseAuthSession? {
        guard client.auth.currentSession != nil else {
            return nil
        }

        do {
            let session = try await client.auth.session
            return SupabaseAuthSession(session: session)
        } catch {
            let categorized = SupabaseInfrastructureError.categorize(error)
            if categorized == .notAuthenticated || categorized == .unauthorized {
                return nil
            }
            throw categorized
        }
    }

    func signOut() async throws {
        do {
            try await client.auth.signOut()
            if let sessionEndedHandler {
                await sessionEndedHandler()
            }
        } catch {
            throw SupabaseInfrastructureError.categorize(error)
        }
    }
}
