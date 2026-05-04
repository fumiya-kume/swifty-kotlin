@testable import CompilerCore
import Foundation
import XCTest

final class ContextHelperSyntheticStubTests: XCTestCase {
    func testContextHelperIsRegisteredWithContextFunctionBlock() throws {
        let (sema, interner) = try makeSema()
        let contextSymbol = try XCTUnwrap(lookupSymbol(["kotlin", "context"], sema: sema, interner: interner))
        let symbol = try XCTUnwrap(sema.symbols.symbol(contextSymbol))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: contextSymbol))

        XCTAssertTrue(symbol.flags.contains(.synthetic))
        XCTAssertTrue(symbol.flags.contains(.inlineFunction))
        XCTAssertEqual(signature.parameterTypes.count, 2)
        XCTAssertEqual(signature.typeParameterSymbols.count, 2)
        XCTAssertEqual(signature.returnType, typeParamType(signature.typeParameterSymbols[1], sema: sema))

        let contextType = typeParamType(signature.typeParameterSymbols[0], sema: sema)
        XCTAssertEqual(signature.parameterTypes[0], contextType)
        guard case let .functionType(blockType) = sema.types.kind(of: signature.parameterTypes[1]) else {
            XCTFail("context block parameter should be a function type")
            return
        }
        XCTAssertEqual(blockType.contextReceivers, [contextType])
        XCTAssertTrue(blockType.params.isEmpty)
        XCTAssertEqual(blockType.returnType, signature.returnType)
    }

    func testContextHelperRegistersOverloadsThroughAritySix() throws {
        let (sema, interner) = try makeSema()
        let contextSymbols = sema.symbols.lookupAll(fqName: ["kotlin", "context"].map { interner.intern($0) })
        let arities = Set(contextSymbols.compactMap { symbolID -> Int? in
            guard let signature = sema.symbols.functionSignature(for: symbolID),
                  case let .functionType(blockType) = sema.types.kind(of: signature.parameterTypes.last ?? .invalid),
                  blockType.params.isEmpty
            else {
                return nil
            }
            return blockType.contextReceivers.count
        })

        XCTAssertEqual(arities, Set(1...6))
    }

    func testContextOfHelperIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let contextOfSymbol = try XCTUnwrap(lookupSymbol(["kotlin", "contextOf"], sema: sema, interner: interner))
        let symbol = try XCTUnwrap(sema.symbols.symbol(contextOfSymbol))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: contextOfSymbol))

        XCTAssertTrue(symbol.flags.contains(.synthetic))
        XCTAssertTrue(symbol.flags.contains(.inlineFunction))
        XCTAssertEqual(signature.parameterTypes, [])
        XCTAssertEqual(signature.typeParameterSymbols.count, 1)
        XCTAssertEqual(signature.returnType, typeParamType(signature.typeParameterSymbols[0], sema: sema))
        XCTAssertTrue(sema.symbols.annotations(for: contextOfSymbol).contains { annotation in
            annotation.annotationFQName == "kotlin.ExperimentalContextParameters"
        })
    }

    func testContextHelperRequiresExperimentalContextParametersOptIn() {
        let source = """
        fun caller(): Int = context(1) { 2 }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected context helper to require opt-in, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.first?.message.contains("ExperimentalContextParameters") == true)
    }

    func testContextHelperAcceptsOptInAndInfersBlockReturnType() throws {
        let source = """
        import kotlin.ExperimentalContextParameters

        @OptIn(ExperimentalContextParameters::class)
        fun caller(): String = context(1) { "ok" }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertTrue(
            diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx).isEmpty,
            "Expected @OptIn to suppress context helper diagnostic, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let callerSymbol = try XCTUnwrap(lookupSymbol(["caller"], sema: sema, interner: interner))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: callerSymbol))
        XCTAssertEqual(signature.returnType, sema.types.stringType)
    }

    func testContextOfResolvesInsideContextHelperBlock() throws {
        let source = """
        import kotlin.ExperimentalContextParameters

        @OptIn(ExperimentalContextParameters::class)
        fun caller(): String = context("ok") { contextOf<String>() }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertTrue(
            diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx).isEmpty,
            "Expected @OptIn to suppress contextOf diagnostic, got: \(ctx.diagnostics.diagnostics)"
        )
        XCTAssertTrue(
            diagnostics(withCode: "KSWIFTK-SEMA-CTX-001", in: ctx).isEmpty,
            "Expected contextOf<String>() to find the String context receiver, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let callerSymbol = try XCTUnwrap(lookupSymbol(["caller"], sema: sema, interner: interner))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: callerSymbol))
        XCTAssertEqual(signature.returnType, sema.types.stringType)
    }

    func testContextOfReportsMissingContextReceiver() {
        let source = """
        import kotlin.ExperimentalContextParameters

        @OptIn(ExperimentalContextParameters::class)
        fun caller(): Int = context("ok") { contextOf<Int>() }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-CTX-001", in: ctx)
        XCTAssertEqual(diagnostics.count, 1, "Expected missing context receiver diagnostic, got: \(ctx.diagnostics.diagnostics)")
    }

    func testContextHelperSixValueOverloadInfersBlockReturnType() throws {
        let source = """
        import kotlin.ExperimentalContextParameters

        @OptIn(ExperimentalContextParameters::class)
        fun caller(): String = context(1, 2, 3, 4, 5, 6) { "ok" }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertTrue(
            diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx).isEmpty,
            "Expected @OptIn to suppress context helper diagnostic, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let callerSymbol = try XCTUnwrap(lookupSymbol(["caller"], sema: sema, interner: interner))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: callerSymbol))
        XCTAssertEqual(signature.returnType, sema.types.stringType)
    }

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let fakePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [fakePath])
        _ = ctx.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
        do {
            try runSema(ctx)
        } catch {
            // Error diagnostics are asserted by each test.
        }
        return ctx
    }

    private func lookupSymbol(
        _ fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        sema.symbols.lookup(fqName: fqPath.map { interner.intern($0) })
    }

    private func diagnostics(withCode code: String, in ctx: CompilationContext) -> [Diagnostic] {
        ctx.diagnostics.diagnostics.filter { $0.code == code }
    }

    private func typeParamType(_ symbol: SymbolID, sema: SemaModule) -> TypeID {
        sema.types.make(.typeParam(TypeParamType(symbol: symbol, nullability: .nonNull)))
    }
}
