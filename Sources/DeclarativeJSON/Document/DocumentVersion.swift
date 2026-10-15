import Foundation

/// The version of the document format this build reads: the value of `v` at
/// the root of a document. A document with another version is rejected when
/// it is decoded.
public enum DocumentVersion {
    public static let current = 1
}
