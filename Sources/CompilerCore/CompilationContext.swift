public final class CompilationContext {
    public let options: CompilerOptions
    public let sourceManager: SourceManager
    public let diagnostics: DiagnosticEngine
    public let interner: StringInterner

    public var tokens: [Token] = []
    public var cst: SyntaxArena? = nil
    public var cstRoot: NodeID = NodeID()
    public var ast: ASTModule? = nil
    public var sema: SemaModule? = nil
    public var kir: KIRModule? = nil
    public var generatedObjectPath: String? = nil
    public var generatedLLVMIRPath: String? = nil

    public init(
        options: CompilerOptions,
        sourceManager: SourceManager,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        self.options = options
        self.sourceManager = sourceManager
        self.diagnostics = diagnostics
        self.interner = interner
    }
}
