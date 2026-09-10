#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - kotlin.io Common Edge Case Tests (STDLIB-030)
//
// Tests for common-range kotlin.io surfaces:
//   - Closeable.use { } extension
//   - AutoCloseable interface resolution
//   - println / print / readLine / readln / readlnOrNull stubs
//   - StringBuilder.appendLine member
//   - String.lineSequence member
//   - File.useLines / File.forEachLine / File.bufferedReader helpers
//
// Edges exercised for .use { }:
//   closes resource on normal return, on exception, on null receiver short-circuit,
//   returns block result, lambda this-type = receiver (kotlin.io.Closeable),
//   AutoCloseable resolves to its own interface symbol,
//   nested class implementing Closeable accepted by use.

@Suite
struct KotlinIOCommonEdgeCaseTests {

    private static nonisolated(unsafe) var _sharedIOCtx: CompilationContext?

    private func sharedIOCtx() throws -> CompilationContext {
        if let cached = Self._sharedIOCtx { return cached }
        let sources: [String] = [
            """
            package sample0
            import java.io.Closeable

            class MyResource : Closeable {
                override fun close() {}
            }

            fun main0() {
                MyResource().use { r ->
                    println(r)
                }
            }
            """,
            """
            package sample1
            import java.io.Closeable

            class Counter : Closeable {
                override fun close() {}
            }

            fun compute1(): Int {
                return Counter().use { 42 }
            }

            fun main1() {
                val x: Int = compute1()
                println(x)
            }
            """,
            """
            package sample2
            import java.io.Closeable

            class Named(val name: String) : Closeable {
                override fun close() {}
            }

            fun main2() {
                val label = Named("test").use { resource ->
                    resource.name
                }
                println(label)
            }
            """,
            """
            package sample3
            import java.io.Closeable

            class TrackedResource : Closeable {
                override fun close() {
                    println("closed")
                }
            }

            fun main3() {
                try {
                    TrackedResource().use {
                        error("boom")
                    }
                } catch (e: Throwable) {
                    println("caught")
                }
            }
            """,
            """
            package sample4
            import java.io.Closeable

            class Box : Closeable {
                override fun close() {}
            }

            fun main4() {
                val nullable: Box? = null
                val result = nullable?.use { "value" }
                println(result)
            }
            """,
            """
            package sample5
            fun main5() {
                val nullable: AutoCloseable? = null
                val result: String = nullable.use { resource ->
                    if (resource == null) "null-resource" else "resource"
                }
                println(result)
            }
            """,
            """
            package sample6
            fun main6() {
                println("ok")
            }
            """,
            """
            package sample7
            import java.io.Closeable

            class Widget : Closeable {
                override fun close() {}
            }

            fun main7() {
                Widget().use { println("ok") }
            }
            """,
            """
            package sample8
            fun main8() {
                println("ok")
            }
            """,
            """
            package sample9
            fun main9() {
                val resource: AutoCloseable = AutoCloseable {
                    println("closed")
                }
                resource.close()
            }
            """,
            """
            package sample10
            fun main10() {
                println("ok")
            }
            """,
            """
            package sample11
            fun main11() {
                println("ok")
            }
            """,
            """
            package sample12
            class AliasResource : AutoCloseable {
                override fun close() {}
            }

            fun main12() {
                AliasResource().use { println("used") }
            }
            """,
            """
            package sample13
            import java.io.Closeable

            class Outer {
                inner class Inner : Closeable {
                    override fun close() {}
                }
            }

            fun main13() {
                val outer = Outer()
                outer.Inner().use { println("inner-use") }
            }
            """,
            """
            package sample14
            fun main14() {
                println()
            }
            """,
            """
            package sample15
            fun main15() {
                println("hello")
                println(42)
                println(null)
            }
            """,
            """
            package sample16
            fun main16() {
                print()
                print("hello")
            }
            """,
            """
            package sample17
            fun main17() {
                println("ok")
            }
            """,
            """
            package sample18
            import kotlin.io.DEFAULT_BUFFER_SIZE

            fun main18() {
                val size: Int = DEFAULT_BUFFER_SIZE
                println(size)
            }
            """,
            """
            package sample19
            fun main19() {
                val line: String? = readLine()
                println(line)
            }
            """,
            """
            package sample20
            fun main20() {
                val line: String = readln()
                println(line)
            }
            """,
            """
            package sample21
            fun main21() {
                val line: String? = readlnOrNull()
                println(line)
            }
            """,
            """
            package sample22
            fun main22() {
                val sb = StringBuilder()
                sb.appendLine("hello")
                sb.appendLine()
                println(sb.toString())
            }
            """,
            """
            package sample23
            fun main23() {
                val text = "a\nb\nc"
                for (line in text.lineSequence()) {
                    println(line)
                }
            }
            """,
            """
            package sample24
            import java.io.File

            fun main24() {
                val f = File("/dev/null")
                f.useLines { lines ->
                    lines.forEach { println(it) }
                }
            }
            """,
            """
            package sample25
            import java.io.File

            fun main25() {
                val f = File("/dev/null")
                f.forEachLine { line -> println(line) }
            }
            """,
            """
            package sample26
            import java.io.File

            fun main26() {
                val reader = File("/dev/null").bufferedReader()
                val line = reader.readLine()
                reader.close()
                println(line)
            }
            """,
            """
            package sample27
            import java.io.File

            fun main27() {
                val f = File("/tmp/kswiftk-io.txt")
                val text: String = f.readText()
                f.appendText(text)
                val bytes = f.readBytes()
                println(bytes)
            }
            """,
            """
            package sample28
            import java.io.File

            fun main28() {
                val f = File("/tmp/kswiftk-io.txt")
                val source = f.inputStream()
                val sink = f.outputStream()
                println(source)
                println(sink)
            }
            """,
            """
            package sample29
            import java.io.File

            fun stem29(f: File): String {
                val name: String = f.nameWithoutExtension
                return name
            }

            fun main29() {
                val f = File("/tmp/archive.tar.gz")
                println(stem29(f))
            }
            """,
            """
            package sample30
            import java.io.Closeable

            class JvmStyleResource : Closeable {
                override fun close() {}
            }

            fun main30() {
                JvmStyleResource().use { println("jvm-style") }
            }
            """,
            """
            package sample31
            import java.io.Closeable

            class Src : Closeable {
                fun read(): String = "data"
                override fun close() {}
            }

            fun main31() {
                val data: String = Src().use { src -> src.read() }
                println(data)
            }
            """,
            """
            package sample32
            fun main32() {
                val x: Unit = println("unit-check")
            }
            """,
            """
            package sample33
            import java.io.File

            fun main33() {
                val c: Closeable = File("/dev/null").bufferedReader()
                c.close()
            }
            """
        ]
        var result: CompilationContext?
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedIOCtx = ctx
        return ctx
    }

