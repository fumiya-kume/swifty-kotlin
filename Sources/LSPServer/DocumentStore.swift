import Foundation

/// Conversion helpers between LSP document URIs and filesystem paths.
public enum DocumentURI {
    /// Returns the filesystem path for a `file://` URI, or `nil` for other
    /// schemes.
    public static func path(fromURI uri: String) -> String? {
        if let url = URL(string: uri), url.isFileURL {
            return url.path
        }
        if uri.hasPrefix("file://") {
            let raw = String(uri.dropFirst("file://".count))
            return raw.removingPercentEncoding ?? raw
        }
        return nil
    }

    /// Returns a `file://` URI for a filesystem path.
    public static func uri(fromPath path: String) -> String {
        URL(fileURLWithPath: path).absoluteString
    }
}

/// In-memory store of the documents currently open in the editor.
public final class DocumentStore {
    public struct Document {
        public var uri: String
        public var languageId: String?
        public var version: Int?
        public var text: String
    }

    private var documents: [String: Document] = [:]

    public init() {}

    public func open(uri: String, languageId: String?, version: Int?, text: String) {
        documents[uri] = Document(uri: uri, languageId: languageId, version: version, text: text)
    }

    public func update(uri: String, version: Int?, text: String) {
        if var existing = documents[uri] {
            existing.version = version
            existing.text = text
            documents[uri] = existing
        } else {
            documents[uri] = Document(uri: uri, languageId: nil, version: version, text: text)
        }
    }

    public func close(uri: String) {
        documents.removeValue(forKey: uri)
    }

    public func document(for uri: String) -> Document? {
        documents[uri]
    }

    public func text(for uri: String) -> String? {
        documents[uri]?.text
    }

    public func version(for uri: String) -> Int? {
        documents[uri]?.version
    }

    public func allURIs() -> [String] {
        Array(documents.keys)
    }
}
