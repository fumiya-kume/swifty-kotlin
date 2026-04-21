@testable import CompilerCore
import XCTest

/// TYPE-103: Verify that `arrayOf()` preserves element types and that
/// array-specific members are not incorrectly resolved on `Any` receivers.
final class ArrayOfTypeSafetyTests: XCTestCase {

    // MARK: - Positive: arrayOf(1, 2).get(0) should resolve without error

    func testArrayOfIntGetResolvesWithoutError() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            val x = arr.get(0)
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    func testArrayOfStringSizeResolvesWithoutError() throws {
        let source = """
        fun main() {
            val arr = arrayOf("a", "b", "c")
            val s = arr.size
            println(s)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
        }
    }

    func testArrayOfContainsResolvesWithoutError() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            val b = arr.contains(2)
            println(b)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
        }
    }

    func testArrayBinarySearchWithComparatorResolvesWithoutError() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3, 4)
            val idx = arr.binarySearch(3, compareBy<Int> { it })
            println(idx)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    func testProjectedArrayBinarySearchWithComparatorResolvesWithoutError() throws {
        let source = """
        fun main(values: Array<out Int>) {
            val idx = values.binarySearch(3, compareBy<Int> { it })
            println(idx)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    // MARK: - Negative: array members on Any should fail

    func testArrayGetOnAnyReceiverProducesError() throws {
        let source = """
        fun test(x: Any) {
            x.get(0)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            // `get` is not a member of Any; should produce unresolved member error.
            assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
        }
    }

    func testArraySizeOnAnyReceiverProducesError() throws {
        let source = """
        fun test(x: Any) {
            x.size
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            // `size` is not a member of Any; should produce unresolved member/field error.
            let hasDiag = ctx.diagnostics.diagnostics.contains {
                $0.code == "KSWIFTK-SEMA-0024" || $0.code == "KSWIFTK-SEMA-FIELD"
            }
            XCTAssertTrue(hasDiag, "Expected unresolved member diagnostic for .size on Any, got: \(ctx.diagnostics.diagnostics.map(\.code))")
        }
    }

    func testIntArrayBinarySearchProducesError() throws {
        let source = """
        fun main() {
            val arr = intArrayOf(1, 2, 3)
            val idx = arr.binarySearch(2, compareBy<Int> { it })
            println(idx)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
        }
    }

    // MARK: - Element type preservation

    func testArrayOfIntGetReturnsIntNotAny() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            val x = arr.get(0)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)

            // Walk the main body and find `val x = arr.get(0)`, then check
            // the initializer type is Int (not Any).
            let mainBody = try XCTUnwrap(findMainBodyStatements(in: ast, interner: ctx.interner))
            var foundGetResult = false
            for exprID in mainBody {
                guard let expr = ast.arena.expr(exprID),
                      case let .localDecl(_, _, _, initializer, _, _) = expr,
                      let initializer,
                      let boundType = sema.bindings.exprType(for: initializer)
                else { continue }
                // The get(0) call on Array<Int> should return Int, not Any.
                if boundType == sema.types.intType {
                    foundGetResult = true
                }
            }
            XCTAssertTrue(foundGetResult, "Expected arr.get(0) to be typed as Int, not Any.")
        }
    }

    // MARK: - Helpers

    private func findMainBodyStatements(
        in ast: ASTModule,
        interner: StringInterner
    ) -> [ExprID]? {
        for file in ast.files {
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(function) = decl,
                      interner.resolve(function.name) == "main",
                      case let .block(statements, _) = function.body
                else { continue }
                return statements
            }
        }
        return nil
    }

    // MARK: - Primitive array factories

    func testIntArrayOfGetReturnsInt() throws {
        let source = """
        fun main() {
            val arr = intArrayOf(10, 20, 30)
            val x = arr.get(0)
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    func testUShortArrayConstructorAndGetReturnUShort() throws {
        let source = """
        fun main() {
            val arr = UShortArray(3) { it.toUShort() }
            val x = arr.get(0)
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)
            let mainBody = try XCTUnwrap(findMainBodyStatements(in: ast, interner: ctx.interner))

            var foundUShortArray = false
            var foundUShortGet = false
            for exprID in mainBody {
                guard let expr = ast.arena.expr(exprID),
                      case let .localDecl(name, _, _, initializer, _, _) = expr,
                      let initializer,
                      let boundType = sema.bindings.exprType(for: initializer)
                else { continue }

                if ctx.interner.resolve(name) == "arr",
                   case let .classType(classType) = sema.types.kind(of: boundType),
                   let symbol = sema.symbols.symbol(classType.classSymbol)
                {
                    foundUShortArray = ctx.interner.resolve(symbol.name) == "UShortArray"
                }

                if ctx.interner.resolve(name) == "x" {
                    foundUShortGet = boundType == sema.types.ushortType
                }
            }

            XCTAssertTrue(foundUShortArray, "Expected arr to be typed as UShortArray.")
            XCTAssertTrue(foundUShortGet, "Expected arr.get(0) to be typed as UShort.")
        }
    }

    func testUByteArrayConstructorInfersUByteElements() throws {
        let source = """
        fun main() {
            val arr = UByteArray(3) { it.toUByte() }
            val x = arr.get(0)
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)
            let mainBody = try XCTUnwrap(findMainBodyStatements(in: ast, interner: ctx.interner))

            var foundUByteArray = false
            var foundUByteGet = false
            for exprID in mainBody {
                guard let expr = ast.arena.expr(exprID),
                      case let .localDecl(name, _, _, initializer, _, _) = expr,
                      let initializer,
                      let boundType = sema.bindings.exprType(for: initializer)
                else { continue }

                if ctx.interner.resolve(name) == "arr",
                   case let .classType(classType) = sema.types.kind(of: boundType),
                   let symbol = sema.symbols.symbol(classType.classSymbol)
                {
                    foundUByteArray = ctx.interner.resolve(symbol.name) == "UByteArray"
                }

                if ctx.interner.resolve(name) == "x" {
                    foundUByteGet = boundType == sema.types.ubyteType
                }
            }

            XCTAssertTrue(foundUByteArray, "Expected arr to be typed as UByteArray.")
            XCTAssertTrue(foundUByteGet, "Expected arr.get(0) to be typed as UByte.")
        }
    }

    func testUShortArrayFactoryReturnsUShortArray() throws {
        let source = """
        fun main() {
            val arr = ushortArrayOf(1.toUShort(), 2.toUShort(), 65535.toUShort())
            val x = arr[2]
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)
            let mainBody = try XCTUnwrap(findMainBodyStatements(in: ast, interner: ctx.interner))

            var foundUShortArray = false
            var foundIndexedUShort = false
            for exprID in mainBody {
                guard let expr = ast.arena.expr(exprID),
                      case let .localDecl(name, _, _, initializer, _, _) = expr,
                      let initializer,
                      let boundType = sema.bindings.exprType(for: initializer)
                else { continue }

                if ctx.interner.resolve(name) == "arr",
                   case let .classType(classType) = sema.types.kind(of: boundType),
                   let symbol = sema.symbols.symbol(classType.classSymbol)
                {
                    foundUShortArray = ctx.interner.resolve(symbol.name) == "UShortArray"
                }

                if ctx.interner.resolve(name) == "x" {
                    foundIndexedUShort = boundType == sema.types.ushortType
                }
            }

            XCTAssertTrue(foundUShortArray, "Expected ushortArrayOf(...) to produce UShortArray.")
            XCTAssertTrue(foundIndexedUShort, "Expected indexed access to produce UShort.")
        }
    }

    func testUByteArrayOfFactoryResolvesWithoutError() throws {
        let source = """
        fun main() {
            val arr = ubyteArrayOf(1.toUByte(), 2.toUByte(), 255.toUByte())
            val x = arr.get(1)
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)
            let mainBody = try XCTUnwrap(findMainBodyStatements(in: ast, interner: ctx.interner))

            var foundUByteArray = false
            var foundIndexedUByte = false
            for exprID in mainBody {
                guard let expr = ast.arena.expr(exprID),
                      case let .localDecl(name, _, _, initializer, _, _) = expr,
                      let initializer,
                      let boundType = sema.bindings.exprType(for: initializer)
                else { continue }

                if ctx.interner.resolve(name) == "arr",
                   case let .classType(classType) = sema.types.kind(of: boundType),
                   let symbol = sema.symbols.symbol(classType.classSymbol)
                {
                    foundUByteArray = ctx.interner.resolve(symbol.name) == "UByteArray"
                }

                if ctx.interner.resolve(name) == "x" {
                    foundIndexedUByte = boundType == sema.types.ubyteType
                }
            }

            XCTAssertTrue(foundUByteArray, "Expected ubyteArrayOf(...) to produce UByteArray.")
            XCTAssertTrue(foundIndexedUByte, "Expected indexed access to produce UByte.")
        }
    }
}
