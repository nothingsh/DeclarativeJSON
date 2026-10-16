import Foundation

/// Reads a document, or a patch, from JSON.
public struct DocumentDecoder {
    public init() {}

    /// Throws `DocumentError.unsupportedVersion` for a document of another
    /// version, and `DecodingError` when the JSON is malformed or the outline
    /// of the document is not right.
    public func decode(_ data: Data) throws -> Document {
        try JSONDecoder().decode(Document.self, from: data)
    }

    /// Reads a patch, for `DocumentViewController.apply(_:)`. Throws as
    /// `decode(_:)` does.
    public func decodePatch(_ data: Data) throws -> Patch {
        try JSONDecoder().decode(Patch.self, from: data)
    }
}
