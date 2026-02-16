public struct InternedString: Hashable {
    public let rawValue: Int32

    public static let invalid = InternedString(rawValue: -1)

    public init(rawValue: Int32 = -1) {
        self.rawValue = rawValue
    }
}

public final class StringInterner {
    private var nextID: Int32 = 0
    private var map: [String: Int32] = [:]
    private var values: [String] = []

    public init() {}

    public func intern(_ string: String) -> InternedString {
        if let existing = map[string] {
            return InternedString(rawValue: existing)
        }
        let id = nextID
        nextID += 1
        map[string] = id
        values.append(string)
        return InternedString(rawValue: id)
    }

    public func resolve(_ id: InternedString) -> String {
        let index = Int(id.rawValue)
        guard index >= 0 && index < values.count else {
            return ""
        }
        return values[index]
    }
}

public enum Keyword: String {
    case `as`
    case `break`
    case `class`
    case `catch`
    case `continue`
    case `data`
    case `do`
    case `else`
    case `false`
    case `dynamic`
    case `enum`
    case `external`
    case `for`
    case `fun`
    case `if`
    case `infix`
    case `in`
    case `is`
    case `import`
    case `interface`
    case `finally`
    case `null`
    case `operator`
    case `object`
    case `package`
    case `return`
    case `super`
    case `this`
    case `typealias`
    case `throw`
    case `true`
    case `try`
    case `val`
    case `var`
    case `while`
    case `when`
    case `sealed`
    case `inner`
    case `reified`
    case `open`
    case `private`
    case `public`
    case `protected`
    case `internal`
    case `override`
    case `final`
    case `abstract`
    case `suspend`
    case `inline`
    case `expect`
    case `actual`
    case `constructor`
    case `companion`
    case `annotation`
    case `const`
    case `crossinline`
    case `lateinit`
    case `noinline`
    case `tailrec`
    case `vararg`
    case value
}

public enum SoftKeyword: String {
    case by
    case get
    case set
    case field
    case property
    case receiver
    case param
    case setparam
    case delegate
    case file
    case `where`
    case `init`
    case `constructor`
    case `out`
    case `when`
}

public enum Symbol: String {
    case plus = "+"
    case minus = "-"
    case star = "*"
    case slash = "/"
    case percent = "%"
    case plusPlus = "++"
    case minusMinus = "--"
    case ampAmp = "&&"
    case barBar = "||"
    case bang = "!"
    case equalEqual = "=="
    case bangEqual = "!="
    case lessThan = "<"
    case lessOrEqual = "<="
    case greaterThan = ">"
    case greaterOrEqual = ">="
    case assign = "="
    case plusAssign = "+="
    case minusAssign = "-="
    case starAssign = "*="
    case slashAssign = "/="
    case percentAssign = "%="
    case dotDot = ".."
    case dotDotLt = "..<"
    case questionQuestion = "??"
    case question = "?"
    case questionDot = "?."
    case questionColon = "?:"
    case bangBang = "!!"
    case doubleColon = "::"
    case comma = ","
    case dot = "."
    case semicolon = ";"
    case colon = ":"
    case arrow = "->"
    case fatArrow = "=>"
    case lParen = "("
    case rParen = ")"
    case lBracket = "["
    case rBracket = "]"
    case lBrace = "{"
    case rBrace = "}"
    case at = "@"
    case hash = "#"
}

public enum TriviaPiece: Equatable {
    case spaces(Int)
    case tabs(Int)
    case newline
    case lineComment(String)
    case blockComment(String)
    case shebang(String)
}

public enum TokenKind: Equatable {
    case identifier(InternedString)
    case backtickedIdentifier(InternedString)
    case keyword(Keyword)
    case softKeyword(SoftKeyword)
    case intLiteral(String)
    case longLiteral(String)
    case floatLiteral(String)
    case doubleLiteral(String)
    case charLiteral(UInt32)
    case stringSegment(InternedString)
    case stringQuote
    case rawStringQuote
    case templateExprStart
    case templateExprEnd
    case templateSimpleNameStart
    case symbol(Symbol)
    case eof
    indirect case missing(expected: TokenKind)
}

public struct Token: Equatable {
    public let kind: TokenKind
    public let range: SourceRange
    public let leadingTrivia: [TriviaPiece]
    public let trailingTrivia: [TriviaPiece]

    public init(
        kind: TokenKind,
        range: SourceRange,
        leadingTrivia: [TriviaPiece] = [],
        trailingTrivia: [TriviaPiece] = []
    ) {
        self.kind = kind
        self.range = range
        self.leadingTrivia = leadingTrivia
        self.trailingTrivia = trailingTrivia
    }
}
