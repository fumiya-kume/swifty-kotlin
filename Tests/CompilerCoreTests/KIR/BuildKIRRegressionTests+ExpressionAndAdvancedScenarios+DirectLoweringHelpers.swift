@testable import CompilerCore
import Foundation
import XCTest

struct KIRDirectLoweringFixture {
    let interner: StringInterner
    let diagnostics: DiagnosticEngine
    let symbols: SymbolTable
    let types: TypeSystem
    let bindings: BindingTable
    let sema: SemaModule
    let astArena: ASTArena
    let ast: ASTModule
    let kirArena: KIRArena
    let driver: KIRLoweringDriver

    func makeShared(
        propertyConstantInitializers: [SymbolID: KIRExprKind] = [:]
    ) -> KIRLoweringSharedContext {
        KIRLoweringSharedContext(
            ast: ast,
            sema: sema,
            arena: kirArena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers
        )
    }
}

func makeKIRDirectLoweringFixture() -> KIRDirectLoweringFixture {
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
    let file = ASTFile(
        fileID: FileID(rawValue: 0),
        packageFQName: [interner.intern("pkg")],
        imports: [],
        topLevelDecls: [],
        scriptBody: []
    )
    let ast = ASTModule(
        files: [file],
        arena: astArena,
        declarationCount: 0,
        tokenCount: 0
    )
    let kirArena = KIRArena()
    let loweringContext = KIRLoweringContext()
    loweringContext.initializeSyntheticLambdaSymbolAllocator(sema: sema)
    let driver = KIRLoweringDriver(ctx: loweringContext)
    return KIRDirectLoweringFixture(
        interner: interner,
        diagnostics: diagnostics,
        symbols: symbols,
        types: types,
        bindings: bindings,
        sema: sema,
        astArena: astArena,
        ast: ast,
        kirArena: kirArena,
        driver: driver
    )
}

func defineSemanticSymbol(
    in fixture: KIRDirectLoweringFixture,
    kind: SymbolKind,
    fqName: [String],
    flags: SymbolFlags = []
) -> SymbolID {
    precondition(!fqName.isEmpty)
    let interned = fqName.map { fixture.interner.intern($0) }
    return fixture.symbols.define(
        kind: kind,
        name: interned.last!,
        fqName: interned,
        declSite: nil,
        visibility: .public,
        flags: flags
    )
}

func appendTypedExpr(
    _ expr: Expr,
    type: TypeID?,
    fixture: KIRDirectLoweringFixture
) -> ExprID {
    let exprID = fixture.astArena.appendExpr(expr)
    if let type {
        fixture.bindings.bindExprType(exprID, type: type)
    }
    return exprID
}

func appendSafeMemberExpr(
    receiver: ExprID,
    callee: InternedString,
    args: [CallArgument],
    type: TypeID,
    fixture: KIRDirectLoweringFixture
) -> ExprID {
    let exprID = fixture.astArena.appendExpr(
        .safeMemberCall(
            receiver: receiver,
            callee: callee,
            typeArgs: [],
            args: args,
            range: makeRange()
        )
    )
    fixture.bindings.bindExprType(exprID, type: type)
    return exprID
}

func appendSafeMemberExprWithoutType(
    receiver: ExprID,
    callee: InternedString,
    args: [CallArgument],
    fixture: KIRDirectLoweringFixture
) -> ExprID {
    fixture.astArena.appendExpr(
        .safeMemberCall(
            receiver: receiver,
            callee: callee,
            typeArgs: [],
            args: args,
            range: makeRange()
        )
    )
}