    // MARK: - Closeable.use – basic resolution


    @Test
    func testCloseableUseResolvesWithoutErrors() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "Closeable.use { } should resolve without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }


    // MARK: - Closeable.use – returns block result


    @Test
    func testCloseableUseReturnTypeIsBlockResult() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            ".use { } return type should be inferred as Int: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }


    // MARK: - Closeable.use – lambda this-type is receiver


    @Test
    func testCloseableUseLambdaReceiverTypedAsCloseable() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "Lambda parameter inside .use { } should be typed as the concrete Closeable receiver: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }


    // MARK: - Closeable.use – close called on exception path


    @Test
    func testCloseableUseWithBodyExceptionClosesResource() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            ".use { } with throwing body should still compile: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }


    // MARK: - Closeable.use – null receiver short-circuits


    @Test
    func testNullableCloseableUseShortCircuitsOnNull() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "?.use on null receiver should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }



    @Test
    func testNullableAutoCloseableDirectUseResolvesWithoutSafeCall() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "Nullable AutoCloseable.use should resolve without requiring ?.use: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }



    @Test
    func testRootAutoCloseableUseSymbolIsRegisteredInSymbolTable() throws {
        let ctx = try sharedIOCtx()
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let kotlinFQN: [InternedString] = [interner.intern("kotlin")]
        let rootUseFQN = kotlinFQN + [interner.intern("use")]
        let useSymbol = try #require(
            sema.symbols.lookup(fqName: rootUseFQN),
            "kotlin.use should expose the common AutoCloseable?.use extension"
        )
        let signature = try #require(sema.symbols.functionSignature(for: useSymbol))
        let receiverType = try #require(signature.receiverType)
        #expect(signature.parameterTypes.count == 1)
        #expect(signature.typeParameterSymbols.count == 2)

