@testable import CompilerCore
import XCTest

final class JvmOverloadsLoweringTests: XCTestCase {
    func testJvmOverloadsSynthesizesTrailingDefaultArgumentWrappers() throws {
        let source = """
        class Greeter {
            @JvmOverloads
            fun greet(prefix: String = "Hello", suffix: String = "!"): String {
                return prefix + suffix
            }
        }
        """

        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let module = try XCTUnwrap(ctx.kir)
        let interner = ctx.interner

        let greetSymbols = sema.symbols.allSymbols().filter { symbol in
            symbol.kind == .function && interner.resolve(symbol.name) == "greet"
        }

        XCTAssertEqual(greetSymbols.count, 3)

        let syntheticWrappers = greetSymbols.filter { $0.flags.contains(.synthetic) }
        XCTAssertEqual(syntheticWrappers.count, 2)

        let signatures = syntheticWrappers.compactMap { sema.symbols.functionSignature(for: $0.id) }
        XCTAssertEqual(signatures.map(\.parameterTypes.count).sorted(), [0, 1])
        XCTAssertTrue(signatures.allSatisfy { $0.valueParameterHasDefaultValues.allSatisfy { $0 == false } })

        let wrapperFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case let .function(function) = decl,
                  syntheticWrappers.contains(where: { $0.id == function.symbol })
            else {
                return nil
            }
            return function
        }
        XCTAssertEqual(wrapperFunctions.count, 2)
        XCTAssertTrue(wrapperFunctions.allSatisfy { function in
            function.body.contains { instruction in
                guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else {
                    return false
                }
                return symbol == greetSymbols.first(where: { !$0.flags.contains(.synthetic) })?.id
            }
        })
    }
}
