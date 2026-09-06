#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ArraySyntheticMemberLinkTests {
    private func firstExprID(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID) else { continue }
            guard let range = ast.arena.exprRange(exprID), ctx.sourceManager.path(of: range.start.file) == path else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    @Test
    func testArrayMemberCallFallbacksResolve() throws {
        let sources: [String] = [
            """
            fun sample0(): Boolean {
                val values = arrayOf(1, 2, 3)
                return values.all { it > 0 }
            }
            """,
            """
            fun sample1() {
                val values = arrayOf(1, 2, 3)
                val result = values.mapIndexed { index, value -> index + value }
                println(result)
            }
            """,
            """
            fun sample2() {
                val values: Array<Int?> = arrayOf(1, null, 2)
                val result = values.filterNotNull()
                println(result)
            }
            """,
            """
            fun sample3(): Int? {
                val values = arrayOf(1, 2, 3)
                return values.firstOrNull()
            }
            """,
            """
            fun sample4(): Int {
                val values = arrayOf(1, 2, 3)
                return values.first()
            }
            """,
            """
            fun sample5(): Int {
                val values = arrayOf(1, 2, 3)
                return values.reduceIndexed { index, acc, value -> acc + value + index }
            }
            """,
        ]

        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        let userPaths = ctx.sourceManager.fileIDs()
            .filter { ctx.sourceManager.origin(of: $0) == .user }
            .map { ctx.sourceManager.path(of: $0) }
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        func sourceArrayExtension(named name: String, receiverName: String) -> SymbolID? {
            sema.symbols.lookupAll(
                fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("collections"),
                    ctx.interner.intern(name),
                ]
            ).first { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      symbol.declSite != nil,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let receiverType = sema.symbols.functionSignature(for: candidate)?.receiverType,
                      case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                      let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
                else {
                    return false
                }
                return ctx.interner.resolve(receiverSymbol.name) == receiverName
            }
        }


            // === testArrayOfNullsTopLevelFactoryUsesRuntimeExternalLink ===
            do {
                let symbolID = try #require(
                    sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("arrayOfNulls"),
                        ]
                    ),
                    "Expected synthetic arrayOfNulls function to be registered"
                )
                #expect(sema.symbols.externalLinkName(for: symbolID) == "kk_array_of_nulls")
                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                #expect(signature.parameterTypes == [sema.types.intType])
                #expect(signature.valueParameterHasDefaultValues == [false])
                #expect(signature.valueParameterIsVararg == [false])
                #expect(signature.typeParameterSymbols.count == 1)
                guard case let .classType(returnClass) = sema.types.kind(of: signature.returnType),
                      let arraySymbol = sema.symbols.symbol(returnClass.classSymbol)
                else {
                    Issue.record("Expected arrayOfNulls to return Array<T?>")
                    return
                }
                #expect(ctx.interner.resolve(arraySymbol.name) == "Array")
                #expect(returnClass.args.count == 1)
                guard case let .invariant(elementType) = returnClass.args[0],
                      case let .typeParam(typeParam) = sema.types.kind(of: elementType)
                else {
                    Issue.record("Expected arrayOfNulls element type to be nullable type parameter")
                    return
                }
                #expect(typeParam.symbol == signature.typeParameterSymbols[0])
                #expect(typeParam.nullability == .nullable)
            }

            // === testArrayReversedArrayIsBundledSourceBacked ===
            do {
                #expect(
                    sema.symbols.lookupAll(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("Array"),
                            ctx.interner.intern("reversedArray"),
                        ]
                    ).isEmpty,
                    "Generic Array.reversedArray synthetic stub should be removed"
                )
                let symbolID = try #require(
                    sourceArrayExtension(named: "reversedArray", receiverName: "Array"),
                    "Expected bundled source Array.reversedArray extension"
                )
                #expect(sema.symbols.isSourceBackedSymbol(symbolID))
                #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                #expect(signature.parameterTypes.isEmpty)
                let receiverType = try #require(signature.receiverType)
                #expect(signature.returnType == receiverType)
                #expect(signature.valueParameterHasDefaultValues.isEmpty)
                #expect(signature.valueParameterIsVararg.isEmpty)
                #expect(signature.typeParameterSymbols.count == 1)
            }

            // === testArrayContentDeepToStringIsBundledSourceBacked ===
            do {
                #expect(
                    sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("Array"),
                            ctx.interner.intern("contentDeepToString"),
                        ]
                    ) == nil,
                    "Generic Array.contentDeepToString synthetic stub should be removed"
                )
                let symbolID = try #require(
                    sourceArrayExtension(named: "contentDeepToString", receiverName: "Array"),
                    "Expected bundled source Array.contentDeepToString extension"
                )
                #expect((sema.symbols.externalLinkName(for: symbolID) ?? "").isEmpty)
                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                #expect(signature.parameterTypes == [])
                #expect(signature.returnType == sema.types.stringType)
                #expect(signature.typeParameterSymbols.count == 1)
                guard let receiverType = signature.receiverType,
                      case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                      let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
                else {
                    Issue.record("Expected Array receiver type")
                    return
                }
                #expect(ctx.interner.resolve(receiverSymbol.name) == "Array")
                #expect(receiverClass.args.count == 1)
            }

            // === testArrayContentDeepHashCodeIsBundledSourceBacked ===
            do {
                #expect(
                    sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("Array"),
                            ctx.interner.intern("contentDeepHashCode"),
                        ]
                    ) == nil,
                    "Generic Array.contentDeepHashCode synthetic stub should be removed"
                )
                let symbolID = try #require(
                    sourceArrayExtension(named: "contentDeepHashCode", receiverName: "Array"),
                    "Expected bundled source Array.contentDeepHashCode extension"
                )
                #expect((sema.symbols.externalLinkName(for: symbolID) ?? "").isEmpty)
                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                #expect(signature.parameterTypes == [])
                #expect(signature.returnType == sema.types.intType)
                #expect(signature.typeParameterSymbols.count == 1)
                guard let receiverType = signature.receiverType,
                      case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                      let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
                else {
                    Issue.record("Expected Array receiver type")
                    return
                }
                #expect(ctx.interner.resolve(receiverSymbol.name) == "Array")
                #expect(receiverClass.args.count == 1)
            }

            // === testArrayContentToStringIsBundledSourceBacked ===
            do {
                // KSP-658: generic Array<T>.contentToString migrated to bundled Kotlin
                // source (kotlin.collections.contentToString); the synthetic Array member
                // stub linking to kk_array_contentToString was removed.
                #expect(
                    sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("Array"),
                            ctx.interner.intern("contentToString"),
                        ]
                    ) == nil,
                    "Generic Array.contentToString synthetic stub should be removed"
                )
                let symbolID = try #require(
                    sema.symbols.lookupAll(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("collections"),
                            ctx.interner.intern("contentToString"),
                        ]
                    ).first(where: { candidate in
                        guard let symbol = sema.symbols.symbol(candidate),
                              symbol.kind == .function,
                              symbol.declSite != nil
                        else {
                            return false
                        }
                        return true
                    }),
                    "Expected bundled source Array.contentToString extension"
                )
                #expect((sema.symbols.externalLinkName(for: symbolID) ?? "").isEmpty)
                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                #expect(signature.parameterTypes == [])
                #expect(signature.returnType == sema.types.stringType)
                #expect(signature.typeParameterSymbols.count == 1)
                guard let receiverType = signature.receiverType,
                      case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                      let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
                else {
                    Issue.record("Expected Array receiver type")
                    return
                }
                #expect(ctx.interner.resolve(receiverSymbol.name) == "Array")
                #expect(receiverClass.args.count == 1)
            }

            // === testArrayContentDeepEqualsIsBundledSourceBacked ===
            do {
                #expect(
                    sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern("Array"),
                            ctx.interner.intern("contentDeepEquals"),
                        ]
                    ) == nil,
                    "Generic Array.contentDeepEquals synthetic stub should be removed"
                )
                let symbolID = try #require(
                    sourceArrayExtension(named: "contentDeepEquals", receiverName: "Array"),
                    "Expected bundled source Array.contentDeepEquals extension"
                )
                #expect((sema.symbols.externalLinkName(for: symbolID) ?? "").isEmpty)
                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                #expect(signature.parameterTypes.count == 1)
                #expect(signature.returnType == sema.types.booleanType)
                #expect(signature.typeParameterSymbols.count == 1)
                guard let receiverType = signature.receiverType,
                      case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                      case let .classType(parameterClass) = sema.types.kind(of: signature.parameterTypes[0]),
                      let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol),
                      let parameterSymbol = sema.symbols.symbol(parameterClass.classSymbol)
                else {
                    Issue.record("Expected Array receiver and parameter types")
                    return
                }
                #expect(ctx.interner.resolve(receiverSymbol.name) == "Array")
                #expect(ctx.interner.resolve(parameterSymbol.name) == "Array")
                #expect(receiverClass.args.count == 1)
                #expect(parameterClass.args.count == 1)
            }

            // === testArrayContentComparisonAndHashAreBundledSourceBacked ===
            do {
                for functionName in ["contentEquals", "contentHashCode"] {
                    #expect(
                        sema.symbols.lookup(
                            fqName: [
                                ctx.interner.intern("kotlin"),
                                ctx.interner.intern("Array"),
                                ctx.interner.intern(functionName),
                            ]
                        ) == nil,
                        "Generic Array.\(functionName) synthetic stub should be removed"
                    )
                    let symbolID = try #require(
                        sourceArrayExtension(named: functionName, receiverName: "Array"),
                        "Expected bundled source Array.\(functionName) extension"
                    )
                    #expect((sema.symbols.externalLinkName(for: symbolID) ?? "").isEmpty)
                }
            }

            // === testArrayCopySurfaceIsBundledSourceBacked ===
            do {
                for functionName in ["copyOf", "copyOfRange", "copyInto"] {
                    #expect(
                        sema.symbols.lookup(
                            fqName: [
                                ctx.interner.intern("kotlin"),
                                ctx.interner.intern("Array"),
                                ctx.interner.intern(functionName),
                            ]
                        ) == nil,
                        "Generic Array.\(functionName) synthetic stub should be removed"
                    )
                }

                let symbolID = try #require(
                    sourceArrayExtension(named: "copyInto", receiverName: "Array"),
                    "Expected bundled source Array.copyInto extension"
                )
                #expect(sema.symbols.isSourceBackedSymbol(symbolID))
                #expect((sema.symbols.externalLinkName(for: symbolID) ?? "").isEmpty)
                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                #expect(signature.parameterTypes.count == 4)
                #expect(signature.returnType == signature.parameterTypes[0])
                #expect(signature.valueParameterHasDefaultValues == [false, true, true, true])
                #expect(signature.valueParameterIsVararg == [false, false, false, false])
                #expect(signature.typeParameterSymbols.count == 1)
                let parameterNames = signature.valueParameterSymbols.compactMap { symbolID in
                    sema.symbols.symbol(symbolID).map { ctx.interner.resolve($0.name) }
                }
                #expect(parameterNames == ["destination", "destinationOffset", "startIndex", "endIndex"])

                for functionName in ["copyOf", "copyOfRange"] {
                    let sourceSymbol = try #require(
                        sourceArrayExtension(named: functionName, receiverName: "Array"),
                        "Expected bundled source Array.\(functionName) extension"
                    )
                    #expect(sema.symbols.isSourceBackedSymbol(sourceSymbol))
                    #expect((sema.symbols.externalLinkName(for: sourceSymbol) ?? "").isEmpty)
                }
            }

            // === testPrimitiveArrayContentToStringOverloadsAreSourceBacked ===
            do {
                let primitiveArrayNames = [
                    "IntArray", "LongArray", "ByteArray", "ShortArray",
                    "UIntArray", "ULongArray", "DoubleArray", "FloatArray",
                    "BooleanArray", "CharArray", "UByteArray", "UShortArray",
                ]
                for arrayName in primitiveArrayNames {
                    #expect(
                        sema.symbols.lookup(
                            fqName: [
                                ctx.interner.intern("kotlin"),
                                ctx.interner.intern(arrayName),
                                ctx.interner.intern("contentToString"),
                            ]
                        ) == nil,
                        "Synthetic \(arrayName).contentToString stub should be removed"
                    )
                    let symbolID = try #require(
                        sourceArrayExtension(named: "contentToString", receiverName: arrayName),
                        "Expected bundled source \(arrayName).contentToString extension"
                    )
                    #expect((sema.symbols.externalLinkName(for: symbolID) ?? "").isEmpty)
                    let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                    #expect(signature.parameterTypes == [], "\(arrayName).contentToString should not take parameters")
                    #expect(signature.returnType == sema.types.stringType)
                    guard let receiverType = signature.receiverType,
                          case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                          let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
                    else {
                        Issue.record("Expected \(arrayName) receiver type")
                        return
                    }
                    #expect(ctx.interner.resolve(receiverSymbol.name) == arrayName)
                    #expect(receiverClass.args.count == 0)
                }
            }

            // === testPrimitiveArrayContentComparisonOverloadsAreSourceBacked ===
            do {
                let primitiveArrayNames = [
                    "IntArray", "LongArray", "ByteArray", "ShortArray",
                    "UIntArray", "ULongArray", "DoubleArray", "FloatArray",
                    "BooleanArray", "CharArray", "UByteArray", "UShortArray",
                ]
                for functionName in ["contentEquals", "contentHashCode"] {
                    for arrayName in primitiveArrayNames {
                        #expect(
                            sema.symbols.lookup(
                                fqName: [
                                    ctx.interner.intern("kotlin"),
                                    ctx.interner.intern(arrayName),
                                    ctx.interner.intern(functionName),
                                ]
                            ) == nil,
                            "Synthetic \(arrayName).\(functionName) stub should be removed"
                        )
                        let symbolID = try #require(
                            sourceArrayExtension(named: functionName, receiverName: arrayName),
                            "Expected bundled source \(arrayName).\(functionName) extension"
                        )
                        #expect((sema.symbols.externalLinkName(for: symbolID) ?? "").isEmpty)
                    }
                }
            }

            // === testPrimitiveArrayJoinToStringSyntheticOverloadsAreRemoved ===
            do {
                let primitiveArrayNames = [
                    "IntArray", "LongArray", "ByteArray", "ShortArray",
                    "UIntArray", "ULongArray", "DoubleArray", "FloatArray",
                    "BooleanArray", "CharArray", "UByteArray", "UShortArray",
                ]
                for arrayName in primitiveArrayNames {
                    let nestedFQName = [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern(arrayName),
                        ctx.interner.intern("joinToString"),
                    ]
                    #expect(
                        sema.symbols.lookupAll(fqName: nestedFQName).isEmpty,
                        "Expected synthetic \(arrayName).joinToString overloads to be removed"
                    )
                }
            }

            // === testArrayConversionMembersAreBundledSourceBacked ===
            do {
                let arrayNames = [
                    "Array",
                    "IntArray",
                    "LongArray",
                    "ByteArray",
                    "ShortArray",
                    "UIntArray",
                    "ULongArray",
                    "DoubleArray",
                    "FloatArray",
                    "BooleanArray",
                    "CharArray",
                    "UByteArray",
                    "UShortArray",
                ]
                for arrayName in arrayNames {
                    for functionName in ["sliceArray", "reversedArray"] {
                        #expect(
                            sema.symbols.lookupAll(
                                fqName: [
                                    ctx.interner.intern("kotlin"),
                                    ctx.interner.intern(arrayName),
                                    ctx.interner.intern(functionName),
                                ]
                            ).isEmpty,
                            "Expected synthetic \(arrayName).\(functionName) overloads to be removed"
                        )
                        let sourceSymbols = sema.symbols.lookupAll(
                            fqName: [
                                ctx.interner.intern("kotlin"),
                                ctx.interner.intern("collections"),
                                ctx.interner.intern(functionName),
                            ]
                        ).filter { symbolID in
                            guard let receiverType = sema.symbols.functionSignature(for: symbolID)?.receiverType,
                                  case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                                  let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
                            else { return false }
                            return ctx.interner.resolve(receiverSymbol.name) == arrayName
                        }
                        #expect(!sourceSymbols.isEmpty, "Expected bundled source \(arrayName).\(functionName) overloads")
                        #expect(sourceSymbols.allSatisfy { sema.symbols.isSourceBackedSymbol($0) })
                        #expect(sourceSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })
                    }
                }
            }

            // === testPrimitiveArrayCopySurfaceIsBundledSourceBacked ===
            do {
                let arrayNames = [
                    "IntArray",
                    "LongArray",
                    "ByteArray",
                    "ShortArray",
                    "UIntArray",
                    "ULongArray",
                    "DoubleArray",
                    "FloatArray",
                    "BooleanArray",
                    "CharArray",
                    "UByteArray",
                    "UShortArray",
                ]
                for arrayName in arrayNames {
                    for functionName in ["copyOf", "copyOfRange", "copyInto"] {
                        let symbolID = try #require(
                            sourceArrayExtension(named: functionName, receiverName: arrayName),
                            "Expected bundled source \(arrayName).\(functionName) extension"
                        )
                        #expect(sema.symbols.isSourceBackedSymbol(symbolID))
                        #expect((sema.symbols.externalLinkName(for: symbolID) ?? "").isEmpty)
                        let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                        let expectedParameterCount = switch functionName {
                        case "copyOf": 0
                        case "copyOfRange": 2
                        default: 4
                        }
                        #expect(
                            signature.parameterTypes.count == expectedParameterCount,
                            "\(arrayName).\(functionName) source overload should expose its base arity"
                        )
                        if functionName == "copyInto" {
                            #expect(signature.valueParameterHasDefaultValues == [false, true, true, true])
                            #expect(signature.valueParameterIsVararg == [false, false, false, false])
                        }
                    }
                }
            }


        // === testArrayAllFallbackInfersBooleanResult ===
        do {
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Array.all to type-check without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            let callExpr = try #require(firstExprID(in: ast, path: userPaths[0], ctx: ctx) { exprID, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "all"
            }, "Expected Array.all member call")
            #expect(sema.bindings.exprType(for: callExpr) == sema.types.booleanType)
        }

        // === testArrayMapIndexedInfersListResult ===
        // KSP-433: mapIndexed moved to bundled Kotlin source (ArrayHOF.kt), so it
        // resolves as an ordinary `Array<T>.mapIndexed(...): List<R>` extension
        // instead of going through `tryArrayMemberFallback`, whose result type
        // was erased to `Any` with `isCollectionExpr` as the out-of-band signal
        // for downstream KIR/runtime dispatch.
        do {
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Array.mapIndexed to type-check without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            let callExpr = try #require(firstExprID(in: ast, path: userPaths[1], ctx: ctx) { exprID, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "mapIndexed"
            }, "Expected Array.mapIndexed member call")
            let resultType = try #require(sema.bindings.exprType(for: callExpr))
            guard case let .classType(resultClass) = sema.types.kind(of: resultType),
                  let resultSymbol = sema.symbols.symbol(resultClass.classSymbol)
            else {
                Issue.record("Expected Array.mapIndexed to return a List class type")
                return
            }
            #expect(ctx.interner.resolve(resultSymbol.name) == "List")
        }

        // === testArrayFilterNotNullAcceptsZeroArgumentsAndInfersListResult ===
        // See the mapIndexed case above: filterNotNull is bundled Kotlin source
        // (ArrayFilterHOF.kt) since KSP-433, so its result is a real `List<T>`.
        do {
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Array.filterNotNull to type-check without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            let callExpr = try #require(firstExprID(in: ast, path: userPaths[2], ctx: ctx) { exprID, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "filterNotNull"
            }, "Expected Array.filterNotNull member call")
            let resultType = try #require(sema.bindings.exprType(for: callExpr))
            guard case let .classType(resultClass) = sema.types.kind(of: resultType),
                  let resultSymbol = sema.symbols.symbol(resultClass.classSymbol)
            else {
                Issue.record("Expected Array.filterNotNull to return a List class type")
                return
            }
            #expect(ctx.interner.resolve(resultSymbol.name) == "List")
        }

        // === testArrayFirstOrNullFallbackInfersNullableElementType ===
        do {
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Array.firstOrNull to type-check without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            let callExpr = try #require(firstExprID(in: ast, path: userPaths[3], ctx: ctx) { exprID, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "firstOrNull"
            }, "Expected Array.firstOrNull member call")
            let resultType = try #require(sema.bindings.exprType(for: callExpr))
            #expect(sema.types.nullability(of: resultType) == .nullable, "Expected Array.firstOrNull() to infer a nullable result type")
            #expect(sema.types.makeNonNullable(resultType) == sema.types.intType)
        }

        // === testArrayFirstFallbackInfersNonNullElementType ===
        do {
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Array.first to type-check without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            let callExpr = try #require(firstExprID(in: ast, path: userPaths[4], ctx: ctx) { exprID, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "first"
            }, "Expected Array.first member call")
            #expect(sema.bindings.exprType(for: callExpr) == sema.types.intType)
        }

        // === testArrayReduceIndexedFallbackInfersElementType ===
        do {
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Array.reduceIndexed to type-check without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            let callExpr = try #require(firstExprID(in: ast, path: userPaths[5], ctx: ctx) { exprID, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "reduceIndexed"
            }, "Expected Array.reduceIndexed member call")
            #expect(sema.bindings.exprType(for: callExpr) == sema.types.intType)
        }

    }

    @Test
    func testGenericArrayJoinToStringIsSourceBacked() throws {
        let ctx = makeContextFromSource(
            """
            fun main() {
                val values: Array<Int?> = arrayOf(1, null, 3)
                println(values.joinToString("|", "<", ">", 2, "..."))
                println(values.joinToString("|", "<", ">", 2, "...") { it.toString() })
            }
            """
        )
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let genericArrayJoinSymbols = sema.symbols.lookupAll(fqName: [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("collections"),
            ctx.interner.intern("joinToString"),
        ]).filter { symbolID in
            guard let info = sema.symbols.symbol(symbolID),
                  info.kind == .function,
                  !info.flags.contains(.synthetic),
                  let fileID = sema.symbols.sourceFileID(for: symbolID),
                  ctx.sourceManager.path(of: fileID).hasPrefix("__bundled_"),
                  let signature = sema.symbols.functionSignature(for: symbolID),
                  let receiverType = signature.receiverType,
                  case let .classType(receiverClass) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                  let receiverInfo = sema.symbols.symbol(receiverClass.classSymbol)
            else {
                return false
            }
            return ctx.interner.resolve(receiverInfo.name) == "Array"
        }
        #expect(!genericArrayJoinSymbols.isEmpty, "Expected source-backed Array.joinToString symbols")
        #expect(
            genericArrayJoinSymbols.allSatisfy { symbolID in
                guard let info = sema.symbols.symbol(symbolID) else { return false }
                return !info.flags.contains(.synthetic)
                    && sema.symbols.externalLinkName(for: symbolID) == nil
            },
            "Generic Array.joinToString must not retain a synthetic runtime link"
        )
        #expect(
            !sema.symbols.allSymbols().contains {
                sema.symbols.externalLinkName(for: $0.id) == "kk_array_joinToString"
            },
            "The generic kk_array_joinToString bridge must be removed"
        )
    }

    @Test
    func testPrimitiveArrayHOFsBindBundledKotlinSource() throws {
        let sources: [(arrayName: String, expression: String)] = [
            ("IntArray", "intArrayOf(1)"),
            ("LongArray", "longArrayOf(1L)"),
            ("ByteArray", "byteArrayOf(1)"),
            ("ShortArray", "shortArrayOf(1)"),
            ("UIntArray", "uintArrayOf(1u)"),
            ("ULongArray", "ulongArrayOf(1uL)"),
            ("DoubleArray", "doubleArrayOf(1.0)"),
            ("FloatArray", "floatArrayOf(1.0f)"),
            ("BooleanArray", "booleanArrayOf(true)"),
            ("CharArray", "charArrayOf('a')"),
            ("UByteArray", "UByteArray(1) { 1.toUByte() }"),
            ("UShortArray", "UShortArray(1) { 1.toUShort() }"),
        ]
        let ctx = makeContextFromSources(sources.map { entry in
            let transform = entry.arrayName == "UByteArray" || entry.arrayName == "UShortArray"
                ? "(it * 2u).toString()"
                : "it.toString()"
            return "fun sample() { val values = \(entry.expression); println(values.map { \(transform) }) }"
        })
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let userPaths = ctx.sourceManager.fileIDs()
            .filter { ctx.sourceManager.origin(of: $0) == .user }
            .map { ctx.sourceManager.path(of: $0) }

        for (index, entry) in sources.enumerated() {
            let callExpr = try #require(firstExprID(in: ast, path: userPaths[index], ctx: ctx) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "map"
            }, "Expected \(entry.arrayName).map call")
            let chosen = try #require(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected \(entry.arrayName).map to bind a callee"
            )
            let symbol = try #require(sema.symbols.symbol(chosen))
            #expect(
                symbol.fqName == [ctx.interner.intern("kotlin"), ctx.interner.intern("collections"), ctx.interner.intern("map")],
                "Expected \(entry.arrayName).map to bind kotlin.collections.map, got \(symbol.fqName.map { ctx.interner.resolve($0) }.joined(separator: "."))"
            )
            #expect(
                sema.symbols.externalLinkName(for: chosen) == nil,
                "Expected \(entry.arrayName).map to have no runtime link, got \(sema.symbols.externalLinkName(for: chosen) ?? "nil")"
            )
            #expect(
                !symbol.flags.contains(.synthetic),
                "Expected \(entry.arrayName).map to bind bundled Kotlin source"
            )
        }
    }

    @Test
    func testPrimitiveArrayJoinToStringTransformBindsBundledKotlinSource() throws {
        let sources: [(arrayName: String, expression: String)] = [
            ("IntArray", "intArrayOf(1)"),
            ("LongArray", "longArrayOf(1L)"),
            ("ByteArray", "byteArrayOf(1)"),
            ("ShortArray", "shortArrayOf(1)"),
            ("UIntArray", "uintArrayOf(1u)"),
            ("ULongArray", "ulongArrayOf(1uL)"),
            ("DoubleArray", "doubleArrayOf(1.0)"),
            ("FloatArray", "floatArrayOf(1.0f)"),
            ("BooleanArray", "booleanArrayOf(true)"),
            ("CharArray", "charArrayOf('a')"),
            ("UByteArray", "UByteArray(1) { 1.toUByte() }"),
            ("UShortArray", "UShortArray(1) { 1.toUShort() }"),
        ]
        let ctx = makeContextFromSources(sources.map { entry in
            "fun sample() { val values = \(entry.expression); println(values.joinToString(\"-\", transform = { it.toString() })) }"
        })
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let userPaths = ctx.sourceManager.fileIDs()
            .filter { ctx.sourceManager.origin(of: $0) == .user }
            .map { ctx.sourceManager.path(of: $0) }

        for (index, entry) in sources.enumerated() {
            let callExpr = try #require(firstExprID(in: ast, path: userPaths[index], ctx: ctx) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "joinToString"
            }, "Expected \(entry.arrayName).joinToString call")
            let chosen = try #require(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected \(entry.arrayName).joinToString to bind a callee"
            )
            let symbol = try #require(sema.symbols.symbol(chosen))
            #expect(
                symbol.fqName == [ctx.interner.intern("kotlin"), ctx.interner.intern("collections"), ctx.interner.intern("joinToString")],
                "Expected \(entry.arrayName).joinToString to bind bundled source, got \(symbol.fqName.map { ctx.interner.resolve($0) }.joined(separator: "."))"
            )
            #expect(sema.symbols.externalLinkName(for: chosen) == nil)
            #expect(!symbol.flags.contains(.synthetic))
        }
    }

    @Test
    func testGenericArrayJoinToStringTransformBindsBundledKotlinSource() throws {
        let ctx = makeContextFromSources([
            """
            fun sample() {
                val values = arrayOf(1, 2, 3)
                println(values.joinToString("-", transform = { it.toString() }))
            }
            """,
        ])
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let path = ctx.sourceManager.fileIDs()
            .filter { ctx.sourceManager.origin(of: $0) == .user }
            .map { ctx.sourceManager.path(of: $0) }
            .first ?? ""
        let callExpr = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "joinToString"
        }, "Expected generic Array.joinToString call")
        let chosen = try #require(
            sema.bindings.callBinding(for: callExpr)?.chosenCallee,
            "Expected generic Array.joinToString to bind a callee"
        )
        let symbol = try #require(sema.symbols.symbol(chosen))
        #expect(
            symbol.fqName == [ctx.interner.intern("kotlin"), ctx.interner.intern("collections"), ctx.interner.intern("joinToString")],
            "Expected generic Array.joinToString to bind bundled source, got \(symbol.fqName.map { ctx.interner.resolve($0) }.joined(separator: "."))"
        )
        #expect(sema.symbols.externalLinkName(for: chosen) == nil)
        #expect(!symbol.flags.contains(.synthetic))
    }


}
#endif
