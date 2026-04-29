@testable import CompilerCore
import Foundation
import XCTest

extension BuildKIRRegressionTests {
    func testUuidSizeConstantsLowerToImmediateConstants() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid

        fun main(): Int {
            val bits = Uuid.SIZE_BITS
            val bytes = Uuid.SIZE_BYTES
            return bits + bytes
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let intConstants = body.compactMap { instruction -> Int64? in
                guard case let .constValue(_, value) = instruction,
                      case let .intLiteral(intValue) = value
                else {
                    return nil
                }
                return intValue
            }
            let loadGlobalNames = body.compactMap { instruction -> String? in
                guard case let .loadGlobal(_, symbol) = instruction,
                      let symbolInfo = ctx.sema?.symbols.symbol(symbol)
                else {
                    return nil
                }
                return symbolInfo.fqName.map { ctx.interner.resolve($0) }.joined(separator: ".")
            }

            XCTAssertTrue(
                intConstants.contains(128),
                "Expected Uuid.SIZE_BITS to lower as int literal 128; load globals: \(loadGlobalNames)"
            )
            XCTAssertTrue(
                intConstants.contains(16),
                "Expected Uuid.SIZE_BYTES to lower as int literal 16; load globals: \(loadGlobalNames)"
            )
        }
    }
}
