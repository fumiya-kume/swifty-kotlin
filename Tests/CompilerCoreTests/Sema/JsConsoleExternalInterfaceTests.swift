@testable import CompilerCore
import XCTest

final class JsConsoleExternalInterfaceTests: XCTestCase {
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
                "Expected Console external interface surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testConsoleInterfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "Console"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.Console must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .interface)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
    }

    func testDirSignatureIsRegistered() throws {
        let (sema, interner) = try makeSema()

        try assertMember(
            named: "dir",
            parameterType: sema.types.anyType,
            isVararg: false,
            sema: sema,
            interner: interner
        )
    }

    func testVarargLoggingSignaturesAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let nullableAny = sema.types.makeNullable(sema.types.anyType)

        for name in ["error", "info", "log", "warn"] {
            try assertMember(
                named: name,
                parameterType: nullableAny,
                isVararg: true,
                sema: sema,
                interner: interner
            )
        }
    }

    private func assertMember(
        named name: String,
        parameterType: TypeID,
        isVararg: Bool,
        sema: SemaModule,
        interner: StringInterner
    ) throws {
        let consoleFQName = ["kotlin", "js", "Console"].map { interner.intern($0) }
        let consoleSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: consoleFQName))
        let consoleType = try XCTUnwrap(sema.symbols.propertyType(for: consoleSymbol))
        let memberFQName = consoleFQName + [interner.intern(name)]
        let member = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: memberFQName).first { symbol in
                guard sema.symbols.symbol(symbol)?.kind == .function,
                      let signature = sema.symbols.functionSignature(for: symbol) else {
                    return false
                }
                return signature.parameterTypes == [parameterType]
            },
            "Console.\(name) member must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(member))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: member))

        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(signature.receiverType, consoleType)
        XCTAssertEqual(signature.parameterTypes, [parameterType])
        XCTAssertEqual(signature.returnType, sema.types.unitType)
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
        XCTAssertEqual(signature.valueParameterIsVararg, [isVararg])
        XCTAssertNil(sema.symbols.externalLinkName(for: member))
    }
}
