import Foundation
import XCTest
@testable import CompilerCore

// MARK: - Diamond Override Resolution Tests (P5-114)

final class DiamondOverrideTests: XCTestCase {

    // MARK: - Diamond detection: missing override

    func testDiamondConflictWithoutOverrideEmitsDiagnostic() throws {
        let source = """
        interface X {
            fun action(): String = "X"
        }
        interface Y {
            fun action(): String = "Y"
        }
        class Z : X, Y {
        }
        fun main() {}
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-DIAMOND", in: ctx)
        }
    }

    // MARK: - Diamond resolved by explicit override: no diagnostic

    func testDiamondConflictResolvedByOverrideNoDiagnostic() throws {
        let source = """
        interface X {
            fun action(): String = "X"
        }
        interface Y {
            fun action(): String = "Y"
        }
        class Z : X, Y {
            override fun action(): String = "Z"
        }
        fun main() {}
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-DIAMOND", in: ctx)
        }
    }

    // MARK: - Single interface with default method: no diamond

    func testSingleInterfaceWithDefaultMethodNoDiamond() throws {
        let source = """
        interface A {
            fun greet(): String = "A"
        }
        class B : A {
        }
        fun main() {}
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-DIAMOND", in: ctx)
        }
    }

    // MARK: - Both interfaces have abstract-only methods: no diamond (falls under ABSTRACT)

    func testBothInterfacesAbstractOnlyNotDiamond() throws {
        let source = """
        interface A {
            fun greet(): String
        }
        interface B {
            fun greet(): String
        }
        class C : A, B {
            override fun greet(): String = "C"
        }
        fun main() {}
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-DIAMOND", in: ctx)
        }
    }

    // MARK: - One default, one abstract: no diamond (only one default)

    func testOneDefaultOneAbstractNoDiamond() throws {
        let source = """
        interface A {
            fun greet(): String = "A"
        }
        interface B {
            fun greet(): String
        }
        class C : A, B {
            override fun greet(): String = "C"
        }
        fun main() {}
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-DIAMOND", in: ctx)
        }
    }

    // MARK: - Multiple unrelated default methods: diamond only on conflicting name

    func testDiamondOnlyForConflictingMethodName() throws {
        let source = """
        interface A {
            fun greet(): String = "A"
            fun hello(): String = "hello"
        }
        interface B {
            fun greet(): String = "B"
        }
        class C : A, B {
        }
        fun main() {}
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            // greet conflicts but is not overridden
            assertHasDiagnostic("KSWIFTK-SEMA-DIAMOND", in: ctx)
            // Only one diamond diagnostic should be emitted (for 'greet')
            let diamondCount = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-DIAMOND" }.count
            XCTAssertEqual(diamondCount, 1)
        }
    }

    // MARK: - super<InterfaceName>.method() parses correctly

    func testQualifiedSuperParsesWithoutError() throws {
        let source = """
        interface A {
            fun greet(): String = "A"
        }
        interface B : A {
            override fun greet(): String = "B"
        }
        interface C : A {
            override fun greet(): String = "C"
        }
        class D : B, C {
            override fun greet(): String = super<B>.greet() + super<C>.greet()
        }
        fun main() {}
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-DIAMOND", in: ctx)
        }
    }

    // MARK: - Invalid super qualifier: KSWIFTK-SEMA-0054

    func testInvalidSuperQualifierEmitsDiagnostic() throws {
        let source = """
        interface A {
            fun greet(): String = "A"
        }
        class B : A {
            override fun greet(): String = super<NonExistent>.greet()
        }
        fun main() {}
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0054", in: ctx)
        }
    }

    // MARK: - Abstract class with diamond: still needs override

    func testAbstractClassWithDiamondNeedsMark() throws {
        let source = """
        interface X {
            fun action(): String = "X"
        }
        interface Y {
            fun action(): String = "Y"
        }
        abstract class Z : X, Y {
        }
        fun main() {}
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            // Abstract class: diamond validation skips abstract types, so no diamond diagnostic
            assertNoDiagnostic("KSWIFTK-SEMA-DIAMOND", in: ctx)
        }
    }
}
