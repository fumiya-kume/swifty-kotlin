import Foundation
import XCTest
@testable import CompilerCore

final class SemanticsAndUtilitiesCoverageTests: XCTestCase {
    func testNameManglerEncodesAllKindsAndProducesStableHashSuffix() {
        let interner = StringInterner()
        let mangler = NameMangler()
        let kinds: [SymbolKind] = [
            .function,
            .class,
            .property,
            .constructor,
            .object,
            .typeAlias,
            .interface,
            .enumClass,
            .annotationClass,
            .package,
            .field,
            .typeParameter,
            .valueParameter,
            .local,
            .label
        ]

        var mangledByKind: [String: String] = [:]
        for (index, kind) in kinds.enumerated() {
            let name = interner.intern("sym_\(index)")
            let fq = [interner.intern("pkg"), interner.intern("name\(index)")]
            let symbol = SemanticSymbol(
                id: SymbolID(rawValue: Int32(index)),
                kind: kind,
                name: name,
                fqName: fq,
                declSite: nil,
                visibility: .public,
                flags: []
            )
            let mangled = mangler.mangle(moduleName: "ModuleX", symbol: symbol, signature: "sig\(index)")
            mangledByKind[String(describing: kind)] = mangled
            XCTAssertTrue(mangled.hasPrefix("_KK_ModuleX__"))
            XCTAssertTrue(mangled.contains("__sig\(index)__"))

            let suffix = String(mangled.suffix(8))
            XCTAssertEqual(suffix.count, 8)
            XCTAssertTrue(suffix.allSatisfy { $0.isHexDigit })
        }

        XCTAssertEqual(mangledByKind.count, kinds.count)
        XCTAssertEqual(mangledByKind[String(describing: SymbolKind.function)], mangler.mangle(
            moduleName: "ModuleX",
            symbol: SemanticSymbol(
                id: SymbolID(rawValue: 0),
                kind: .function,
                name: interner.intern("sym_0"),
                fqName: [interner.intern("pkg"), interner.intern("name0")],
                declSite: nil,
                visibility: .public,
                flags: []
            ),
            signature: "sig0"
        ))
    }

    func testNameManglerBuildsErasedSignatureWithNullableAndSuspendFunctionTypes() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let mangler = NameMangler()

        let intType = types.make(.primitive(.int, .nonNull))
        let nullableIntType = types.make(.primitive(.int, .nullable))
        let suspendLambdaType = types.make(.functionType(
            FunctionType(
                params: [intType],
                returnType: nullableIntType,
                isSuspend: true
            )
        ))
        let functionSymbolID = symbols.define(
            kind: .function,
            name: interner.intern("consume"),
            fqName: [interner.intern("pkg"), interner.intern("consume")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [nullableIntType, suspendLambdaType],
                returnType: intType,
                isSuspend: false
            ),
            for: functionSymbolID
        )
        let functionSymbol = try XCTUnwrap(symbols.symbol(functionSymbolID), "missing function symbol")