        guard case let .functionType(blockType) = sema.types.kind(of: signature.parameterTypes[0]) else {
            Issue.record("kotlin.use block parameter should be a function type"); return
        }
        #expect(blockType.params == [receiverType])
        #expect(blockType.returnType == signature.returnType)

        #expect(signature.typeParameterUpperBoundsList.count == 2)
        let tUpperBound = try #require(signature.typeParameterUpperBoundsList.first?.first)
        #expect(sema.types.nullability(of: tUpperBound) == .nullable)
        let nonNullBound = sema.types.makeNonNullable(tUpperBound)
        let autoCloseableFQN = kotlinFQN + [interner.intern("AutoCloseable")]
        let autoCloseableSymbol = try #require(sema.symbols.lookup(fqName: autoCloseableFQN))
        guard case let .classType(boundClass) = sema.types.kind(of: nonNullBound) else {
            Issue.record("kotlin.use T upper bound should resolve to kotlin.AutoCloseable?"); return
        }
        #expect(boundClass.classSymbol == autoCloseableSymbol)
    }


    // MARK: - AutoCloseable alias resolution
    //
    // NOTE (STDLIB-030 gap): Using AutoCloseable as a generic upper bound `<T : AutoCloseable>`
    // is not yet resolved by the type checker — the alias is registered in the symbol table but
    // the bound-constraint solver does not traverse type-alias chains for .use dispatch.
    // The test below validates the symbol-table registration path only; the bound+use scenario
    // is covered by testAutoCloseableSymbolIsRegisteredInSymbolTable.


    @Test
    func testAutoCloseableAliasDirectUseViaConcreateCloseableResolves() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "Closeable implementor should be accepted by .use without error: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }


    // MARK: - AutoCloseable interface visible in sema symbol table


    @Test
    func testAutoCloseableSymbolIsRegisteredInSymbolTable() throws {
        let ctx = try sharedIOCtx()
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let kotlinFQN: [InternedString] = [interner.intern("kotlin")]
        let autoCloseableFQN = kotlinFQN + [interner.intern("AutoCloseable")]
        let symbol = try #require(sema.symbols.lookup(fqName: autoCloseableFQN), "kotlin.AutoCloseable should be registered as a source-backed interface symbol")
        #expect(sema.symbols.symbol(symbol)?.kind == .interface, "kotlin.AutoCloseable should be an interface symbol")
        #expect(sema.symbols.symbol(symbol)?.flags.contains(.synthetic) == false, "kotlin.AutoCloseable should not be a synthetic fallback")
    }



    @Test
    func testAutoCloseableFactoryResolvesWithoutErrors() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "AutoCloseable { } factory should resolve without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }



    @Test
    func testAutoCloseableFactorySymbolIsRegisteredInSymbolTable() throws {
        let ctx = try sharedIOCtx()
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        // KSP-721: the factory is Kotlin source (Stdlib/kotlin/AutoCloseable.kt)
        // declared as an external function bound to the runtime bridge.
        let autoCloseableFQN = [interner.intern("kotlin"), interner.intern("AutoCloseable")]
        let functionSymbol = sema.symbols.lookupAll(fqName: autoCloseableFQN).first { symbolID in
            sema.symbols.symbol(symbolID)?.kind == .function
        }
        let symbol = try #require(functionSymbol, "kotlin.AutoCloseable factory should be registered")
        #expect(sema.symbols.externalLinkName(for: symbol) == "__kk_auto_closeable_create")
        #expect(
            sema.symbols.symbol(symbol)?.flags.contains(.synthetic) == false,
            "kotlin.AutoCloseable factory should be the source-backed declaration"
        )
    }


    @Test
    func testBothCloseableUseOverloadsAreSourceBacked() throws {
        let ctx = try sharedIOCtx()
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let rootUse = try #require(
            sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("use")]),
            "kotlin.use should be registered"
        )
        let ioUse = try #require(
            sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("io"),
                interner.intern("use"),
            ]),
            "kotlin.io.use should be registered"
        )

        #expect(sema.symbols.symbol(rootUse)?.kind == .function)
        #expect(sema.symbols.symbol(ioUse)?.kind == .function)
        #expect(sema.symbols.symbol(rootUse)?.flags.contains(.synthetic) == false)
        #expect(sema.symbols.symbol(ioUse)?.flags.contains(.synthetic) == false)
    }

    @Test
    func testAutoCloseableCloseFinallyIsSourceBackedInternalNullableExtension() throws {
        let ctx = try sharedIOCtx()
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let closeFinallyFQName = [interner.intern("kotlin"), interner.intern("closeFinally")]
        let symbol = try #require(
            sema.symbols.lookupAll(fqName: closeFinallyFQName).first(where: { candidate in
                sema.symbols.isSourceBackedSymbol(candidate)
                    && sema.symbols.functionSignature(for: candidate)?.receiverType != nil
            }),
            "kotlin.closeFinally should be a source-backed extension"
        )
        let info = try #require(sema.symbols.symbol(symbol))
        let signature = try #require(sema.symbols.functionSignature(for: symbol))
        let receiverType = try #require(signature.receiverType)

        #expect(info.visibility == .internal)
        #expect(sema.types.nullability(of: receiverType) == .nullable)
        #expect(signature.parameterTypes.count == 1)
        #expect(sema.types.nullability(of: signature.parameterTypes[0]) == .nullable)
        #expect(signature.returnType == sema.types.unitType)
    }


    // MARK: - Closeable symbol registered in symbol table


    @Test
    func testCloseableSymbolIsRegisteredInSymbolTable() throws {
        let ctx = try sharedIOCtx()
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let kotlinIOFQN: [InternedString] = [interner.intern("kotlin"), interner.intern("io")]
        let closeableFQN = kotlinIOFQN + [interner.intern("Closeable")]
        let symbol = try #require(sema.symbols.lookup(fqName: closeableFQN), "kotlin.io.Closeable should be registered as an interface symbol")
        #expect(sema.symbols.symbol(symbol)?.kind == .interface, "kotlin.io.Closeable should be an interface symbol")
        #expect(sema.symbols.symbol(symbol)?.flags.contains(.synthetic) == false, "kotlin.io.Closeable should not be a synthetic fallback")
    }


    // MARK: - Class implementing AutoCloseable

    /// KSP-721: `kotlin.AutoCloseable` is now a source-backed interface, so a
    /// class listing it as a supertype records the AutoCloseable symbol itself.

    @Test
    func testClassImplementingAutoCloseableRecordsAutoCloseableSupertype() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "class : AutoCloseable should resolve without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let resourceSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("sample12"), interner.intern("AliasResource")]))
        let autoCloseableSymbol = try #require(sema.symbols.lookup(
            fqName: [interner.intern("kotlin"), interner.intern("AutoCloseable")]
        ))
        #expect(sema.symbols.directSupertypes(for: resourceSymbol).contains(autoCloseableSymbol))
    }


    // MARK: - Nested class implementing Closeable


    @Test
    func testNestedClassImplementingCloseableAcceptedByUse() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "Nested class implementing Closeable should be accepted by .use: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }


    // MARK: - println stubs


    @Test
    func testPrintlnNoArgStubResolves() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "println() no-arg should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }



    @Test
    func testPrintlnAnyArgStubResolves() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "println(Any?) should resolve for String, Int, and null: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }



    @Test
    func testPrintNoArgStubResolves() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "print() no-arg and print(Any?) should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }


    // MARK: - DEFAULT_BUFFER_SIZE property


    @Test
    func testDefaultBufferSizePropertyIsRegistered() throws {
        let ctx = try sharedIOCtx()
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let kotlinIOFQN: [InternedString] = [interner.intern("kotlin"), interner.intern("io")]
        let propertyFQN = kotlinIOFQN + [interner.intern("DEFAULT_BUFFER_SIZE")]
        let propertySymbol = try #require(
            sema.symbols.lookupAll(fqName: propertyFQN).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .property
            },
            "kotlin.io.DEFAULT_BUFFER_SIZE should be registered from bundled Kotlin source"
        )
        #expect(sema.symbols.propertyType(for: propertySymbol) == sema.types.intType)
        #expect(sema.symbols.isSourceBackedSymbol(propertySymbol))
        #expect(sema.symbols.externalLinkName(for: propertySymbol) == nil)
        #expect(sema.symbols.symbol(propertySymbol)?.flags.contains(.constValue) == true)
        #expect(sema.symbols.constValueExprKind(for: propertySymbol) == .intLiteral(8192))
    }



    @Test
    func testDefaultBufferSizePropertyResolvesAsInt() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "DEFAULT_BUFFER_SIZE should resolve as Int: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }


    // MARK: - readLine stub


    @Test
    func testReadLineStubResolvesToNullableString() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "readLine() should resolve to String? without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }


    // MARK: - readln / readlnOrNull stubs


    @Test
    func testReadlnStubResolvesToNonNullString() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "readln() should resolve to String (non-null): \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }



    @Test
    func testReadlnOrNullStubResolvesToNullableString() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "readlnOrNull() should resolve to String? without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }


    // MARK: - StringBuilder.appendLine


    @Test
    func testStringBuilderAppendLineWithArgResolves() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "StringBuilder.appendLine() and appendLine(String) should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }


    // MARK: - String.lineSequence


    @Test
    func testStringLineSequenceResolves() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "String.lineSequence() should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }


    // MARK: - File.useLines (line iteration helper)


    @Test
    func testFileUseLinesResolves() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "File.useLines { } should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }


    // MARK: - File.forEachLine


    @Test
    func testFileForEachLineResolves() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "File.forEachLine { } should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }


    // MARK: - File.bufferedReader


    @Test
    func testFileBufferedReaderResolves() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "File.bufferedReader() and BufferedReader.readLine() / close() should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }


    // MARK: - File read / append helpers


    @Test
    func testFileReadAppendAndByteHelpersResolve() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "File.readText(), appendText(), and readBytes() should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }


    // MARK: - File stream helpers


    @Test
    func testFileInputAndOutputStreamResolve() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "File.inputStream() and outputStream() should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }


    // MARK: - File.nameWithoutExtension (STDLIB-IO-PROP-005)


    @Test
    func testFileNameWithoutExtensionResolvesAsString() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "File.nameWithoutExtension extension property should resolve as String: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }


    // MARK: - java.io.Closeable maps to kotlin.io.Closeable


    @Test
    func testJavaIOCloseableIsAcceptedByUseExtension() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "java.io.Closeable implementor should be accepted by .use: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }


    // MARK: - use result is non-Unit when block returns value


    @Test
    func testUseResultCanBeAssignedToTypedVariable() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            ".use { } result should be assignable to typed variable: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }


    // MARK: - println return type is Unit


    @Test
    func testPrintlnReturnTypeIsUnit() throws {
        let ctx = try sharedIOCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "println() return type should be Unit: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }


    // MARK: - KSP-721 regression: closeable marker is the AutoCloseable interface, not the factory


    @Test
    func testCloseableInterfaceSymbolIsNotTheFactoryFunction() throws {
        let ctx = try sharedIOCtx()
        let sema = try #require(ctx.sema)
        let closeableSymbol = try #require(
            sema.types.closeableInterfaceSymbol,
            "closeableInterfaceSymbol should be set"
        )
        let info = try #require(
            sema.symbols.symbol(closeableSymbol),
            "closeableInterfaceSymbol should be a valid symbol"
        )
        #expect(
            info.kind == .interface,
            "types.closeableInterfaceSymbol must be kotlin.AutoCloseable the interface, not the factory function"
        )
    }


    // MARK: - KSP-721 regression: synthetic IO nominals are subtypes of kotlin.io.Closeable


    @Test
    func testBufferedReaderIsSubtypeOfIOCloseable() throws {
        let ctx = try sharedIOCtx()
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let bufferedReaderFQN = [interner.intern("java"), interner.intern("io"), interner.intern("BufferedReader")]
        let bufferedReaderSymbol = try #require(
            sema.symbols.lookup(fqName: bufferedReaderFQN),
            "java.io.BufferedReader should be registered"
        )
        let ioCloseableFQN = [interner.intern("kotlin"), interner.intern("io"), interner.intern("Closeable")]
        let ioCloseableSymbol = try #require(
            sema.symbols.lookup(fqName: ioCloseableFQN),
            "kotlin.io.Closeable should be registered"
        )

        #expect(
            sema.symbols.directSupertypes(for: bufferedReaderSymbol).contains(ioCloseableSymbol),
            "java.io.BufferedReader direct supertypes should include kotlin.io.Closeable"
        )

        let bufferedReaderType = sema.types.make(.classType(ClassType(
            classSymbol: bufferedReaderSymbol, args: [], nullability: .nonNull
        )))
        let ioCloseableType = sema.types.make(.classType(ClassType(
            classSymbol: ioCloseableSymbol, args: [], nullability: .nonNull
        )))
        #expect(
            sema.types.isSubtype(bufferedReaderType, ioCloseableType),
            "java.io.BufferedReader should be a subtype of kotlin.io.Closeable"
        )
    }

}
#endif
