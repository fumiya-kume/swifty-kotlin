@testable import CompilerCore
import Foundation
import XCTest

/// Tests for REFL-002: standalone `T::class` references produce proper KClass
/// metadata via `kk_kclass_create` instead of falling back to Unit.
final class StandaloneClassReferenceTests: XCTestCase {

    /// Standalone `T::class` inside a reified inline function should emit
    /// `kk_kclass_create` in the lowered KIR output after inline expansion.
    func testStandaloneReifiedClassRefEmitsKClassCreate() throws {
        let source = """
        inline fun <reified T> classOf(): Any = T::class
        fun main() {
            val kc = classOf<Int>()
            println(kc)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            // Run through lowering so inline expansion processes T::class.
            try runToLowering(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("kk_kclass_create"),
                "Expected kk_kclass_create for standalone T::class after inline expansion, got: \(callees)"
            )
        }
    }

    /// Standalone `String::class` (concrete/builtin type) should emit
    /// `kk_kclass_create` in the KIR output.
    func testStandaloneConcreteClassRefEmitsKClassCreate() throws {
        let source = """
        fun main() {
            val kc = String::class
            println(kc)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("kk_kclass_create"),
                "Expected kk_kclass_create for standalone String::class, got: \(callees)"
            )
        }
    }

    /// Standalone `Int::class` (primitive builtin type) should emit
    /// `kk_kclass_create` in the KIR output.
    func testStandalonePrimitiveClassRefEmitsKClassCreate() throws {
        let source = """
        fun main() {
            val kc = Int::class
            println(kc)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("kk_kclass_create"),
                "Expected kk_kclass_create for standalone Int::class, got: \(callees)"
            )
        }
    }

    /// `T::class.simpleName` (chained) should still use the direct
    /// `kk_type_token_simple_name` path after inline expansion.
    func testChainedClassRefSimpleNameUsesDirectPath() throws {
        let source = """
        inline fun <reified T> typeNameOf(): String = T::class.simpleName ?: "unknown"
        fun main() = println(typeNameOf<Int>())
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("kk_type_token_simple_name"),
                "Chained T::class.simpleName should use kk_type_token_simple_name, got: \(callees)"
            )
            XCTAssertFalse(
                callees.contains("kk_kclass_create"),
                "Chained T::class.simpleName should NOT emit kk_kclass_create, got: \(callees)"
            )
        }
    }

    /// User-defined class `MyClass::class` should emit `kk_kclass_create`.
    func testStandaloneUserClassRefEmitsKClassCreate() throws {
        let source = """
        class MyClass
        fun main() {
            val kc = MyClass::class
            println(kc)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("kk_kclass_create"),
                "Expected kk_kclass_create for standalone MyClass::class, got: \(callees)"
            )
        }
    }

    // MARK: - REFL-002 Additional tests

    /// `this::class` inside a class method should emit `kk_kclass_create`.
    func testThisClassRefEmitsKClassCreate() throws {
        let source = """
        class Foo {
            fun getKClass(): Any = this::class
        }
        fun main() {
            val f = Foo()
            println(f.getKClass())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            // Check that classRefTargetType was bound for the this::class expr
            // by looking for kk_kclass_create in the Foo.getKClass body.
            let body = try findKIRFunctionBody(named: "getKClass", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("kk_kclass_create"),
                "Expected kk_kclass_create for this::class, got: \(callees)"
            )
        }
    }

    /// `Long::class` should emit `kk_kclass_create` with a non-zero type token.
    func testStandaloneLongClassRefEmitsKClassCreate() throws {
        let source = """
        fun main() {
            val kc = Long::class
            println(kc)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("kk_kclass_create"),
                "Expected kk_kclass_create for standalone Long::class, got: \(callees)"
            )
        }
    }

    /// `Double::class` should emit `kk_kclass_create`.
    func testStandaloneDoubleClassRefEmitsKClassCreate() throws {
        let source = """
        fun main() {
            val kc = Double::class
            println(kc)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("kk_kclass_create"),
                "Expected kk_kclass_create for standalone Double::class, got: \(callees)"
            )
        }
    }

    /// `Boolean::class` should emit `kk_kclass_create`.
    func testStandaloneBooleanClassRefEmitsKClassCreate() throws {
        let source = """
        fun main() {
            val kc = Boolean::class
            println(kc)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("kk_kclass_create"),
                "Expected kk_kclass_create for standalone Boolean::class, got: \(callees)"
            )
        }
    }

    /// RuntimeTypeCheckToken should encode Long as a distinct (non-zero) base.
    func testRuntimeTypeCheckTokenEncodesLong() {
        let (sema, _, types, interner) = makeSemaModule()
        let longType = types.make(.primitive(.long, .nonNull))
        let encoded = RuntimeTypeCheckToken.encode(type: longType, sema: sema, interner: interner)
        // longBase = 11
        XCTAssertEqual(encoded & 0xFF, 11, "Long should encode with base 11, got \(encoded & 0xFF)")
        XCTAssertNotEqual(encoded, 0, "Long token must not be unknownBase (0)")
    }

    /// RuntimeTypeCheckToken should encode Double as a distinct base.
    func testRuntimeTypeCheckTokenEncodesDouble() {
        let (sema, _, types, interner) = makeSemaModule()
        let doubleType = types.make(.primitive(.double, .nonNull))
        let encoded = RuntimeTypeCheckToken.encode(type: doubleType, sema: sema, interner: interner)
        // doubleBase = 12
        XCTAssertEqual(encoded & 0xFF, 12, "Double should encode with base 12, got \(encoded & 0xFF)")
    }

    /// RuntimeTypeCheckToken should encode Float as a distinct base.
    func testRuntimeTypeCheckTokenEncodesFloat() {
        let (sema, _, types, interner) = makeSemaModule()
        let floatType = types.make(.primitive(.float, .nonNull))
        let encoded = RuntimeTypeCheckToken.encode(type: floatType, sema: sema, interner: interner)
        // floatBase = 13
        XCTAssertEqual(encoded & 0xFF, 13, "Float should encode with base 13, got \(encoded & 0xFF)")
    }

    /// RuntimeTypeCheckToken should encode Char as a distinct base.
    func testRuntimeTypeCheckTokenEncodesChar() {
        let (sema, _, types, interner) = makeSemaModule()
        let charType = types.make(.primitive(.char, .nonNull))
        let encoded = RuntimeTypeCheckToken.encode(type: charType, sema: sema, interner: interner)
        // charBase = 14
        XCTAssertEqual(encoded & 0xFF, 14, "Char should encode with base 14, got \(encoded & 0xFF)")
    }

    /// KIR result type for a standalone `Int::class` should carry a KClass type
    /// rather than falling back to Any.
    func testKIRResultTypeIsKClassNotAny() throws {
        let source = """
        fun main() {
            val kc = Int::class
            println(kc)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            // Find the kk_kclass_create call and check its result type.
            for instruction in body {
                guard case let .call(_, callee, _, result, _, _, _) = instruction else { continue }
                if ctx.interner.resolve(callee) == "kk_kclass_create" {
                    guard let resultID = result,
                          let resultType = module.arena.exprType(resultID) else {
                        XCTFail("kk_kclass_create result has no stored type")
                        return
                    }
                    // The result type should be KClass<Int>, not Any.
                    if case .kClassType = ctx.sema!.types.kind(of: resultType) {
                        // Success — type is KClass<T>.
                        return
                    }
                    XCTFail("Expected KClass type for kk_kclass_create result, got type kind: \(ctx.sema!.types.kind(of: resultType))")
                    return
                }
            }
            XCTFail("kk_kclass_create call not found in main body")
        }
    }
}
