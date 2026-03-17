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
}
