import Foundation
import Supabase

struct SupabaseClientConfiguration: Sendable {
    let url: URL
    let publishableKey: String

    static func load(from bundle: Bundle = .main) -> SupabaseClientConfiguration? {
        guard
            let urlString = normalizedValue(for: "SupabaseURL", in: bundle),
            let url = URL(string: urlString),
            url.scheme == "https",
            url.host != nil,
            let publishableKey = normalizedValue(for: "SupabasePublishableKey", in: bundle)
        else {
            return nil
        }

        return SupabaseClientConfiguration(url: url, publishableKey: publishableKey)
    }

    private static func normalizedValue(for key: String, in bundle: Bundle) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !normalized.contains("$(") else {
            return nil
        }
        return normalized
    }
}

/// Owns the single Supabase client for the lifetime of the app.
@MainActor
final class SupabaseClientProvider {
    let client: SupabaseClient

    init(configuration: SupabaseClientConfiguration) {
        client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey,
            options: SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true),
            ),
        )
    }

    static func makeFromMainBundle() -> SupabaseClientProvider? {
        guard let configuration = SupabaseClientConfiguration.load() else {
            return nil
        }
        return SupabaseClientProvider(configuration: configuration)
    }
}
