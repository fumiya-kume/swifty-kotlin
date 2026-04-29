@testable import CompilerCore
import Foundation
import XCTest

final class NativeStackTraceAddressesSurfaceTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Tests assert on collected diagnostics.
        }
        return ctx
    }

    func testGetStackTraceAddressesIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let nativeFQName = ["kotlin", "native", "getStackTraceAddresses"].map { interner.intern($0) }
        let listFQName = ["kotlin", "collections", "List"].map { interner.intern($0) }
        let listSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: listFQName))
        let listLongType = sema.types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(sema.types.longType)],
            nullability: .nonNull
        )))
        let candidates = sema.symbols.lookupAll(fqName: nativeFQName)
        let match = candidates.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes.isEmpty
                && signature.returnType == listLongType
        }
        let symbol = try XCTUnwrap(match, "Expected kotlin.native.getStackTraceAddresses")

        XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), "kk_native_getStackTraceAddresses")
        XCTAssertTrue(
            sema.symbols.annotations(for: symbol).contains {
                $0.annotationFQName == "kotlin.experimental.ExperimentalNativeApi"
            },
            "getStackTraceAddresses must carry ExperimentalNativeApi metadata"
        )
    }

    func testGetStackTraceAddressesResolvesInSourceWithOptIn() {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        import kotlin.native.getStackTraceAddresses

        fun probe(): List<Long> = getStackTraceAddresses()
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        XCTAssertTrue(errors.isEmpty, "Expected getStackTraceAddresses to resolve without errors, got \(errors)")
    }
}
