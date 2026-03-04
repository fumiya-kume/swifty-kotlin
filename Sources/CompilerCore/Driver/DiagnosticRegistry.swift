// swiftlint:disable file_length type_body_length trailing_comma
import Foundation

/// Describes a single code action (quick-fix) that an LSP client can offer to the user.
public struct DiagnosticCodeAction: Equatable, Sendable {
    /// Human-readable title shown in the editor UI.
    public let title: String
    /// LSP code action kind (e.g. "quickfix", "refactor").
    public let kind: String

    public init(title: String, kind: String = "quickfix") {
        self.title = title
        self.kind = kind
    }
}

/// Metadata describing a registered diagnostic code.
public struct DiagnosticDescriptor: Equatable, Sendable {
    /// The canonical code string (e.g. "KSWIFTK-SEMA-0014").
    public let code: String
    /// Which compiler pass this diagnostic originates from.
    public let pass: String
    /// Default severity for this diagnostic.
    public let defaultSeverity: DiagnosticSeverity
    /// Short human-readable summary of what the diagnostic means.
    public let summary: String
    /// Default code actions (quick-fixes) available for this diagnostic.
    public let codeActions: [DiagnosticCodeAction]

    public init(
        code: String,
        pass: String,
        defaultSeverity: DiagnosticSeverity,
        summary: String,
        codeActions: [DiagnosticCodeAction] = []
    ) {
        self.code = code
        self.pass = pass
        self.defaultSeverity = defaultSeverity
        self.summary = summary
        self.codeActions = codeActions
    }
}

/// Central registry of all diagnostic codes emitted by the KSwiftK compiler.
///
/// Every diagnostic follows the `KSWIFTK-{PASS}-{CODE}` naming convention where
/// `{PASS}` identifies the compiler pass (LEX, PARSE, SEMA, TYPE, LIB, KIR,
/// CORO, BACKEND, LINK, PIPELINE, ICE) and `{CODE}` is a numeric or mnemonic
/// identifier unique within that pass.
public enum DiagnosticRegistry {
    /// All registered diagnostic descriptors, keyed by their code string.
    public static let descriptors: [String: DiagnosticDescriptor] = {
        var map: [String: DiagnosticDescriptor] = [:]
        for descriptor in allDescriptors {
            map[descriptor.code] = descriptor
        }
        return map
    }()

    /// Look up a descriptor by its diagnostic code.
    public static func lookup(_ code: String) -> DiagnosticDescriptor? {
        descriptors[code]
    }

    /// All registered codes as a sorted array.
    public static var allCodes: [String] {
        allDescriptors.map(\.code).sorted()
    }

    // MARK: - Lexer pass (LEX)

    static let lexDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-LEX-0001",
            pass: "LEX",
            defaultSeverity: .error,
            summary: "Unterminated string literal.",
            codeActions: [DiagnosticCodeAction(title: "Close string literal with matching quote")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LEX-0002",
            pass: "LEX",
            defaultSeverity: .error,
            summary: "Unexpected character in input.",
            codeActions: [DiagnosticCodeAction(title: "Remove unexpected character")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LEX-0003",
            pass: "LEX",
            defaultSeverity: .error,
            summary: "Invalid numeric literal."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LEX-0004",
            pass: "LEX",
            defaultSeverity: .error,
            summary: "Invalid escape sequence in string."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LEX-0006",
            pass: "LEX",
            defaultSeverity: .error,
            summary: "Malformed number literal (overflow or bad format)."
        ),
    ]

    // MARK: - Parser pass (PARSE)

