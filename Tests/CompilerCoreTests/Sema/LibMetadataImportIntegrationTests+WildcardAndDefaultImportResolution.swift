@testable import CompilerCore
import Foundation
import XCTest

extension LibMetadataImportIntegrationTests {
    func testWildcardImportResolvesKklibSymbolInScope() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ScopeLib",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=3
        package _ fq=sc.util schema=v1
        function _ fq=sc.util.compute schema=v1 arity=1 sig=F1<I,I>
        class _ fq=sc.util.Engine schema=v1
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let source = """
        import sc.util.*
        fun main(): Int = compute(42)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ScopeApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)

            // Verify the symbol is present
            let computeSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "compute" &&
                    symbol.kind == .function &&
                    symbol.flags.contains(.synthetic)
            }
            XCTAssertNotNil(computeSymbol, "Wildcard import should make library function 'compute' available")

            // Verify no SEMA/TYPE diagnostics (proves the symbol resolved in scope)
            let semaErrors = ctx.diagnostics.diagnostics.filter {
                $0.code.hasPrefix("KSWIFTK-SEMA") || $0.code.hasPrefix("KSWIFTK-TYPE")
            }
            XCTAssertTrue(semaErrors.isEmpty, "Wildcard import should resolve library function without errors: \(semaErrors.map(\.code))")
        }
    }

    func testDefaultImportResolvesKklibSymbolInScope() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "StdlibDefault",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=3
        package _ fq=kotlin schema=v1
        package _ fq=kotlin.text schema=v1
        function _ fq=kotlin.text.isBlank schema=v1 arity=1 sig=F1<Lkotlin_String;,Z>
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let source = """
        fun main(): Boolean = isBlank("")
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "DefaultScopeApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let isBlankSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "isBlank" &&
                    symbol.kind == .function &&
                    symbol.flags.contains(.synthetic)
            }
            XCTAssertNotNil(isBlankSymbol, "Default import should make library function 'isBlank' from kotlin.text available")

            let semaErrors = ctx.diagnostics.diagnostics.filter {
                $0.code.hasPrefix("KSWIFTK-SEMA") || $0.code.hasPrefix("KSWIFTK-TYPE")
            }
            XCTAssertTrue(semaErrors.isEmpty, "Default import should resolve library function without errors: \(semaErrors.map(\.code))")
        }
    }

    func testWildcardImportWithoutExplicitPackageRecordInMetadata() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "NoPackageRecord",
          "metadata": "metadata.bin"
        }
        """
        // Metadata has no explicit package records; packages should be synthesized
        let metadata = """
        symbols=2
        function _ fq=np.api.doWork schema=v1 arity=0
        class _ fq=np.api.Worker schema=v1
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let source = """
        import np.api.*
        fun main() = doWork()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "NoPackageApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)

            // Verify synthetic package was created
            let packageSymbol = sema.symbols.allSymbols().first { symbol in
                symbol.kind == .package &&
                    symbol.fqName.map { ctx.interner.resolve($0) } == ["np", "api"]
            }
            XCTAssertNotNil(packageSymbol, "Synthetic package 'np.api' should be created even without explicit package record")

            let doWorkSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "doWork" &&
                    symbol.kind == .function &&
                    symbol.flags.contains(.synthetic)
            }
            XCTAssertNotNil(doWorkSymbol, "Wildcard import should resolve function from synthesized package")

            let semaErrors = ctx.diagnostics.diagnostics.filter {
                $0.code.hasPrefix("KSWIFTK-SEMA") || $0.code.hasPrefix("KSWIFTK-TYPE")
            }
            XCTAssertTrue(semaErrors.isEmpty, "No SEMA errors expected: \(semaErrors.map(\.code))")
        }
    }

    func testMultipleKklibWildcardImportsCoexist() throws {
        let fm = FileManager.default

        // Create first library
        let baseDir1 = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir1 = baseDir1.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir1, withIntermediateDirectories: true)

        let manifest1 = """
        {
          "formatVersion": 1,
          "moduleName": "LibA",
          "metadata": "metadata.bin"
        }
        """
        let metadata1 = """
        symbols=2
        package _ fq=lib.a schema=v1
        function _ fq=lib.a.funcA schema=v1 arity=0
        """
        try manifest1.write(to: libDir1.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata1.write(to: libDir1.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        // Create second library
        let baseDir2 = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir2 = baseDir2.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir2, withIntermediateDirectories: true)

        let manifest2 = """
        {
          "formatVersion": 1,
          "moduleName": "LibB",
          "metadata": "metadata.bin"
        }
        """
        let metadata2 = """
        symbols=2
        package _ fq=lib.b schema=v1
        function _ fq=lib.b.funcB schema=v1 arity=0
        """
        try manifest2.write(to: libDir2.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata2.write(to: libDir2.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let source = """
        import lib.a.*
        import lib.b.*
        fun main() {
            funcA()
            funcB()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MultiLibApp",
                emit: .kirDump,
                searchPaths: [libDir1.path, libDir2.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)

            let funcA = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "funcA" && symbol.flags.contains(.synthetic)
            }
            let funcB = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "funcB" && symbol.flags.contains(.synthetic)
            }
            XCTAssertNotNil(funcA, "funcA from lib.a should be resolved via wildcard import")
            XCTAssertNotNil(funcB, "funcB from lib.b should be resolved via wildcard import")

            let semaErrors = ctx.diagnostics.diagnostics.filter {
                $0.code.hasPrefix("KSWIFTK-SEMA") || $0.code.hasPrefix("KSWIFTK-TYPE")
            }
            XCTAssertTrue(semaErrors.isEmpty, "No SEMA errors expected with multiple library wildcard imports: \(semaErrors.map(\.code))")
        }
    }

    func testPackageSymbolCreatedEvenWhenNonPackageSymbolExistsAtSamePath() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "CoexistLib",
          "metadata": "metadata.bin"
        }
        """
        // Library has both a class 'cx.util' and functions under package 'cx.util'
        let metadata = """
        symbols=3
        class _ fq=cx.util schema=v1
        function _ fq=cx.util.process schema=v1 arity=0
        function _ fq=cx.util.transform schema=v1 arity=1 sig=F1<I,I>
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let source = """
        import cx.util.*
        fun main() = process()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "CoexistApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)

            // Verify the package symbol was created despite the class 'cx.util' existing
            let packageSymbol = sema.symbols.allSymbols().first { symbol in
                symbol.kind == .package &&
                    symbol.fqName.map { ctx.interner.resolve($0) } == ["cx", "util"]
            }
            XCTAssertNotNil(packageSymbol, "Package 'cx.util' should be created even when class 'cx.util' exists")

            let processSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "process" &&
                    symbol.kind == .function &&
                    symbol.flags.contains(.synthetic)
            }
            XCTAssertNotNil(processSymbol, "Wildcard import should resolve 'process' even when non-package symbol coexists at package path")

            let semaErrors = ctx.diagnostics.diagnostics.filter {
                $0.code.hasPrefix("KSWIFTK-SEMA") || $0.code.hasPrefix("KSWIFTK-TYPE")
            }
            XCTAssertTrue(semaErrors.isEmpty, "No SEMA errors expected: \(semaErrors.map(\.code))")
        }
    }

    func testDefaultImportFromMultipleStdlibPackagesInKklib() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "StdlibMulti",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=5
        package _ fq=kotlin schema=v1
        package _ fq=kotlin.collections schema=v1
        package _ fq=kotlin.text schema=v1
        function _ fq=kotlin.collections.listOf schema=v1 arity=0 sig=F0<A>
        function _ fq=kotlin.text.trim schema=v1 arity=1 sig=F1<Lkotlin_String;,Lkotlin_String;>
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let source = """
        fun main() {
            listOf()
            trim("")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MultiStdlibApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)

            let listOfSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "listOf" && symbol.flags.contains(.synthetic)
            }
            let trimSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "trim" && symbol.flags.contains(.synthetic)
            }
            XCTAssertNotNil(listOfSymbol, "Default import should resolve 'listOf' from kotlin.collections")
            XCTAssertNotNil(trimSymbol, "Default import should resolve 'trim' from kotlin.text")

            let semaErrors = ctx.diagnostics.diagnostics.filter {
                $0.code.hasPrefix("KSWIFTK-SEMA") || $0.code.hasPrefix("KSWIFTK-TYPE")
            }
            XCTAssertTrue(semaErrors.isEmpty, "No SEMA errors expected: \(semaErrors.map(\.code))")
        }
    }
}
