@testable import CompilerCore
import XCTest

final class TypeCheckHelpersCoverageTests: XCTestCase {}

struct HelpersFixture {
    let interner: StringInterner
    let diagnostics: DiagnosticEngine
    let symbols: SymbolTable
    let types: TypeSystem
    let bindings: BindingTable
    let sema: SemaModule
    let astArena: ASTArena
    let ast: ASTModule
}

func makeHelpersFixture() -> HelpersFixture {
    let interner = StringInterner()
    let diagnostics = DiagnosticEngine()
    let symbols = SymbolTable()
    let types = TypeSystem()
    let bindings = BindingTable()
    let sema = SemaModule(
        symbols: symbols,
        types: types,
        bindings: bindings,
        diagnostics: diagnostics
    )

    let astArena = ASTArena()
    let ast = ASTModule(
        files: [
            ASTFile(
                fileID: FileID(rawValue: 0),
                packageFQName: [interner.intern("pkg")],
                imports: [],
                topLevelDecls: [],
                scriptBody: []
            ),
        ],
        arena: astArena,
        declarationCount: 0,
        tokenCount: 0
    )

    return HelpersFixture(
        interner: interner,
        diagnostics: diagnostics,
        symbols: symbols,
        types: types,
        bindings: bindings,
        sema: sema,
        astArena: astArena,
        ast: ast
    )
}
