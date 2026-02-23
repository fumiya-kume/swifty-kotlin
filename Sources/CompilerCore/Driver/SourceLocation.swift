public struct TokenID: Hashable, Sendable {
    public let rawValue: Int32

    public static let invalid = TokenID(rawValue: -1)

    public init(rawValue: Int32 = -1) {
        self.rawValue = rawValue
    }
}

public struct NodeID: Hashable, Sendable {
    public let rawValue: Int32

    public static let invalid = NodeID(rawValue: -1)

    public init(rawValue: Int32 = -1) {
        self.rawValue = rawValue
    }
}

public struct DeclID: Hashable, Sendable {
    public let rawValue: Int32

    public static let invalid = DeclID(rawValue: -1)

    public init(rawValue: Int32 = -1) {
        self.rawValue = rawValue
    }
}

public struct FileID: Hashable, Sendable {
    public let rawValue: Int32

    public static let invalid = FileID(rawValue: -1)

    public init(rawValue: Int32 = -1) {
        self.rawValue = rawValue
    }

    public init(rawValue: Int) {
        self.rawValue = Int32(rawValue)
    }
}

public struct SourceLocation: Equatable, Sendable {
    public let file: FileID
    public let offset: Int

    public init(file: FileID, offset: Int) {
        self.file = file
        self.offset = offset
    }
}

public struct SourceRange: Equatable, Sendable {
    public let start: SourceLocation
    public let end: SourceLocation

    public init(start: SourceLocation, end: SourceLocation) {
        self.start = start
        self.end = end
    }
}

public struct LineColumn: Equatable, Sendable {
    public let line: Int
    public let column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }
}