    static let parseDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0001",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Expected keyword in declaration."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0002",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Expected declaration name.",
            codeActions: [DiagnosticCodeAction(title: "Insert placeholder name")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0003",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Expected name in package or import path."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0004",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Expected expression."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0005",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Expected type name or alias name."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0006",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Unexpected token in declaration."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0010",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Expected closing delimiter in statement."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PARSE-0011",
            pass: "PARSE",
            defaultSeverity: .error,
            summary: "Malformed statement."
        ),
    ]

    // MARK: - Semantic analysis pass (SEMA)

    static let semaDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0002",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "No matching overload found for call."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0003",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Ambiguous overload resolution."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0004",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Return type mismatch.",
            codeActions: [DiagnosticCodeAction(title: "Change return type annotation to match expression")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0005",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Missing return type annotation.",
            codeActions: [DiagnosticCodeAction(title: "Add explicit return type annotation")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0013",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Unresolved reference in local scope."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0014",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Type mismatch in assignment or initialization.",
            codeActions: [DiagnosticCodeAction(title: "Add explicit type cast")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0018",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Cannot apply unary operator to operand type."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0019",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Cannot apply binary operator to operand types."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0021",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Duplicate declaration in scope."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0022",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Unresolved reference.",
            codeActions: [DiagnosticCodeAction(title: "Check spelling or add import for symbol")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0023",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Unresolved type reference."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0024",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Unresolved member function call."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0025",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Type mismatch in argument."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0031",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Null safety violation on non-nullable type."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0032",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Incompatible types in when-branch condition."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0040",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Cannot access private member.",
            codeActions: [DiagnosticCodeAction(title: "Change visibility to 'internal'")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0041",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Cannot access protected member.",
            codeActions: [DiagnosticCodeAction(title: "Change visibility to 'public'")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0042",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Invalid operator application."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0050",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Invalid is-check target type."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0051",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Invalid as-cast source type."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0052",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Invalid as-cast target type."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0053",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Unsafe cast requires 'as?' form."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0054",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Invalid is-check on non-class type."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0061",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Conflicting member declaration."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0062",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Type parameter constraint violation."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0071",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Non-exhaustive when expression (missing branches)."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0072",
            pass: "SEMA",
            defaultSeverity: .warning,
            summary: "Redundant branch in when expression."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0073",
            pass: "SEMA",
            defaultSeverity: .warning,
            summary: "Unreachable branch in when expression."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0080",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Const property not initialized with compile-time constant.",
            codeActions: [DiagnosticCodeAction(title: "Remove 'const' modifier")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0081",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Const property must have an initializer."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0082",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Const property must be of a primitive type."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0083",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Const val initializer must be a compile-time constant expression."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0084",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Invalid use in constant context."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0096",
            pass: "SEMA",
            defaultSeverity: .warning,
            summary: "Unnecessary safe call on non-nullable receiver."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0097",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Cannot apply prefix operator to operand type."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-0098",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Cannot apply postfix operator to operand type."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-TAILREC",
            pass: "SEMA",
            defaultSeverity: .warning,
            summary: "Function marked 'tailrec' but last expression is not a self-recursive call."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-DIAMOND",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Diamond inheritance conflict requires explicit override.",
            codeActions: [DiagnosticCodeAction(title: "Add explicit override to resolve diamond conflict")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-FIELD",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Unresolved member access.",
            codeActions: [DiagnosticCodeAction(title: "Check member name spelling")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-FINAL",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Cannot override final member.",
            codeActions: [DiagnosticCodeAction(title: "Remove 'final' modifier from base declaration")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-INFER",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Type inference constraint failure."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-OVERRIDE",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Missing 'override' keyword on overriding member.",
            codeActions: [DiagnosticCodeAction(title: "Add 'override' keyword")]
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-REIFIED",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Cannot use non-reified type parameter in reified context."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-BOUND",
            pass: "SEMA",
            defaultSeverity: .error,
            summary: "Type argument does not satisfy upper bound constraint."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-SEMA-PLATFORM",
            pass: "SEMA",
            defaultSeverity: .warning,
            summary: "Platform-typed expression used without null check; may throw NullPointerException at runtime.",
            codeActions: [DiagnosticCodeAction(title: "Add null check before use")]
        ),
    ]

    // MARK: - Type resolution pass (TYPE)

    static let typeDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-TYPE-0003",
            pass: "TYPE",
            defaultSeverity: .error,
            summary: "Unresolved type in declaration."
        ),
    ]

    // MARK: - Library import pass (LIB)

    static let libDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0001",
            pass: "LIB",
            defaultSeverity: .warning,
            summary: "Library metadata format version mismatch."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0002",
            pass: "LIB",
            defaultSeverity: .warning,
            summary: "Inline function body not available from library."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0003",
            pass: "LIB",
            defaultSeverity: .warning,
            summary: "Library layout field not found."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0004",
            pass: "LIB",
            defaultSeverity: .warning,
            summary: "Library layout size mismatch."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0005",
            pass: "LIB",
            defaultSeverity: .warning,
            summary: "Library layout hint ignored."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0007",
            pass: "LIB",
            defaultSeverity: .warning,
            summary: "Imported library symbol not resolved."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0010",
            pass: "LIB",
            defaultSeverity: .error,
            summary: "Library discovery: unresolvable import."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0011",
            pass: "LIB",
            defaultSeverity: .error,
            summary: "Library discovery: module not found."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0012",
            pass: "LIB",
            defaultSeverity: .error,
            summary: "Library discovery: metadata parse failure."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0013",
            pass: "LIB",
            defaultSeverity: .error,
            summary: "Library discovery: symbol conflict."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0014",
            pass: "LIB",
            defaultSeverity: .warning,
            summary: "Library discovery: partial metadata."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0015",
            pass: "LIB",
            defaultSeverity: .error,
            summary: "Library search path not found."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LIB-0016",
            pass: "LIB",
            defaultSeverity: .warning,
            summary: "Library discovery: search path warning."
        ),
    ]

    // MARK: - KIR generation pass (KIR)

    static let kirDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-KIR-0001",
            pass: "KIR",
            defaultSeverity: .warning,
            summary: "KIR generation encountered unsupported construct."
        ),
    ]

    // MARK: - Coroutine lowering pass (CORO)

    static let coroDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-CORO-0001",
            pass: "CORO",
            defaultSeverity: .error,
            summary: "Suspend function call outside coroutine context."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-CORO-0002",
            pass: "CORO",
            defaultSeverity: .error,
            summary: "Invalid coroutine state transition."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-CORO-0003",
            pass: "CORO",
            defaultSeverity: .error,
            summary: "Coroutine lowering failure."
        ),
    ]

    // MARK: - Backend pass (BACKEND)

    static let backendDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-BACKEND-0001",
            pass: "BACKEND",
            defaultSeverity: .error,
            summary: "C code generation failure."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-BACKEND-0002",
            pass: "BACKEND",
            defaultSeverity: .error,
            summary: "C compilation (clang) failure."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-BACKEND-1002",
            pass: "BACKEND",
            defaultSeverity: .warning,
            summary: "LLVM C API backend: non-fatal codegen warning."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-BACKEND-1003",
            pass: "BACKEND",
            defaultSeverity: .error,
            summary: "LLVM C API backend: function codegen failure."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-BACKEND-1004",
            pass: "BACKEND",
            defaultSeverity: .error,
            summary: "LLVM C API backend: module verification failure."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-BACKEND-1006",
            pass: "BACKEND",
            defaultSeverity: .error,
            summary: "LLVM C API backend: library load failure."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-BACKEND-1007",
            pass: "BACKEND",
            defaultSeverity: .error,
            summary: "LLVM C API backend: symbol resolution failure."
        ),
    ]

    // MARK: - Link pass (LINK)

    static let linkDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-LINK-0001",
            pass: "LINK",
            defaultSeverity: .error,
            summary: "Linker invocation failed."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-LINK-0002",
            pass: "LINK",
            defaultSeverity: .error,
            summary: "Link input not available."
        ),
    ]

    // MARK: - Pipeline / driver pass (PIPELINE)

    static let pipelineDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-PIPELINE-0001",
            pass: "PIPELINE",
            defaultSeverity: .error,
            summary: "Compiler pipeline failed while loading input sources."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PIPELINE-0002",
            pass: "PIPELINE",
            defaultSeverity: .error,
            summary: "Compiler pipeline received invalid intermediate state."
        ),
        DiagnosticDescriptor(
            code: "KSWIFTK-PIPELINE-0003",
            pass: "PIPELINE",
            defaultSeverity: .error,
            summary: "Compiler pipeline could not produce requested output."
        ),
    ]

    // MARK: - Internal compiler error (ICE)

    static let iceDescriptors: [DiagnosticDescriptor] = [
        DiagnosticDescriptor(
            code: "KSWIFTK-ICE-0001",
            pass: "ICE",
            defaultSeverity: .error,
            summary: "Internal compiler error."
        ),
    ]

    // MARK: - Aggregate

    static let allDescriptors: [DiagnosticDescriptor] =
        lexDescriptors
            + parseDescriptors
            + semaDescriptors
            + typeDescriptors
            + libDescriptors
            + kirDescriptors
            + coroDescriptors
            + backendDescriptors
            + linkDescriptors
            + pipelineDescriptors
            + iceDescriptors
}

// swiftlint:enable file_length type_body_length trailing_comma
