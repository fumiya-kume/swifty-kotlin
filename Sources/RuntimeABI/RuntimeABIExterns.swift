/// Canonical C ABI extern declarations derived from `RuntimeABISpec`.
///
/// `RuntimeABISpec` is the single source of truth. This type keeps the
/// compiler/test-facing extern view stable without duplicating hundreds of
/// handwritten declarations.
public enum RuntimeABIExterns {
    public static let specVersion = RuntimeABISpec.specVersion

    /// A single extern function declaration for the C preamble.
    public struct ExternDecl: Equatable, Sendable {
        public let name: String
        public let parameterTypes: [String]
        public let returnType: String

        public init(name: String, parameterTypes: [String], returnType: String) {
            self.name = name
            self.parameterTypes = parameterTypes
            self.returnType = returnType
        }

        public init(spec: RuntimeABIFunctionSpec) {
            self.init(
                name: spec.name,
                parameterTypes: spec.parameterTypeStrings,
                returnType: spec.returnTypeString
            )
        }

        /// Generates the C extern declaration string.
        public var cExternDeclaration: String {
            let params: String = if parameterTypes.isEmpty {
                "void"
            } else {
                parameterTypes.joined(separator: ", ")
            }
            return "extern \(returnType) \(name)(\(params));"
        }
    }

    /// All runtime extern declarations, ordered by section.
    public static let allExterns = RuntimeABISpec.allFunctions.map(ExternDecl.init(spec:))

    private static let externsByName: [String: ExternDecl] = Dictionary(
        uniqueKeysWithValues: allExterns.map { ($0.name, $0) }
    )

    /// Look up an extern declaration by symbol name.
    public static func externDecl(named name: String) -> ExternDecl? {
        externsByName[name]
    }
}
