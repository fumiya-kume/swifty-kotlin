import Foundation
import XCTest
@testable import CompilerCore

final class BackendPipelineCoverageTests: XCTestCase {
    func testLoadSourcesPhaseReportsMissingInputsAndUnreadableFiles() {
        let emptyCtx = makeCompilationContext(inputs: [])
        XCTAssertThrowsError(try LoadSourcesPhase().run(emptyCtx))
        XCTAssertEqual(emptyCtx.diagnostics.diagnostics.last?.code, "KSWIFTK-SOURCE-0001")

        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("kt")
            .path
        let missingCtx = makeCompilationContext(inputs: [missingPath])
        XCTAssertThrowsError(try LoadSourcesPhase().run(missingCtx))
        XCTAssertEqual(missingCtx.diagnostics.diagnostics.last?.code, "KSWIFTK-SOURCE-0002")
    }

    func testRunToKIRAndLoweringRecordsAllPasses() throws {
        let source = """
        inline fun add(a: Int, b: Int) = a + b
        suspend fun susp(v: Int) = v
        fun chooser(flag: Boolean, n: Int) = when (flag) { true -> n + 1, false -> n - 1, else -> n }
        fun main() {
            add(1, 2)
            susp(3)
            chooser(true, 4)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            XCTAssertEqual(module.executedLowerings, [
                "NormalizeBlocks",
                "OperatorLowering",
                "ForLowering",
                "WhenLowering",
                "PropertyLowering",
                "DataEnumSealedSynthesis",
                "LambdaClosureConversion",
                "InlineLowering",
                "CoroutineLowering",
                "ABILowering"
            ])
            XCTAssertGreaterThan(module.functionCount, 0)
        }
    }

    func testCodegenEmitsKirDumpLLVMIRAndLibraryArtifacts() throws {
        let source = """
        inline fun helper(x: Int) = x + 1
        fun main() = helper(41)
        """

        try withTemporaryFile(contents: source) { path in
            let tempDir = FileManager.default.temporaryDirectory

            let kirBase = tempDir.appendingPathComponent(UUID().uuidString).path
            let kirCtx = makeCompilationContext(inputs: [path], moduleName: "KirMod", emit: .kirDump, outputPath: kirBase)
            try runToKIR(kirCtx)
            try LoweringPhase().run(kirCtx)
            try CodegenPhase().run(kirCtx)
            XCTAssertTrue(FileManager.default.fileExists(atPath: kirBase + ".kir"))

            let llvmBase = tempDir.appendingPathComponent(UUID().uuidString).path
            let llvmCtx = makeCompilationContext(inputs: [path], moduleName: "LLMod", emit: .llvmIR, outputPath: llvmBase)
            try runToKIR(llvmCtx)
            try LoweringPhase().run(llvmCtx)
            try CodegenPhase().run(llvmCtx)
            let llvmPath = try XCTUnwrap(llvmCtx.generatedLLVMIRPath)
            XCTAssertTrue(llvmPath.hasSuffix(".ll"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: llvmPath))

            let libBase = tempDir.appendingPathComponent(UUID().uuidString).path
            let libCtx = makeCompilationContext(inputs: [path], moduleName: "LibMod", emit: .library, outputPath: libBase)
            try runToKIR(libCtx)
            try LoweringPhase().run(libCtx)
            try CodegenPhase().run(libCtx)

            let libDir = libBase + ".kklib"
            let manifestPath = libDir + "/manifest.json"
            let metadataPath = libDir + "/metadata.bin"
            let objectPath = libDir + "/objects/LibMod_0.o"
            XCTAssertTrue(FileManager.default.fileExists(atPath: manifestPath))
            XCTAssertTrue(FileManager.default.fileExists(atPath: metadataPath))
            XCTAssertTrue(FileManager.default.fileExists(atPath: objectPath))

            let manifest = try String(contentsOfFile: manifestPath, encoding: .utf8)
            XCTAssertTrue(manifest.contains("\"moduleName\": \"LibMod\""))

            let metadata = try String(contentsOfFile: metadataPath, encoding: .utf8)
            XCTAssertTrue(metadata.contains("symbols="))

            let inlineDir = libDir + "/inline-kir"
            let inlineFiles = try FileManager.default.contentsOfDirectory(atPath: inlineDir)
            XCTAssertFalse(inlineFiles.isEmpty)
            XCTAssertTrue(inlineFiles.allSatisfy { $0.hasSuffix(".kirbin") })
        }
    }

    func testSemaLoadsSymbolsFromKklibSearchPath() throws {
        let librarySource = """
        package extdemo
        fun plus(v: Int) = v + 1
        """
        try withTemporaryFile(contents: librarySource) { libraryPath in
            let libraryBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let libraryCtx = makeCompilationContext(
                inputs: [libraryPath],
                moduleName: "ExtDemo",
                emit: .library,
                outputPath: libraryBase
            )
            try runToKIR(libraryCtx)
            try LoweringPhase().run(libraryCtx)
            try CodegenPhase().run(libraryCtx)

            let appSource = """
            import extdemo.plus
            fun main() = plus(41)
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let appCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "App",
                    emit: .kirDump,
                    searchPaths: [libraryBase + ".kklib"]
                )
                try runToKIR(appCtx)