        let encoded = mangler.mangledSignature(for: functionSymbol, symbols: symbols, types: types)
        XCTAssertTrue(encoded.contains("Q<I>"))
        XCTAssertTrue(encoded.contains("SF1<"))
        XCTAssertTrue(encoded.hasPrefix("F2<"))
    }

    func testNameManglerSupportsDeclKindOverridesForAccessorKinds() {
        let interner = StringInterner()
        let mangler = NameMangler()

        let functionSymbol = SemanticSymbol(
            id: SymbolID(rawValue: 10),
            kind: .function,
            name: interner.intern("value"),
            fqName: [interner.intern("pkg"), interner.intern("value")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let constructorSymbol = SemanticSymbol(
            id: SymbolID(rawValue: 11),
            kind: .constructor,
            name: interner.intern("Ctor"),
            fqName: [interner.intern("pkg"), interner.intern("Ctor")],
            declSite: nil,
            visibility: .public,
            flags: []
        )

        let getter = mangler.mangle(
            moduleName: "ModuleX",
            symbol: functionSymbol,
            signature: "_",
            declKind: .getter
        )
        let setter = mangler.mangle(
            moduleName: "ModuleX",
            symbol: functionSymbol,
            signature: "_",
            declKind: .setter
        )
        let constructor = mangler.mangle(moduleName: "ModuleX", symbol: constructorSymbol, signature: "_")

        XCTAssertTrue(getter.contains("__G__"))
        XCTAssertTrue(setter.contains("__S__"))
        XCTAssertTrue(constructor.contains("__K__"))
    }

    func testDataFlowMergeAndWhenExhaustivenessAcrossKinds() {
        let analyzer = DataFlowAnalyzer()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )

        let sym = SymbolID(rawValue: 1)
        let lhs = DataFlowState(variables: [
            sym: VariableFlowState(
                possibleTypes: [types.anyType],
                nullability: .nonNull,
                isStable: true
            )
        ])
        let rhsType = types.make(.primitive(.int, .nullable))
        let rhs = DataFlowState(variables: [
            sym: VariableFlowState(
                possibleTypes: [rhsType],
                nullability: .nullable,
                isStable: false
            ),
            SymbolID(rawValue: 2): VariableFlowState(
                possibleTypes: [types.unitType],
                nullability: .nonNull,
                isStable: true
            )
        ])

        let merged = analyzer.merge(lhs, rhs)
        XCTAssertEqual(merged.variables.count, 1)
        XCTAssertTrue(merged.variables[sym]?.possibleTypes.contains(types.anyType) == true)
        XCTAssertTrue(merged.variables[sym]?.possibleTypes.contains(rhsType) == true)
        XCTAssertEqual(merged.variables[sym]?.nullability, .nullable)
        XCTAssertEqual(merged.variables[sym]?.isStable, false)

        let boolType = types.make(.primitive(.boolean, .nonNull))
        XCTAssertTrue(analyzer.isWhenExhaustive(
            subjectType: boolType,
            branches: WhenBranchSummary(coveredSymbols: [InternedString(rawValue: 1), InternedString(rawValue: 2)], hasElse: false),
            sema: sema
        ))
        XCTAssertFalse(analyzer.isWhenExhaustive(
            subjectType: boolType,
            branches: WhenBranchSummary(coveredSymbols: [InternedString(rawValue: 1)], hasElse: false),
            sema: sema
        ))
        XCTAssertTrue(analyzer.isWhenExhaustive(
            subjectType: boolType,
            branches: WhenBranchSummary(coveredSymbols: [], hasElse: true),
            sema: sema
        ))

        let classType = types.make(.classType(ClassType(classSymbol: SymbolID(rawValue: 9))))
        XCTAssertFalse(analyzer.isWhenExhaustive(
            subjectType: classType,
            branches: WhenBranchSummary(coveredSymbols: [], hasElse: false),
            sema: sema
        ))

        let enumSymbol = symbols.define(
            kind: .enumClass,
            name: interner.intern("Color"),
            fqName: [interner.intern("Color")],
            declSite: nil,
            visibility: .public
        )
        let red = interner.intern("Red")
        let green = interner.intern("Green")
        _ = symbols.define(
            kind: .field,
            name: red,
            fqName: [interner.intern("Color"), red],
            declSite: nil,
            visibility: .public
        )
        _ = symbols.define(
            kind: .field,
            name: green,
            fqName: [interner.intern("Color"), green],
            declSite: nil,
            visibility: .public
        )
        let enumType = types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertTrue(analyzer.isWhenExhaustive(
            subjectType: enumType,
            branches: WhenBranchSummary(coveredSymbols: [red, green], hasElse: false),
            sema: sema
        ))
        XCTAssertFalse(analyzer.isWhenExhaustive(
            subjectType: enumType,
            branches: WhenBranchSummary(coveredSymbols: [red], hasElse: false),
            sema: sema
        ))

        let nullableEnumType = types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nullable
        )))
        XCTAssertFalse(analyzer.isWhenExhaustive(
            subjectType: nullableEnumType,
            branches: WhenBranchSummary(coveredSymbols: [red, green], hasElse: false, hasNullCase: false),
            sema: sema
        ))
        XCTAssertTrue(analyzer.isWhenExhaustive(
            subjectType: nullableEnumType,
            branches: WhenBranchSummary(coveredSymbols: [red, green], hasElse: false, hasNullCase: true),
            sema: sema
        ))

        let sealedBase = symbols.define(
            kind: .class,
            name: interner.intern("Expr"),
            fqName: [interner.intern("Expr")],
            declSite: nil,
            visibility: .public,
            flags: [.sealedType]
        )
        let sealedA = symbols.define(
            kind: .object,
            name: interner.intern("A"),
            fqName: [interner.intern("A")],
            declSite: nil,
            visibility: .public
        )
        let sealedB = symbols.define(
            kind: .object,
            name: interner.intern("B"),
            fqName: [interner.intern("B")],
            declSite: nil,
            visibility: .public
        )
        symbols.setDirectSupertypes([sealedBase], for: sealedA)
        symbols.setDirectSupertypes([sealedBase], for: sealedB)
        let sealedType = types.make(.classType(ClassType(
            classSymbol: sealedBase,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertTrue(analyzer.isWhenExhaustive(
            subjectType: sealedType,
            branches: WhenBranchSummary(
                coveredSymbols: [interner.intern("A"), interner.intern("B")],
                hasElse: false
            ),
            sema: sema
        ))
        XCTAssertFalse(analyzer.isWhenExhaustive(
            subjectType: sealedType,
            branches: WhenBranchSummary(
                coveredSymbols: [interner.intern("A")],
                hasElse: false
            ),
            sema: sema
        ))

        XCTAssertFalse(analyzer.isWhenExhaustive(
            subjectType: types.nullableAnyType,
            branches: WhenBranchSummary(coveredSymbols: [], hasElse: false),
            sema: sema
        ))

        let intType = types.make(.primitive(.int, .nonNull))
        XCTAssertFalse(analyzer.isWhenExhaustive(
            subjectType: intType,
            branches: WhenBranchSummary(coveredSymbols: [], hasElse: false),
            sema: sema
        ))

        let nullableBool = types.make(.primitive(.boolean, .nullable))
        XCTAssertFalse(analyzer.isWhenExhaustive(
            subjectType: nullableBool,
            branches: WhenBranchSummary(
                coveredSymbols: [InternedString(rawValue: 1), InternedString(rawValue: 2)],
                hasElse: false,
                hasNullCase: false
            ),
            sema: sema
        ))
        XCTAssertTrue(analyzer.isWhenExhaustive(
            subjectType: nullableBool,
            branches: WhenBranchSummary(
                coveredSymbols: [InternedString(rawValue: 1), InternedString(rawValue: 2)],
                hasElse: false,
                hasNullCase: true
            ),
            sema: sema
        ))
    }

    func testTypeSystemSubtypeLUBAndGLBCoversVarianceAndIntersections() {
        let types = TypeSystem()

        let intNN = types.make(.primitive(.int, .nonNull))
        let intNullable = types.make(.primitive(.int, .nullable))
        let boolNN = types.make(.primitive(.boolean, .nonNull))

        XCTAssertTrue(types.isSubtype(intNN, intNN))
        XCTAssertTrue(types.isSubtype(types.nothingType, intNN))
        XCTAssertTrue(types.isSubtype(types.errorType, intNN))
        XCTAssertTrue(types.isSubtype(intNN, types.errorType))
        XCTAssertTrue(types.isSubtype(intNullable, types.nullableAnyType))
        XCTAssertTrue(types.isSubtype(intNN, types.anyType))
        XCTAssertFalse(types.isSubtype(intNullable, types.anyType))
        XCTAssertTrue(types.isSubtype(intNN, intNullable))
        XCTAssertFalse(types.isSubtype(intNullable, intNN))

        let classSym = SymbolID(rawValue: 100)
        let classAOutInt = types.make(.classType(ClassType(
            classSymbol: classSym,
            args: [.out(intNN)],
            nullability: .nonNull
        )))
        let classAOutAny = types.make(.classType(ClassType(
            classSymbol: classSym,
            args: [.out(types.anyType)],
            nullability: .nonNull
        )))
        XCTAssertTrue(types.isSubtype(classAOutInt, classAOutAny))

        let classAInInt = types.make(.classType(ClassType(
            classSymbol: classSym,
            args: [.in(intNN)],
            nullability: .nonNull
        )))
        let classAInAny = types.make(.classType(ClassType(
            classSymbol: classSym,
            args: [.in(types.anyType)],
            nullability: .nonNull
        )))
        XCTAssertTrue(types.isSubtype(classAInAny, classAInInt))
        XCTAssertFalse(types.isSubtype(classAInInt, classAInAny))

        let classInvariantInt = types.make(.classType(ClassType(
            classSymbol: classSym,
            args: [.invariant(intNN)],
            nullability: .nonNull
        )))
        let classInvariantBool = types.make(.classType(ClassType(
            classSymbol: classSym,
            args: [.invariant(boolNN)],
            nullability: .nonNull
        )))
        XCTAssertFalse(types.isSubtype(classInvariantInt, classInvariantBool))

        let classOtherSymbol = types.make(.classType(ClassType(
            classSymbol: SymbolID(rawValue: 101),
            args: [.star],
            nullability: .nonNull
        )))
        XCTAssertFalse(types.isSubtype(classInvariantInt, classOtherSymbol))

        let baseNominal = SymbolID(rawValue: 200)
        let midNominal = SymbolID(rawValue: 201)
        let leafNominal = SymbolID(rawValue: 202)
        types.setNominalDirectSupertypes([baseNominal], for: midNominal)
        types.setNominalDirectSupertypes([midNominal], for: leafNominal)

        let baseType = types.make(.classType(ClassType(
            classSymbol: baseNominal,
            args: [],
            nullability: .nonNull
        )))
        let leafType = types.make(.classType(ClassType(
            classSymbol: leafNominal,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertTrue(types.isSubtype(leafType, baseType))
        XCTAssertFalse(types.isSubtype(baseType, leafType))

        let covariantSymbol = SymbolID(rawValue: 210)
        types.setNominalTypeParameterVariances([.out], for: covariantSymbol)
        let covariantInvariantInt = types.make(.classType(ClassType(
            classSymbol: covariantSymbol,
            args: [.invariant(intNN)],
            nullability: .nonNull
        )))
        let covariantInvariantAny = types.make(.classType(ClassType(
            classSymbol: covariantSymbol,
            args: [.invariant(types.anyType)],
            nullability: .nonNull
        )))
        XCTAssertTrue(types.isSubtype(covariantInvariantInt, covariantInvariantAny))
        let covariantInProjection = types.make(.classType(ClassType(
            classSymbol: covariantSymbol,
            args: [.in(intNN)],
            nullability: .nonNull
        )))
        XCTAssertFalse(types.isSubtype(covariantInProjection, covariantInvariantAny))

        let contravariantSymbol = SymbolID(rawValue: 211)
        types.setNominalTypeParameterVariances([.in], for: contravariantSymbol)
        let contravariantInvariantInt = types.make(.classType(ClassType(
            classSymbol: contravariantSymbol,
            args: [.invariant(intNN)],
            nullability: .nonNull
        )))
        let contravariantInvariantAny = types.make(.classType(ClassType(
            classSymbol: contravariantSymbol,
            args: [.invariant(types.anyType)],
            nullability: .nonNull
        )))
        XCTAssertTrue(types.isSubtype(contravariantInvariantAny, contravariantInvariantInt))
        let contravariantOutProjection = types.make(.classType(ClassType(
            classSymbol: contravariantSymbol,
            args: [.out(intNN)],
            nullability: .nonNull
        )))
        XCTAssertFalse(types.isSubtype(contravariantOutProjection, contravariantInvariantInt))

        let classStarLHS = types.make(.classType(ClassType(
            classSymbol: classSym,
            args: [.star],
            nullability: .nonNull
        )))
        let classStarRHS = types.make(.classType(ClassType(
            classSymbol: classSym,
            args: [.star],
            nullability: .nonNull
        )))
        XCTAssertTrue(types.isSubtype(classStarLHS, classStarRHS))

        let fnA = types.make(.functionType(FunctionType(
            receiver: intNN,
            params: [types.anyType],
            returnType: intNN,
            isSuspend: false,
            nullability: .nonNull
        )))
        let fnB = types.make(.functionType(FunctionType(
            receiver: intNN,
            params: [intNN],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        XCTAssertTrue(types.isSubtype(fnA, fnB))

        let fnSuspend = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [intNN],
            returnType: intNN,
            isSuspend: true,
            nullability: .nonNull
        )))
        XCTAssertFalse(types.isSubtype(fnA, fnSuspend))

        let typeParamNN = types.make(.typeParam(TypeParamType(symbol: SymbolID(rawValue: 5), nullability: .nonNull)))
        let typeParamNullable = types.make(.typeParam(TypeParamType(symbol: SymbolID(rawValue: 5), nullability: .nullable)))
        XCTAssertTrue(types.isSubtype(typeParamNN, types.anyType))
        XCTAssertFalse(types.isSubtype(typeParamNullable, types.anyType))

        let lhsIntersection = types.make(.intersection([intNN, boolNN]))
        XCTAssertFalse(types.isSubtype(lhsIntersection, intNN))
        XCTAssertTrue(types.isSubtype(intNN, types.make(.intersection([intNN, boolNN]))))

        XCTAssertEqual(types.lub([]), types.errorType)
        XCTAssertEqual(types.lub([intNN, intNN]), intNN)
        XCTAssertEqual(types.lub([intNN, intNullable]), types.nullableAnyType)

        XCTAssertEqual(types.glb([]), types.errorType)
        XCTAssertEqual(types.glb([intNN, intNN]), intNN)
        XCTAssertEqual(types.glb([intNN, types.nothingType]), types.nothingType)

        let glbMixed = types.glb([intNN, boolNN])
        XCTAssertEqual(types.kind(of: glbMixed), .intersection([intNN, boolNN]))

        XCTAssertEqual(types.kind(of: TypeID(rawValue: 9999)), .error)
    }

    func testTypeSystemAnyNonNullSubtypeCoversClassFunctionIntersectionAndDefaultCases() {
        let types = TypeSystem()

        let intNN = types.make(.primitive(.int, .nonNull))
        let intNullable = types.make(.primitive(.int, .nullable))

        let classNN = types.make(.classType(ClassType(
            classSymbol: SymbolID(rawValue: 400),
            args: [],
            nullability: .nonNull
        )))
        let classNullable = types.make(.classType(ClassType(
            classSymbol: SymbolID(rawValue: 400),
            args: [],
            nullability: .nullable
        )))

        let fnNN = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [intNN],
            returnType: intNN,
            isSuspend: false,
            nullability: .nonNull
        )))
        let fnNullable = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [intNN],
            returnType: intNN,
            isSuspend: false,
            nullability: .nullable
        )))

        let intersectionAllNonNull = types.make(.intersection([intNN, classNN]))
        let intersectionWithNullable = types.make(.intersection([intNN, intNullable]))

        XCTAssertTrue(types.isSubtype(classNN, types.anyType))
        XCTAssertFalse(types.isSubtype(classNullable, types.anyType))
        XCTAssertTrue(types.isSubtype(fnNN, types.anyType))
        XCTAssertFalse(types.isSubtype(fnNullable, types.anyType))
        XCTAssertTrue(types.isSubtype(intersectionAllNonNull, types.anyType))
        XCTAssertFalse(types.isSubtype(intersectionWithNullable, types.anyType))
        XCTAssertFalse(types.isSubtype(types.nullableAnyType, types.anyType))

        let fnWithReceiver = types.make(.functionType(FunctionType(
            receiver: intNN,
            params: [intNN],
            returnType: intNN,
            isSuspend: false,
            nullability: .nonNull
        )))
        let fnWithoutReceiver = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [intNN],
            returnType: intNN,
            isSuspend: false,
            nullability: .nonNull
        )))
        XCTAssertFalse(types.isSubtype(fnWithReceiver, fnWithoutReceiver))
    }

    func testDiagnosticsRenderSortOrderAndPrintingPaths() {
        let manager = SourceManager()
        let fileB = manager.addFile(path: "b.kt", contents: Data("line1\nline2\n".utf8))
        let fileA = manager.addFile(path: "a.kt", contents: Data("x\ny\n".utf8))

        let engine = DiagnosticEngine()
        engine.warning("W002", "later file", range: makeRange(file: fileB, start: 0, end: 1))
        engine.error("E001", "first file", range: makeRange(file: fileA, start: 0, end: 1))
        engine.note("N010", "same place as error", range: makeRange(file: fileA, start: 0, end: 1))
        engine.info("I999", "no range", range: nil)

        XCTAssertTrue(engine.hasError)
        let rendered = engine.render(manager)
        let lines = rendered.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines[0].contains("a.kt:1:1: error E001"))
        XCTAssertTrue(lines[1].contains("a.kt:1:1: note N010"))
        XCTAssertTrue(lines[2].contains("b.kt:1:1: warning W002"))
        XCTAssertTrue(lines[3].contains("info I999: no range"))

        engine.printDiagnostics(to: false, from: manager)

        let empty = DiagnosticEngine()
        empty.printDiagnostics(to: false, from: manager)
    }

    func testSemanticsBindingTableAndSymbolTableScopes() {
        let interner = StringInterner()
        let symbols = SymbolTable()

        let pkg = symbols.define(
            kind: .package,
            name: interner.intern("pkg"),
            fqName: [interner.intern("pkg")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        let fn = symbols.define(
            kind: .function,
            name: interner.intern("run"),
            fqName: [interner.intern("pkg"), interner.intern("run")],
            declSite: nil,
            visibility: .public,
            flags: [.inlineFunction, .suspendFunction]
        )

        XCTAssertEqual(symbols.count, 2)
        XCTAssertNotNil(symbols.symbol(pkg))
        XCTAssertNotNil(symbols.lookup(fqName: [interner.intern("pkg")]))

        let signature = FunctionSignature(parameterTypes: [TypeSystem().anyType], returnType: TypeSystem().unitType)
        symbols.setFunctionSignature(signature, for: fn)
        XCTAssertEqual(symbols.functionSignature(for: fn)?.parameterTypes.count, 1)

        let root = PackageScope(parent: nil, symbols: symbols)
        let fileScope = FileScope(parent: root, symbols: symbols)
        fileScope.insert(fn)
        XCTAssertEqual(fileScope.lookup(interner.intern("run")), [fn])
        XCTAssertTrue(root.lookup(interner.intern("run")).isEmpty)

        let bindings = BindingTable()
        let expr = ExprID(rawValue: 1)
        let decl = DeclID(rawValue: 2)
        bindings.bindExprType(expr, type: TypeSystem().anyType)
        bindings.bindIdentifier(expr, symbol: fn)
        bindings.bindCall(expr, binding: CallBinding(chosenCallee: fn, substitutedTypeArguments: [], parameterMapping: [0: 0]))
        bindings.bindDecl(decl, symbol: fn)

        XCTAssertEqual(bindings.identifierSymbols[expr], fn)
        XCTAssertEqual(bindings.callBindings[expr]?.chosenCallee, fn)
        XCTAssertEqual(bindings.declSymbols[decl], fn)
    }

    func testInsertWithAliasRegistersSymbolUnderAliasName() {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let fn = symbols.define(
            kind: .function,
            name: interner.intern("originalName"),
            fqName: [interner.intern("pkg"), interner.intern("originalName")],
            declSite: nil,
            visibility: .public
        )

        let scope = ImportScope(parent: nil, symbols: symbols)
        let aliasName = interner.intern("AliasName")
        scope.insertWithAlias(fn, asName: aliasName)

        XCTAssertEqual(scope.lookup(aliasName), [fn])
        XCTAssertTrue(scope.lookup(interner.intern("originalName")).isEmpty)
    }

    func testImportAliasDeclStoresAliasField() {
        let interner = StringInterner()
        let range = makeRange(start: 0, end: 10)

        let noAlias = ImportDecl(range: range, path: [interner.intern("a"), interner.intern("B")], alias: nil)
        XCTAssertNil(noAlias.alias)

        let withAlias = ImportDecl(range: range, path: [interner.intern("a"), interner.intern("B")], alias: interner.intern("X"))
        XCTAssertEqual(withAlias.alias, interner.intern("X"))
    }

    func testConditionBranchStructCreation() {
        let analyzer = DataFlowAnalyzer()
        let sym = SymbolID(rawValue: 100)
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))

        let trueState = DataFlowState(variables: [
            sym: VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: true)
        ])
        let falseState = DataFlowState(variables: [
            sym: VariableFlowState(possibleTypes: [stringType], nullability: .nonNull, isStable: true)
        ])
        let branch = ConditionBranch(trueState: trueState, falseState: falseState)

        XCTAssertEqual(branch.trueState.variables[sym]?.possibleTypes, [intType])
        XCTAssertEqual(branch.falseState.variables[sym]?.possibleTypes, [stringType])

        let merged = analyzer.merge(branch.trueState, branch.falseState)
        XCTAssertEqual(merged.variables[sym]?.possibleTypes.count, 2)
        XCTAssertTrue(merged.variables[sym]?.possibleTypes.contains(intType) == true)
        XCTAssertTrue(merged.variables[sym]?.possibleTypes.contains(stringType) == true)
    }

    func testResolvedTypeFromFlowStateReturnsSingleType() {
        let analyzer = DataFlowAnalyzer()
        let types = TypeSystem()
        let sym = SymbolID(rawValue: 200)
        let intType = types.make(.primitive(.int, .nonNull))

        let state = DataFlowState(variables: [
            sym: VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: true)
        ])
        XCTAssertEqual(analyzer.resolvedTypeFromFlowState(state, symbol: sym), intType)

        let multiState = DataFlowState(variables: [
            sym: VariableFlowState(possibleTypes: [intType, types.anyType], nullability: .nonNull, isStable: true)
        ])
        XCTAssertNil(analyzer.resolvedTypeFromFlowState(multiState, symbol: sym))

        XCTAssertNil(analyzer.resolvedTypeFromFlowState(DataFlowState(), symbol: sym))
    }

    func testWhenElseStateNarrowsNullability() {
        let analyzer = DataFlowAnalyzer()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let sema = SemaModule(
            symbols: symbols, types: types,
            bindings: BindingTable(), diagnostics: DiagnosticEngine()
        )
        let sym = SymbolID(rawValue: 300)
        let nullableInt = types.make(.primitive(.int, .nullable))

        let elseState = analyzer.whenElseState(
            subjectSymbol: sym, subjectType: nullableInt,
            hasExplicitNullBranch: true, base: DataFlowState(), sema: sema
        )
        XCTAssertEqual(elseState.variables[sym]?.nullability, .nonNull)
        XCTAssertEqual(elseState.variables[sym]?.isStable, true)

        let noNullBranch = analyzer.whenElseState(
            subjectSymbol: sym, subjectType: nullableInt,
            hasExplicitNullBranch: false, base: DataFlowState(), sema: sema
        )
        XCTAssertNil(noNullBranch.variables[sym])
    }

    func testWhenNonNullBranchStateNarrowsToNonNull() {
        let analyzer = DataFlowAnalyzer()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let sema = SemaModule(
            symbols: symbols, types: types,
            bindings: BindingTable(), diagnostics: DiagnosticEngine()
        )
        let sym = SymbolID(rawValue: 400)
        let nullableString = types.make(.primitive(.string, .nullable))

        let result = analyzer.whenNonNullBranchState(
            subjectSymbol: sym, subjectType: nullableString,
            base: DataFlowState(), sema: sema
        )
        XCTAssertEqual(result.variables[sym]?.nullability, .nonNull)
        XCTAssertEqual(result.variables[sym]?.isStable, true)
        XCTAssertEqual(result.variables[sym]?.possibleTypes.count, 1)
    }

    func testMergeCFGJoinPointPreservesWidestTypeAndNullability() {
        let analyzer = DataFlowAnalyzer()
        let types = TypeSystem()
        let sym = SymbolID(rawValue: 500)
        let intType = types.make(.primitive(.int, .nonNull))
        let nullableInt = types.make(.primitive(.int, .nullable))

        let lhs = DataFlowState(variables: [
            sym: VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: true)
        ])
        let rhs = DataFlowState(variables: [
            sym: VariableFlowState(possibleTypes: [nullableInt], nullability: .nullable, isStable: true)
        ])
        let merged = analyzer.merge(lhs, rhs)

        XCTAssertEqual(merged.variables[sym]?.nullability, .nullable)
        XCTAssertEqual(merged.variables[sym]?.possibleTypes.count, 2)
        XCTAssertTrue(merged.variables[sym]?.isStable == true)

        let unstable = DataFlowState(variables: [
            sym: VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: false)
        ])
        let mergedUnstable = analyzer.merge(lhs, unstable)
        XCTAssertEqual(mergedUnstable.variables[sym]?.isStable, false)

        let symA = SymbolID(rawValue: 600)
        let symB = SymbolID(rawValue: 601)
        let onlyLeft = DataFlowState(variables: [
            symA: VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: true)
        ])
        let onlyRight = DataFlowState(variables: [
            symB: VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: true)
        ])
        let disjoint = analyzer.merge(onlyLeft, onlyRight)
        XCTAssertTrue(disjoint.variables.isEmpty)
    }

    func testSymbolTableSupportsOverloadedFunctionsWithSameFQName(){
        let interner = StringInterner()
        let symbols = SymbolTable()
        let fqName = [interner.intern("pkg"), interner.intern("run")]

        let first = symbols.define(
            kind: .function,
            name: interner.intern("run"),
            fqName: fqName,
            declSite: nil,
            visibility: .public
        )
        let second = symbols.define(
            kind: .function,
            name: interner.intern("run"),
            fqName: fqName,
            declSite: nil,
            visibility: .public
        )

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(symbols.lookupAll(fqName: fqName), [first, second])
        XCTAssertEqual(symbols.lookup(fqName: fqName), first)
    }
}

final class CommandRunnerCoverageTests: XCTestCase {
    func testRunReturnsStdoutOnSuccess() throws {
        let result = try CommandRunner.run(
            executable: "/usr/bin/env",
            arguments: ["sh", "-c", "printf 'ok'"]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "ok")
    }

    func testRunThrowsNonZeroExitWithCapturedStderr() {
        XCTAssertThrowsError(
            try CommandRunner.run(
                executable: "/usr/bin/env",
                arguments: ["sh", "-c", "printf 'err' >&2; exit 7"]
            )
        ) { error in
            guard case CommandRunnerError.nonZeroExit(let result) = error else {
                XCTFail("Expected nonZeroExit, got \(error)")
                return
            }
            XCTAssertEqual(result.exitCode, 7)
            XCTAssertEqual(result.stderr, "err")
        }
    }

    func testRunThrowsLaunchFailedForMissingExecutable() {
        XCTAssertThrowsError(
            try CommandRunner.run(
                executable: "/definitely/missing/executable",
                arguments: []
            )
        ) { error in
            guard case CommandRunnerError.launchFailed(let message) = error else {
                XCTFail("Expected launchFailed, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("Failed to launch"))
        }
    }
}
