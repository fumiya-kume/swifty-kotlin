@testable import CompilerCore
import Foundation
import XCTest

extension LoweringPassRegressionTests {
    func testInlineLoweringMapsReifiedTypeTokenSymbolRefToHiddenArgument() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let diagnostics = DiagnosticEngine()

        let packageName = interner.intern("demo")
        let mainName = interner.intern("main")
        let inlineName = interner.intern("inlineToken")
        let typeParameterName = interner.intern("T")
        let intType = types.make(.primitive(.int, .nonNull))

        let mainSymbol = symbols.define(
            kind: .function,
            name: mainName,
            fqName: [packageName, mainName],
            declSite: nil,
            visibility: .public
        )
        let inlineSymbol = symbols.define(
            kind: .function,
            name: inlineName,
            fqName: [packageName, inlineName],
            declSite: nil,
            visibility: .public,
            flags: [.inlineFunction]
        )
        let typeParameterSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParameterName,
            fqName: [packageName, interner.intern("$inlineToken"), typeParameterName],
            declSite: nil,
            visibility: .private,
            flags: [.reifiedTypeParameter]
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: intType,
                typeParameterSymbols: [typeParameterSymbol],
                reifiedTypeParameterIndices: Set([0])
            ),
            for: inlineSymbol
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: intType
            ),
            for: mainSymbol
        )

        // Type token symbols use a negative offset to avoid collision with real symbol IDs
        let hiddenTokenSymbol = SymbolID(rawValue: Int32(typeTokenSymbolOffset) - typeParameterSymbol.rawValue)
        let inlineTokenExpr = arena.appendExpr(.temporary(0), type: intType)
        let callerTokenExpr = arena.appendExpr(.intLiteral(321), type: intType)
        let callerResultExpr = arena.appendExpr(.temporary(1), type: intType)

        let inlineFunction = KIRFunction(
            symbol: inlineSymbol,
            name: inlineName,
            params: [KIRParameter(symbol: hiddenTokenSymbol, type: intType)],
            returnType: intType,
            body: [
                .constValue(result: inlineTokenExpr, value: .symbolRef(typeParameterSymbol)),
                .returnValue(inlineTokenExpr),
            ],
            isSuspend: false,
            isInline: true
        )
        let mainFunction = KIRFunction(
            symbol: mainSymbol,
            name: mainName,
            params: [],
            returnType: intType,
            body: [
                .constValue(result: callerTokenExpr, value: .intLiteral(321)),
                .call(
                    symbol: inlineSymbol,
                    callee: inlineName,
                    arguments: [callerTokenExpr],
                    result: callerResultExpr,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callerResultExpr),
            ],
            isSuspend: false,
            isInline: false
        )

        let mainDeclID = arena.appendDecl(.function(mainFunction))
        _ = arena.appendDecl(.function(inlineFunction))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainDeclID])],
            arena: arena
        )

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "InlineReifiedToken",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
        ctx.kir = module
        ctx.sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: bindings,
            diagnostics: diagnostics
        )

        try LoweringPhase().run(ctx)

        guard case let .function(loweredMain)? = module.arena.decl(mainDeclID) else {
            XCTFail("Expected lowered main function.")
            return
        }

        let loweredCallees = loweredMain.body.compactMap { instruction -> InternedString? in
            guard case let .call(_, callee, _, _, _, _, _) = instruction else {
                return nil
            }
            return callee
        }
        XCTAssertFalse(loweredCallees.contains(inlineName))

        let symbolRefConstants = loweredMain.body.compactMap { instruction -> SymbolID? in
            guard case let .constValue(_, value) = instruction,
                  case let .symbolRef(symbol) = value
            else {
                return nil
            }
            return symbol
        }
        XCTAssertFalse(symbolRefConstants.contains(typeParameterSymbol))

        let returnExpr = try XCTUnwrap(loweredMain.body.compactMap { instruction -> KIRExprID? in
            guard case let .returnValue(value) = instruction else {
                return nil
            }
            return value
        }.first)
        guard case let .intLiteral(returnedLiteral)? = module.arena.expr(returnExpr) else {
            XCTFail("Expected inline result to resolve to hidden token argument value.")
            return
        }
        XCTAssertEqual(returnedLiteral, 321)
    }

    // MARK: - Private Helpers

    struct LoweringRewriteFixture {
        let interner: StringInterner
        let module: KIRModule
        let mainID: KIRDeclID
        let emptyID: KIRDeclID
    }

    func makeLoweringRewriteFixture() throws -> LoweringRewriteFixture {
        let interner = StringInterner()
        let arena = KIRArena()

        let mainSym = SymbolID(rawValue: 10)
        let inlineSym = SymbolID(rawValue: 11)
        let suspendSym = SymbolID(rawValue: 12)
        let emptySym = SymbolID(rawValue: 13)

        let v0 = arena.appendExpr(.temporary(0))
        let v1 = arena.appendExpr(.temporary(1))
        let v2 = arena.appendExpr(.temporary(2))
        let v3 = arena.appendExpr(.temporary(3))
        let vFalse = arena.appendExpr(.boolLiteral(false))

        let mainFn = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(symbol: nil, callee: interner.intern("kk_range_iterator"), arguments: [v0], result: v3, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_for_lowered"), arguments: [v3], result: v1, canThrow: false, thrownResult: nil),
                .constValue(result: vFalse, value: .boolLiteral(false)),
                .jumpIfEqual(lhs: v0, rhs: vFalse, target: 800),
                .jump(801),
                .label(800),
                .copy(from: v2, to: v1),
                .label(801),
                .call(symbol: nil, callee: interner.intern("get"), arguments: [v0], result: v1, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("set"), arguments: [v0], result: v1, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("<lambda>"), arguments: [v0], result: v1, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("inlineTarget"), arguments: [], result: v1, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("suspendTarget"), arguments: [v0], result: v1, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let inlineFn = KIRFunction(
            symbol: inlineSym,
            name: interner.intern("inlineTarget"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: true
        )
        let suspendFn = KIRFunction(
            symbol: suspendSym,
            name: interner.intern("suspendTarget"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(symbol: suspendSym, callee: interner.intern("suspendTarget"), arguments: [], result: v2, canThrow: false, thrownResult: nil),
                .returnValue(v2),
            ],
            isSuspend: true,
            isInline: false
        )
        let emptyFn = KIRFunction(
            symbol: emptySym,
            name: interner.intern("empty"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(inlineFn))
        _ = arena.appendDecl(.function(suspendFn))
        let emptyID = arena.appendDecl(.function(emptyFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID, emptyID])], arena: arena)

        let options = CompilerOptions(
            moduleName: "Lowering",
            inputs: [],
            outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let ctx = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        try LoweringPhase().run(ctx)

        return LoweringRewriteFixture(interner: interner, module: module, mainID: mainID, emptyID: emptyID)
    }
}