                let sema = try XCTUnwrap(appCtx.sema)
                let importedPlus = sema.symbols.allSymbols().first { symbol in
                    appCtx.interner.resolve(symbol.name) == "plus" &&
                    symbol.kind == .function &&
                    symbol.flags.contains(.synthetic)
                }
                XCTAssertNotNil(importedPlus)
                XCTAssertFalse(appCtx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
            }
        }
    }

    func testLinkPhaseReportsMissingMainAndCanLinkExecutable() throws {
        try withTemporaryFile(contents: "fun notMain() = 0") { path in
            let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(inputs: [path], moduleName: "NoMain", emit: .executable, outputPath: out)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)

            XCTAssertThrowsError(try LinkPhase().run(ctx))
            XCTAssertTrue(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-LINK-0002" })
        }

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "HasMain",
                inputs: [path],
                outputPath: out,
                emit: .executable,
                target: TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: "14.0")
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )

            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: out))
        }
    }

    func testLLVMBackendEmitsOutputsAndReportsCommandFailure() throws {
        let interner = StringInterner()
        let module = makeComplexKIRModule(interner: interner)
        let backend = LLVMBackend(
            target: TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: "14.0"),
            optLevel: .O2,
            debugInfo: true,
            diagnostics: DiagnosticEngine()
        )

        let runtime = RuntimeLinkInfo(libraryPaths: [], libraries: [], extraObjects: [])
        let tempDir = FileManager.default.temporaryDirectory
        let irPath = tempDir.appendingPathComponent(UUID().uuidString + ".ll").path
        let objPath = tempDir.appendingPathComponent(UUID().uuidString + ".o").path

        try backend.emitLLVMIR(module: module, runtime: runtime, outputIRPath: irPath, interner: interner)
        try backend.emitObject(module: module, runtime: runtime, outputObjectPath: objPath, interner: interner)
        XCTAssertTrue(FileManager.default.fileExists(atPath: irPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: objPath))

        let fnName = LLVMBackend.cFunctionSymbol(
            for: KIRFunction(
                symbol: SymbolID(rawValue: 9),
                name: interner.intern("1 bad-name"),
                params: [],
                returnType: TypeSystem().unitType,
                body: [.returnUnit],
                isSuspend: false,
                isInline: false
            ),
            interner: interner
        )
        XCTAssertTrue(fnName.hasPrefix("kk_fn__1_bad_name_9"))

        let failingDiagnostics = DiagnosticEngine()
        let failingBackend = LLVMBackend(
            target: TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: failingDiagnostics
        )
        let missingDir = tempDir.appendingPathComponent(UUID().uuidString).path + "/sub/out.o"
        XCTAssertThrowsError(
            try failingBackend.emitObject(module: module, runtime: runtime, outputObjectPath: missingDir, interner: interner)
        )
        XCTAssertTrue(failingDiagnostics.diagnostics.contains { $0.code == "KSWIFTK-BACKEND-0001" })
    }

    func testLoweringRewritesMarkerCallsAndNormalizesEmptyFunctionBody() throws {
        let interner = StringInterner()
        let arena = KIRArena()

        let mainSym = SymbolID(rawValue: 10)
        let inlineSym = SymbolID(rawValue: 11)
        let suspendSym = SymbolID(rawValue: 12)
        let emptySym = SymbolID(rawValue: 13)

        let v0 = arena.appendExpr(.temporary(0))
        let v1 = arena.appendExpr(.temporary(1))

        let mainFn = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(symbol: nil, callee: interner.intern("__for_expr__"), arguments: [v0], result: v1, outThrown: false),
                .call(symbol: nil, callee: interner.intern("__when_expr__"), arguments: [v0], result: v1, outThrown: false),
                .call(symbol: nil, callee: interner.intern("get"), arguments: [v0], result: v1, outThrown: false),
                .call(symbol: nil, callee: interner.intern("set"), arguments: [v0], result: v1, outThrown: false),
                .call(symbol: nil, callee: interner.intern("<lambda>"), arguments: [v0], result: v1, outThrown: false),
                .call(symbol: nil, callee: interner.intern("inlineTarget"), arguments: [], result: v1, outThrown: false),
                .call(symbol: nil, callee: interner.intern("suspendTarget"), arguments: [v0], result: v1, outThrown: false),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )
        let inlineFn = KIRFunction(
            symbol: inlineSym,
            name: interner.intern("inlineTarget"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: true
        )
        let suspendFn = KIRFunction(
            symbol: suspendSym,
            name: interner.intern("suspendTarget"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [.returnUnit],
            isSuspend: true,
            isInline: false
        )
        let emptyFn = KIRFunction(
            symbol: emptySym,
            name: interner.intern("empty"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(inlineFn))
        _ = arena.appendDecl(.function(suspendFn))
        let emptyID = arena.appendDecl(.function(emptyFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID, emptyID])], arena: arena)

        let options = CompilerOptions(
            moduleName: "Lowering",
            inputs: [],
            outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let ctx = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module

        try LoweringPhase().run(ctx)

        guard case .function(let loweredMain)? = module.arena.decl(mainID) else {
            XCTFail("expected lowered main function")
            return
        }

        let callees = loweredMain.body.compactMap { instruction -> String? in
            guard case .call(_, let callee, _, _, _) = instruction else { return nil }
            return interner.resolve(callee)
        }
        XCTAssertTrue(callees.contains("iterator"))
        XCTAssertTrue(callees.contains("kk_for_lowered"))
        XCTAssertTrue(callees.contains("kk_when_select"))
        XCTAssertTrue(callees.contains("kk_property_access"))
        XCTAssertTrue(callees.contains("kk_lambda_invoke"))
        XCTAssertFalse(callees.contains("inlineTarget"))
        XCTAssertFalse(callees.contains("inlined_inlineTarget"))
        XCTAssertTrue(callees.contains("kk_coroutine_suspended"))
        XCTAssertTrue(callees.contains("kk_suspend_suspendTarget"))

        let loweredSuspend = module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case .function(let function) = decl else {
                return nil
            }
            return interner.resolve(function.name) == "kk_suspend_suspendTarget" ? function : nil
        }.first
        XCTAssertEqual(loweredSuspend?.params.count, 1)
        XCTAssertEqual(loweredSuspend?.isSuspend, false)
        let loweredSuspendCallees = loweredSuspend?.body.compactMap { instruction -> String? in
            guard case .call(_, let callee, _, _, _) = instruction else { return nil }
            return interner.resolve(callee)
        } ?? []
        XCTAssertTrue(loweredSuspendCallees.contains("kk_coroutine_state_enter"))
        XCTAssertTrue(loweredSuspendCallees.contains("kk_coroutine_state_exit"))

        let callThrowFlags: [String: [Bool]] = loweredMain.body.reduce(into: [:]) { partial, instruction in
            guard case .call(_, let callee, _, _, let outThrown) = instruction else {
                return
            }
            let name = interner.resolve(callee)
            partial[name, default: []].append(outThrown)
        }
        XCTAssertEqual(callThrowFlags["kk_coroutine_suspended"]?.allSatisfy({ $0 == false }), true)
        XCTAssertEqual(callThrowFlags["kk_suspend_suspendTarget"]?.allSatisfy({ $0 == true }), true)

        guard case .function(let loweredEmpty)? = module.arena.decl(emptyID) else {
            XCTFail("expected lowered empty function")
            return
        }
        XCTAssertEqual(loweredEmpty.body.last, .returnUnit)
        XCTAssertFalse(loweredEmpty.body.isEmpty)
    }

    func testInlineLoweringExpandsInlineBodyAndRewritesResultUse() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let callerSym = SymbolID(rawValue: 300)
        let inlineSym = SymbolID(rawValue: 301)
        let inlineParamSym = SymbolID(rawValue: 302)

        let inlineArg = arena.appendExpr(.temporary(0))
        let inlineOne = arena.appendExpr(.temporary(1))
        let inlineSum = arena.appendExpr(.temporary(2))
        let callerArg = arena.appendExpr(.temporary(3))
        let callerResult = arena.appendExpr(.temporary(4))

        let inlineFn = KIRFunction(
            symbol: inlineSym,
            name: interner.intern("plusOne"),
            params: [KIRParameter(symbol: inlineParamSym, type: types.make(.primitive(.int, .nonNull)))],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [
                .constValue(result: inlineArg, value: .symbolRef(inlineParamSym)),
                .constValue(result: inlineOne, value: .intLiteral(1)),
                .call(symbol: nil, callee: interner.intern("kk_op_add"), arguments: [inlineArg, inlineOne], result: inlineSum, outThrown: false),
                .returnValue(inlineSum)
            ],
            isSuspend: false,
            isInline: true
        )
        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [
                .constValue(result: callerArg, value: .intLiteral(41)),
                .call(symbol: inlineSym, callee: interner.intern("plusOne"), arguments: [callerArg], result: callerResult, outThrown: false),
                .returnValue(callerResult)
            ],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(inlineFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "InlineLowering",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        try LoweringPhase().run(ctx)

        guard case .function(let loweredCaller)? = module.arena.decl(callerID) else {
            XCTFail("expected lowered caller function")
            return
        }

        let calleeNames = loweredCaller.body.compactMap { instruction -> String? in
            guard case .call(_, let callee, _, _, _) = instruction else { return nil }
            return interner.resolve(callee)
        }
        XCTAssertFalse(calleeNames.contains("plusOne"))
        XCTAssertTrue(calleeNames.contains("kk_op_add"))

        let returnValues = loweredCaller.body.compactMap { instruction -> KIRExprID? in
            guard case .returnValue(let expr) = instruction else { return nil }
            return expr
        }
        XCTAssertEqual(returnValues.count, 1)
        XCTAssertNotEqual(returnValues.first, callerResult)
    }

    func testDataEnumSealedSynthesisAddsSyntheticHelpers() throws {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let sema = SemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)

        let packageName = interner.intern("demo")
        let packagePath = [packageName]

        let colorName = interner.intern("Color")
        let colorSymbol = symbols.define(
            kind: .enumClass,
            name: colorName,
            fqName: packagePath + [colorName],
            declSite: nil,
            visibility: .public
        )
        _ = symbols.define(
            kind: .field,
            name: interner.intern("RED"),
            fqName: packagePath + [colorName, interner.intern("RED")],
            declSite: nil,
            visibility: .public
        )
        _ = symbols.define(
            kind: .field,
            name: interner.intern("BLUE"),
            fqName: packagePath + [colorName, interner.intern("BLUE")],
            declSite: nil,
            visibility: .public
        )

        let baseName = interner.intern("Base")
        let baseSymbol = symbols.define(
            kind: .class,
            name: baseName,
            fqName: packagePath + [baseName],
            declSite: nil,
            visibility: .public,
            flags: [.sealedType]
        )
        let childName = interner.intern("Child")
        let childSymbol = symbols.define(
            kind: .class,
            name: childName,
            fqName: packagePath + [childName],
            declSite: nil,
            visibility: .public
        )
        symbols.setDirectSupertypes([baseSymbol], for: childSymbol)

        let pointName = interner.intern("Point")
        let pointSymbol = symbols.define(
            kind: .class,
            name: pointName,
            fqName: packagePath + [pointName],
            declSite: nil,
            visibility: .public,
            flags: [.dataType]
        )

        let arena = KIRArena()
        let colorDecl = arena.appendDecl(.nominalType(KIRNominalType(symbol: colorSymbol)))
        let baseDecl = arena.appendDecl(.nominalType(KIRNominalType(symbol: baseSymbol)))
        let pointDecl = arena.appendDecl(.nominalType(KIRNominalType(symbol: pointSymbol)))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [colorDecl, baseDecl, pointDecl])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "Synthesis",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
        ctx.sema = sema
        ctx.kir = module

        try LoweringPhase().run(ctx)

        let functionNames = module.arena.declarations.compactMap { decl -> String? in
            guard case .function(let function) = decl else {
                return nil
            }
            return interner.resolve(function.name)
        }
        XCTAssertTrue(functionNames.contains("Color$enumValuesCount"))
        XCTAssertTrue(functionNames.contains("Base$sealedSubtypeCount"))
        XCTAssertTrue(functionNames.contains("Point$copy"))

        let copyFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case .function(let function) = decl else {
                return nil
            }
            return interner.resolve(function.name) == "Point$copy" ? function : nil
        }.first
        XCTAssertEqual(copyFunction?.params.count, 1)
    }

    func testLinkPhaseGuardAndFailureBranches() throws {
        let objectCtx = makeCompilationContext(inputs: [], moduleName: "SkipLink", emit: .object)
        XCTAssertNoThrow(try LinkPhase().run(objectCtx))

        let missingObjectCtx = makeCompilationContext(inputs: [], moduleName: "MissingObj", emit: .executable)
        XCTAssertThrowsError(try LinkPhase().run(missingObjectCtx))

        let tempObjectURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".o")
        try Data().write(to: tempObjectURL)

        let noKirCtx = makeCompilationContext(inputs: [], moduleName: "NoKir", emit: .executable)
        noKirCtx.generatedObjectPath = tempObjectURL.path
        XCTAssertThrowsError(try LinkPhase().run(noKirCtx))

        let interner = StringInterner()
        let arena = KIRArena()
        let mainSym = SymbolID(rawValue: 99)
        let mainDecl = arena.appendDecl(.function(KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainDecl])], arena: arena)

        let badTargetOptions = CompilerOptions(
            moduleName: "BadTarget",
            inputs: [],
            outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
            emit: .executable,
            target: TargetTriple(arch: "definitely-bad-arch", vendor: "apple", os: "macosx", osVersion: nil)
        )
        let badTargetCtx = CompilationContext(
            options: badTargetOptions,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        badTargetCtx.generatedObjectPath = tempObjectURL.path
        badTargetCtx.kir = module

        XCTAssertThrowsError(try LinkPhase().run(badTargetCtx))
        XCTAssertTrue(badTargetCtx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-LINK-0001" })
    }

    func testFrontendAndSemaResolveTypedDeclarationsAndEmitExpectedDiagnostics() throws {
        let source = """
        package typed.demo
        import typed.demo.*

        public inline suspend fun transform<T>(
            vararg values: T,
            crossinline mapper: T,
            noinline fallback: T = mapper
        ): String? = "ok"
        fun String.decorate(): String = this

        fun typed(a: Int, b: String?, c: Any): Int = 1
        fun duplicate(x: Int, x: Int): Int = x

        val explicit: Int = 1
        var delegated by delegateProvider
        val unknown: CustomType = explicit
        val explicit: Int = 2

        class TypedBox<T>(value: T)
        object Obj
        typealias Alias = String
        enum class Kind { A, B }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "Typed", emit: .kirDump)
            try runToKIR(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let declarations = ast.arena.declarations()
            XCTAssertGreaterThanOrEqual(declarations.count, 8)

            var sawTypedParameter = false
            var sawFunctionReturnType = false
            var sawFunctionReceiverType = false
            var sawExplicitPropertyType = false
            var sawDelegatedPropertyWithoutType = false

            for decl in declarations {
                switch decl {
                case .funDecl(let fn):
                    if fn.returnType != nil {
                        sawFunctionReturnType = true
                    }
                    if fn.receiverType != nil {
                        sawFunctionReceiverType = true
                    }
                    if fn.valueParams.contains(where: { $0.type != nil }) {
                        sawTypedParameter = true
                    }
                case .propertyDecl(let property):
                    if let typeID = property.type, let typeRef = ast.arena.typeRef(typeID) {
                        sawExplicitPropertyType = true
                        if case .named(let path, _) = typeRef {
                            XCTAssertFalse(path.isEmpty)
                        }
                    } else if ctx.interner.resolve(property.name) == "delegated" {
                        sawDelegatedPropertyWithoutType = true
                    }
                default:
                    continue
                }
            }

            XCTAssertTrue(sawTypedParameter)
            XCTAssertTrue(sawFunctionReturnType)
            XCTAssertTrue(sawFunctionReceiverType)
            XCTAssertTrue(sawExplicitPropertyType)
            XCTAssertTrue(sawDelegatedPropertyWithoutType)

            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.symbols.allSymbols().isEmpty)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
            let decorateSymbol = sema.symbols.allSymbols().first(where: { symbol in
                ctx.interner.resolve(symbol.name) == "decorate"
            })
            XCTAssertNotNil(decorateSymbol)
            if let decorateSymbol {
                let signature = sema.symbols.functionSignature(for: decorateSymbol.id)
                XCTAssertNotNil(signature?.receiverType)
            }

            let codes = Set(ctx.diagnostics.diagnostics.map(\.code))
            XCTAssertTrue(codes.contains("KSWIFTK-TYPE-0002"))
            XCTAssertTrue(codes.contains("KSWIFTK-SEMA-0001"))
        }
    }

    func testTypeCheckAndBuildKIRCoverExpressionVariants() throws {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()

        let range = makeRange(file: FileID(rawValue: 0), start: 0, end: 1)
        let astArena = ASTArena()

        let intTypeRef = astArena.appendTypeRef(.named(path: [interner.intern("Int")], nullable: false))
        let boolTypeRef = astArena.appendTypeRef(.named(path: [interner.intern("Boolean")], nullable: false))
        let stringTypeRef = astArena.appendTypeRef(.named(path: [interner.intern("String")], nullable: false))

        let helperName = interner.intern("helper")
        let calcName = interner.intern("calc")
        let argName = interner.intern("arg")
        let unknownName = interner.intern("unknown")

        let eInt1 = astArena.appendExpr(.intLiteral(1, range))
        let eInt2 = astArena.appendExpr(.intLiteral(2, range))
        let eBoolTrue = astArena.appendExpr(.boolLiteral(true, range))
        let eBoolFalse = astArena.appendExpr(.boolLiteral(false, range))
        let eString = astArena.appendExpr(.stringLiteral(interner.intern("s"), range))
        let eNameLocal = astArena.appendExpr(.nameRef(argName, range))
        let eNameKnown = astArena.appendExpr(.nameRef(helperName, range))
        let eNameUnknown = astArena.appendExpr(.nameRef(unknownName, range))

        let eAdd = astArena.appendExpr(.binary(op: .add, lhs: eInt1, rhs: eInt2, range: range))
        let eSub = astArena.appendExpr(.binary(op: .subtract, lhs: eInt2, rhs: eInt1, range: range))
        let eMul = astArena.appendExpr(.binary(op: .multiply, lhs: eInt1, rhs: eInt2, range: range))
        let eDiv = astArena.appendExpr(.binary(op: .divide, lhs: eInt2, rhs: eInt1, range: range))
        let eEq = astArena.appendExpr(.binary(op: .equal, lhs: eInt1, rhs: eInt2, range: range))

        let eCallKnown = astArena.appendExpr(.call(callee: eNameKnown, args: [CallArgument(expr: eInt1)], range: range))
        let eCallUnknown = astArena.appendExpr(.call(callee: eNameUnknown, args: [CallArgument(expr: eInt1)], range: range))
        let eCallNonName = astArena.appendExpr(.call(callee: eInt1, args: [], range: range))

        let whenBranchTrue = WhenBranch(condition: eBoolTrue, body: eInt1, range: range)
        let whenBranchFalse = WhenBranch(condition: eBoolFalse, body: eInt2, range: range)
        let eWhenNoElse = astArena.appendExpr(.whenExpr(subject: eBoolTrue, branches: [whenBranchTrue], elseExpr: nil, range: range))
        let eWhenElse = astArena.appendExpr(.whenExpr(subject: eBoolTrue, branches: [whenBranchTrue, whenBranchFalse], elseExpr: eInt1, range: range))

        let helperDecl = astArena.appendDecl(.funDecl(FunDecl(
            range: range,
            name: helperName,
            modifiers: [],
            typeParams: [],
            receiverType: nil,
            valueParams: [ValueParamDecl(name: interner.intern("x"), type: intTypeRef)],
            returnType: intTypeRef,
            body: .expr(eInt1, range),
            isSuspend: false,
            isInline: false
        )))

        let calcDecl = astArena.appendDecl(.funDecl(FunDecl(
            range: range,
            name: calcName,
            modifiers: [.inline, .suspend],
            typeParams: [],
            receiverType: nil,
            valueParams: [ValueParamDecl(name: argName, type: intTypeRef)],
            returnType: intTypeRef,
            body: .block([
                eInt1, eBoolTrue, eString, eNameLocal, eNameKnown, eNameUnknown,
                eAdd, eSub, eMul, eDiv, eEq, eCallKnown, eCallUnknown, eCallNonName,
                eWhenNoElse, eWhenElse
            ], range),
            isSuspend: true,
            isInline: true
        )))

        let propertyDecl = astArena.appendDecl(.propertyDecl(PropertyDecl(
            range: range,
            name: interner.intern("text"),
            modifiers: [],
            type: stringTypeRef
        )))

        let boolProperty = astArena.appendDecl(.propertyDecl(PropertyDecl(
            range: range,
            name: interner.intern("flag"),
            modifiers: [],
            type: boolTypeRef
        )))

        let classDecl = astArena.appendDecl(.classDecl(ClassDecl(
            range: range,
            name: interner.intern("C"),
            modifiers: [],
            typeParams: [],
            primaryConstructorParams: []
        )))

        let astFile = ASTFile(
            fileID: FileID(rawValue: 0),
            packageFQName: [interner.intern("pkg")],
            imports: [],
            topLevelDecls: [helperDecl, calcDecl, propertyDecl, boolProperty, classDecl]
        )
        let module = ASTModule(files: [astFile], arena: astArena, declarationCount: 5, tokenCount: 0)

        let options = CompilerOptions(
            moduleName: "ExprCoverage",
            inputs: [],
            outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let ctx = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
        ctx.ast = module
        ctx.sema = SemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)

        try DataFlowSemaPassPhase().run(ctx)
        try TypeCheckSemaPassPhase().run(ctx)
        try BuildKIRPhase().run(ctx)
        try LoweringPhase().run(ctx)

        let kir = try XCTUnwrap(ctx.kir)
        XCTAssertGreaterThanOrEqual(kir.functionCount, 2)
        XCTAssertFalse(kir.executedLowerings.isEmpty)
        XCTAssertFalse((ctx.sema?.bindings.exprTypes ?? [:]).isEmpty)
    }

    private func makeComplexKIRModule(interner: StringInterner) -> KIRModule {
        let arena = KIRArena()

        let mainSym = SymbolID(rawValue: 1)
        let calleeSym = SymbolID(rawValue: 2)

        let e0 = arena.appendExpr(.intLiteral(10))
        let e1 = arena.appendExpr(.intLiteral(3))
        let e2 = arena.appendExpr(.boolLiteral(true))
        let e3 = arena.appendExpr(.stringLiteral(interner.intern("hello\\n\"world\"")))
        let e4 = arena.appendExpr(.symbolRef(calleeSym))
        let e5 = arena.appendExpr(.temporary(5))
        let e6 = arena.appendExpr(.temporary(6))
        let e7 = arena.appendExpr(.temporary(7))
        let e8 = arena.appendExpr(.temporary(8))
        let e9 = arena.appendExpr(.unit)

        let callee = KIRFunction(
            symbol: calleeSym,
            name: interner.intern("callee"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )

        let main = KIRFunction(
            symbol: mainSym,
            name: interner.intern("1-main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .nop,
                .beginBlock,
                .constValue(result: e0, value: .intLiteral(10)),
                .constValue(result: e1, value: .intLiteral(3)),
                .constValue(result: e2, value: .boolLiteral(true)),
                .constValue(result: e3, value: .stringLiteral(interner.intern("hello\\n\"world\""))),
                .constValue(result: e4, value: .symbolRef(calleeSym)),
                .constValue(result: e5, value: .temporary(99)),
                .constValue(result: e9, value: .unit),
                .binary(op: .add, lhs: e0, rhs: e1, result: e5),
                .binary(op: .subtract, lhs: e0, rhs: e1, result: e6),
                .binary(op: .multiply, lhs: e0, rhs: e1, result: e7),
                .binary(op: .divide, lhs: e0, rhs: e1, result: e8),
                .binary(op: .equal, lhs: e0, rhs: e1, result: e5),
                .call(symbol: nil, callee: interner.intern("println"), arguments: [e3], result: e5, outThrown: false),
                .call(symbol: nil, callee: interner.intern("kk_println_any"), arguments: [e3], result: nil, outThrown: false),
                .call(symbol: nil, callee: interner.intern("kk_op_add"), arguments: [e0, e1], result: e5, outThrown: false),
                .call(symbol: nil, callee: interner.intern("kk_op_sub"), arguments: [e0, e1], result: e6, outThrown: false),
                .call(symbol: nil, callee: interner.intern("kk_op_mul"), arguments: [e0, e1], result: e7, outThrown: false),
                .call(symbol: nil, callee: interner.intern("kk_op_div"), arguments: [e0, e1], result: e8, outThrown: false),
                .call(symbol: nil, callee: interner.intern("kk_op_eq"), arguments: [e0, e1], result: e5, outThrown: false),
                .call(symbol: nil, callee: interner.intern("kk_when_select"), arguments: [e2, e0, e1], result: e5, outThrown: false),
                .call(symbol: calleeSym, callee: interner.intern("ignored"), arguments: [], result: e5, outThrown: false),
                .returnValue(e5),
                .endBlock
            ],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(main))
        _ = arena.appendDecl(.global(KIRGlobal(symbol: mainSym, type: TypeSystem().anyType)))
        _ = arena.appendDecl(.nominalType(KIRNominalType(symbol: mainSym)))
        _ = arena.appendDecl(.function(callee))

        return KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])], arena: arena)
    }
}
