import Foundation

nonisolated extension String {
    /// `nil` when the string is empty or only whitespace.
    ///
    /// Used everywhere a field is optional in the model but arrives from a text
    /// field as `""`. Keeps empty strings out of the archive file, so absence
    /// is recorded as absence rather than as an empty value.
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated extension Optional where Wrapped == String {
    var nilIfEmpty: String? { self?.nilIfEmpty }
    var orEmpty: String { self ?? "" }
}

nonisolated extension Array where Element == String {
    /// The list joined for display, or `nil` when there is nothing in it.
    /// Lets a report drop a field rather than print an empty one.
    var nilIfEmptyJoined: String? {
        let kept = compactMap(\.nilIfEmpty)
        return kept.isEmpty ? nil : kept.joined(separator: ", ")
    }
}

nonisolated extension KeyedDecodingContainer {
    /// Decodes a value, falling back to `fallback` when the key is absent or
    /// unreadable.
    ///
    /// The archive file has to outlive many versions of this app. A field added
    /// in 2031 must not make a file written in 2026 undecodable, and a field
    /// removed later must not either. Every model that can grow decodes through
    /// these, so an unknown or missing key degrades instead of failing.
    func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }

    func value<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}
