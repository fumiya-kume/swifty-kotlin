import Foundation
import XCTest
@testable import CompilerCore

final class LibraryMetadataManifestValidationTests: XCTestCase {
    // MARK: - P5-54: Missing/Invalid manifest.json

    func testMissingManifestJsonEmitsErrorAndSkipsLibrary() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        // Create metadata.bin but NO manifest.json
        let metadata = """
        symbols=1
        function _ fq=nm.foo schema=v1 arity=0
        """
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "NoManifestApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0015", in: ctx)
            let hasImported = ctx.sema?.symbols.allSymbols().contains { symbol in
                ctx.interner.resolve(symbol.name) == "foo" && symbol.flags.contains(.synthetic)
            }
            XCTAssertFalse(hasImported ?? false, "Library without manifest.json should not load symbols")
        }
    }

    func testInvalidJsonManifestEmitsErrorAndSkipsLibrary() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let invalidJson = "this is not json {{{}"
        try invalidJson.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let metadata = """
        symbols=1
        function _ fq=ij.bar schema=v1 arity=0
        """
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "InvalidJsonApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0015", in: ctx)
            let hasImported = ctx.sema?.symbols.allSymbols().contains { symbol in
                ctx.interner.resolve(symbol.name) == "bar" && symbol.flags.contains(.synthetic)
            }
            XCTAssertFalse(hasImported ?? false, "Library with invalid JSON manifest should not load symbols")
        }
    }

    // MARK: - P5-54: Missing metadata field warning

    func testManifestMissingMetadataFieldEmitsWarning() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "NoMetaField"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=nmf.fn schema=v1 arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "NoMetaFieldApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let metadataWarnings = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-LIB-0016" && $0.severity == .warning
            }
            XCTAssertFalse(metadataWarnings.isEmpty, "Should warn when 'metadata' field is missing from manifest")
        }
    }

    // MARK: - P5-54: compilerVersion validation

    func testManifestEmptyCompilerVersionEmitsWarning() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "EmptyCV",
          "compilerVersion": "",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=ecv.fn schema=v1 arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "EmptyCVApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let cvWarnings = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-LIB-0017" && $0.severity == .warning
            }
            XCTAssertFalse(cvWarnings.isEmpty, "Should warn when 'compilerVersion' is empty")
        }
    }

    func testManifestInvalidCompilerVersionTypeEmitsWarning() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "BadCVType",
          "compilerVersion": 123,
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=bcvt.fn schema=v1 arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "BadCVTypeApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let cvWarnings = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-LIB-0017" && $0.severity == .warning
            }
            XCTAssertFalse(cvWarnings.isEmpty, "Should warn when 'compilerVersion' is not a string")
        }
    }

    func testManifestValidCompilerVersionDoesNotWarn() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
        let t = defaultTargetTriple()
        let targetStr = "\(t.arch)-\(t.vendor)-\(t.os)"

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "GoodCV",
          "kotlinLanguageVersion": "2.3.10",
          "compilerVersion": "0.1.0",
          "target": "\(targetStr)",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=gcv.fn schema=v1 arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "GoodCVApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertNoDiagnostic("KSWIFTK-LIB-0017", in: ctx)
        }
    }

    // MARK: - P5-54: Path traversal protection

    func testManifestMetadataPathTraversalEmitsError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "Traversal",
          "metadata": "../../etc/passwd"
        }
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "TraversalApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0018", in: ctx)
        }
    }

    func testManifestObjectPathTraversalEmitsError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ObjTraversal",
          "metadata": "metadata.bin",
          "objects": ["../../secret.o"]
        }
        """
        let metadata = """
        symbols=1
        function _ fq=ot.fn schema=v1 arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ObjTraversalApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0018", in: ctx)
        }
    }

    func testManifestInlineKIRDirPathTraversalEmitsError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "InlineTraversal",
          "metadata": "metadata.bin",
          "inlineKIRDir": "../../../tmp"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=it.fn schema=v1 arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "InlineTraversalApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0018", in: ctx)
        }
    }

    // MARK: - P5-54: Invalid objects field type

    func testManifestInvalidObjectsFieldTypeEmitsError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "BadObjects",
          "metadata": "metadata.bin",
          "objects": "not-an-array"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=bo.fn schema=v1 arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "BadObjectsApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let objectsErrors = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-LIB-0014" && $0.message.contains("Invalid 'objects' field type")
            }
            XCTAssertFalse(objectsErrors.isEmpty, "Should emit error when 'objects' is not an array")
        }
    }

    // MARK: - P5-54: Full valid manifest with all fields passes cleanly

    func testFullyValidManifestProducesNoSchemaErrors() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        let objectsDir = libDir.appendingPathComponent("objects")
        let inlineDir = libDir.appendingPathComponent("inline-kir")
        try fm.createDirectory(at: objectsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: inlineDir, withIntermediateDirectories: true)
        let t = defaultTargetTriple()
        let targetStr = "\(t.arch)-\(t.vendor)-\(t.os)"

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "FullValid",
          "kotlinLanguageVersion": "2.3.10",
          "compilerVersion": "0.1.0",
          "target": "\(targetStr)",
          "objects": ["objects/FullValid_0.o"],
          "metadata": "metadata.bin",
          "inlineKIRDir": "inline-kir"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=fv.fn schema=v1 arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        // Create a dummy object file so path check passes
        try "".write(to: objectsDir.appendingPathComponent("FullValid_0.o"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "FullValidApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertNoDiagnostic("KSWIFTK-LIB-0010", in: ctx)
            assertNoDiagnostic("KSWIFTK-LIB-0011", in: ctx)
            assertNoDiagnostic("KSWIFTK-LIB-0012", in: ctx)
            assertNoDiagnostic("KSWIFTK-LIB-0013", in: ctx)
            assertNoDiagnostic("KSWIFTK-LIB-0014", in: ctx)
            assertNoDiagnostic("KSWIFTK-LIB-0015", in: ctx)
            assertNoDiagnostic("KSWIFTK-LIB-0016", in: ctx)
            assertNoDiagnostic("KSWIFTK-LIB-0017", in: ctx)
            assertNoDiagnostic("KSWIFTK-LIB-0018", in: ctx)

            // Verify the symbol was loaded
            let fnSymbol = ctx.sema?.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "fn" && symbol.flags.contains(.synthetic)
            }
            XCTAssertNotNil(fnSymbol, "Fully valid manifest should load symbols successfully")
        }
    }

}
