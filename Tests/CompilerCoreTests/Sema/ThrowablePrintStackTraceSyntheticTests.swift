@testable import CompilerCore
import XCTest

final class ThrowablePrintStackTraceSyntheticTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(ctx.diagnostics.hasError, "Expected Throwable surface to resolve cleanly, got: \(diagnostics)")
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testPrintStackTraceMemberFunctionIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let kotlinPackage = ["kotlin"].map { interner.intern($0) }
        let throwableSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: kotlinPackage + [interner.intern("Throwable")]
        ))
        let throwableType = sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nonNull
        )))

        let printStackTraceSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: kotlinPackage + [interner.intern("Throwable"), interner.intern("printStackTrace")]
        ))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: printStackTraceSymbol))

        XCTAssertEqual(sema.symbols.externalLinkName(for: printStackTraceSymbol), "kk_throwable_printStackTrace")
        XCTAssertEqual(signature.receiverType, throwableType)
        XCTAssertEqual(signature.parameterTypes, [])
        XCTAssertEqual(signature.returnType, sema.types.unitType)
    }

    func testPrintStackTraceResolvesAsUnitReturningMemberCall() throws {
        let source = """
        fun sample(e: Throwable) {
            val result: Unit = e.printStackTrace()
        }
        """

        let (sema, interner) = try makeSema(source: source)
        let sampleSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: [interner.intern("sample")]
        ))

        XCTAssertNotNil(sema.symbols.functionSignature(for: sampleSymbol))
    }
}
