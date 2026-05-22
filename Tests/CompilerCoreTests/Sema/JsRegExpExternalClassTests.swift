@testable import CompilerCore
import XCTest

final class JsRegExpExternalClassTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected RegExp external class surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testRegExpClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "RegExp"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.RegExp must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .class)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
    }

    func testRegExpConstructorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let ctorFQName = ["kotlin", "js", "RegExp", "<init>"].map { interner.intern($0) }
        let constructor = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: ctorFQName).first { symbol in
                sema.symbols.functionSignature(for: symbol)?.parameterTypes.count == 2
            },
            "RegExp(pattern, flags) constructor must be registered"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: constructor))

        XCTAssertEqual(signature.parameterTypes, [
            sema.types.stringType,
            sema.types.makeNullable(sema.types.stringType),
        ])
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [false, true])
    }

    func testRegExpResetMemberIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let regExpFQName = ["kotlin", "js", "RegExp"].map { interner.intern($0) }
        let regExpSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: regExpFQName))
        let regExpType = try XCTUnwrap(sema.symbols.propertyType(for: regExpSymbol))
        let reset = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: regExpFQName + [interner.intern("reset")]).first { symbol in
                guard let signature = sema.symbols.functionSignature(for: symbol) else {
                    return false
                }
                return signature.receiverType == regExpType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == sema.types.unitType
            },
            "RegExp.reset() member must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(reset))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: reset))

        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [])
        XCTAssertEqual(signature.valueParameterIsVararg, [])
        XCTAssertNil(sema.symbols.externalLinkName(for: reset))
    }

    func testRegExpResetCanBeCalled() throws {
        _ = try makeSema(source: """
        import kotlin.js.RegExp

        fun resetRegex() {
            RegExp("a").reset()
        }
        """)
    }
}
