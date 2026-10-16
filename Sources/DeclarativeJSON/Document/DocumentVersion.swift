import Foundation

/// The version of the document format this build reads.
public enum DocumentVersion {
    /// The value of `v` at the root of a document. A document with another
    /// version is rejected when it is decoded.
    public static let current = 1
    /// The additions to version `current` this build reads. A release that
    /// adds to what a document can say raises it by one; 0 is version 1 as
    /// first released. An app sends it with its requests, so that the backend
    /// writes only what the app reads.
    public static let minor = 6
}
