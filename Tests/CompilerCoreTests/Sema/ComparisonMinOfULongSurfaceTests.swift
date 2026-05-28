@testable import CompilerCore
import XCTest

final class ComparisonMinOfULongSurfaceTests: XCTestCase {
    func testULongMinOfSurfaceRegistersUnsignedOverloads() throws {
        let source = "fun touch() {}"

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner
            let minOfSymbols = sema.symbols.lookupAll(fqName: [
                interner.intern("kotlin"),
                interner.intern("comparisons"),
                interner.intern("minOf"),
            ])

            let signatures = minOfSymbols.compactMap { sema.symbols.functionSignature(for: $0) }
            XCTAssertTrue(signatures.contains { signature in
                signature.parameterTypes == [sema.types.ulongType, sema.types.ulongType]
                    && signature.returnType == sema.types.ulongType
                    && !signature.valueParameterIsVararg.contains(true)
            })
            XCTAssertTrue(signatures.contains { signature in
                signature.parameterTypes == [sema.types.ulongType, sema.types.ulongType, sema.types.ulongType]
                    && signature.returnType == sema.types.ulongType
                    && !signature.valueParameterIsVararg.contains(true)
            })
            XCTAssertTrue(signatures.contains { signature in
                signature.parameterTypes == [sema.types.ulongType, sema.types.ulongType]
                    && signature.returnType == sema.types.ulongType
                    && signature.valueParameterIsVararg == [false, true]
            })
        }
    }
}
