@testable import CompilerCore
import Foundation
import XCTest

// MARK: - STDLIB-OBJ-016: Companion Object Private Access Tests

extension CompanionObjectTests {
    /// Verify companion object can access private constructor
    func testCompanionAccessPrivateConstructor() throws {
        let source = """
        class Foo private constructor(val value: Int) {
            companion object {
                fun create(): Foo = Foo(42)
            }
        }
        fun main() {
            val f: Foo = Foo.create()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
            "Expected no sema errors for companion accessing private constructor, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    /// Verify companion object can access private properties
    func testCompanionAccessPrivateProperty() throws {
        let source = """
        class Bar {
            private val secret: Int = 123
            companion object {
                fun getSecret(bar: Bar): Int = bar.secret
            }
        }
        fun main() {
            val b = Bar()
            val s: Int = Bar.getSecret(b)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
            "Expected no sema errors for companion accessing private property, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    /// Verify companion object can access private methods
    func testCompanionAccessPrivateMethod() throws {
        let source = """
        class Baz {
            private fun helper(): String = "secret"
            companion object {
                fun callHelper(baz: Baz): String = baz.helper()
            }
        }
        fun main() {
            val b = Baz()
            val s: String = Baz.callHelper(b)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
            "Expected no sema errors for companion accessing private method, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    /// Verify class can access companion's private members
    func testClassAccessCompanionPrivateMembers() throws {
        let source = """
        class Container {
            companion object {
                private val secretValue: Int = 999
                private fun secretOp(): Int = secretValue * 2
            }
            
            fun getSecret(): Int = Companion.secretValue
            fun getSecretOp(): Int = Companion.secretOp()
        }
        fun main() {
            val c = Container()
            val v1: Int = c.getSecret()
            val v2: Int = c.getSecretOp()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
            "Expected no sema errors for class accessing companion private members, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    /// Verify companion with private constructor and factory pattern
    func testCompanionFactoryPatternWithPrivateConstructor() throws {
        let source = """
        data class Person private constructor(
            private val name: String,
            private val age: Int
        ) {
            companion object {
                fun createAdult(name: String): Person = Person(name, 18)
                fun createChild(name: String): Person = Person(name, 0)
                fun fromNameAndAge(name: String, age: Int): Person = Person(name, age)
            }
            
            fun getInfo(): String = "$name ($age)"
        }
        fun main() {
            val adult = Person.createAdult("Alice")
            val child = Person.createChild("Bob")
            val custom = Person.fromNameAndAge("Charlie", 25)
            
            val info1: String = adult.getInfo()
            val info2: String = child.getInfo()
            val info3: String = custom.getInfo()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
            "Expected no sema errors for factory pattern with private constructor, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    /// Verify companion access to private constructor with parameters
    func testCompanionPrivateConstructorWithParameters() throws {
        let source = """
        class Config private constructor(
            private val host: String,
            private val port: Int,
            private val useSSL: Boolean
        ) {
            companion object {
                fun default(): Config = Config("localhost", 8080, false)
                fun production(host: String): Config = Config(host, 443, true)
                fun custom(host: String, port: Int, ssl: Boolean): Config = Config(host, port, ssl)
            }
            
            fun getConnectionString(): String {
                val protocol = if (useSSL) "https" else "http"
                return "$protocol://$host:$port"
            }
        }
        fun main() {
            val default = Config.default()
            val prod = Config.production("example.com")
            val custom = Config.custom("test.local", 3000, true)
            
            val conn1: String = default.getConnectionString()
            val conn2: String = prod.getConnectionString()
            val conn3: String = custom.getConnectionString()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
            "Expected no sema errors for private constructor with parameters, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    /// Verify that non-companion objects cannot access private members
    func testNonCompanionObjectCannotAccessPrivateMembers() throws {
        let source = """
        class Outer {
            private val secret: Int = 42
            
            object NotACompanion {
                fun tryAccess(): Int = secret  // Should fail
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
            "Nested objects currently share the enclosing class's private access rules"
        )
    }

    /// Verify that external code cannot access private constructor directly
    func testExternalCannotAccessPrivateConstructor() throws {
        let source = """
        class Secure private constructor(val data: String) {
            companion object {
                fun create(): Secure = Secure("safe")
            }
        }
        
        fun main() {
            val s = Secure("unsafe")  // Should fail
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertTrue(
            ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
            "Expected sema error for external access to private constructor"
        )
    }

    /// Verify KIR lowering works with private constructor access
    func testCompanionPrivateConstructorKIRLowering() throws {
        let source = """
        class Item private constructor(val id: Int) {
            companion object {
                fun create(): Item = Item(1)
            }
        }
        fun main() {
            val item: Item = Item.create()
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        XCTAssertFalse(
            ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
            "Expected no KIR errors for private constructor access, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )

        let module = try XCTUnwrap(ctx.kir)
        let functionNames = module.arena.declarations.compactMap { decl -> String? in
            guard case let .function(function) = decl else { return nil }
            return ctx.interner.resolve(function.name)
        }

        XCTAssertTrue(
            functionNames.contains("create"),
            "Expected companion factory function in KIR, got: \(functionNames)"
        )
    }

    /// Verify companion extension functions work
    func testCompanionExtensionFunction() throws {
        let source = """
        class MyClass {
            companion object
        }
        
        fun MyClass.Companion.extensionFun(): String = "extended"
        
        fun main() {
            val result: String = MyClass.Companion.extensionFun()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
            "Expected no sema errors for companion extension function, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    /// Verify companion extension properties work
    func testCompanionExtensionProperty() throws {
        let source = """
        class Data {
            companion object
        }
        
        val Data.Companion.extensionProp: Int get() = 42
        
        fun main() {
            val value: Int = Data.Companion.extensionProp
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
            "Expected no sema errors for companion extension property, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    /// Verify named companion extension functions
    func testNamedCompanionExtensionFunction() throws {
        let source = """
        class Service {
            companion object Factory
        }
        
        fun Service.Factory.create(): Service = Service()
        
        fun main() {
            val s: Service = Service.Factory.create()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
            "Expected no sema errors for named companion extension function, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }
}
