@testable import CompilerCore
import Foundation
import XCTest

final class ArraySyntheticMemberLinkTests: XCTestCase {
    func testArrayAllFallbackInfersBooleanResult() throws {
        let source = """
        fun sample(): Boolean {
            val values = arrayOf(1, 2, 3)
            return values.all { it > 0 }
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected Array.all to type-check without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
        )

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)
        let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "all"
        }, "Expected Array.all member call")

        XCTAssertEqual(sema.bindings.exprType(for: callExpr), sema.types.booleanType)
    }

    func testArrayOfNullsTopLevelFactoryUsesRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(
                sema.symbols.lookup(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("arrayOfNulls"),
                    ]
                ),
                "Expected synthetic arrayOfNulls function to be registered"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbolID), "kk_array_of_nulls")

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
            XCTAssertEqual(signature.parameterTypes, [sema.types.intType])
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
            XCTAssertEqual(signature.valueParameterIsVararg, [false])
            XCTAssertEqual(signature.typeParameterSymbols.count, 1)

            guard case let .classType(returnClass) = sema.types.kind(of: signature.returnType),
                  let arraySymbol = sema.symbols.symbol(returnClass.classSymbol)
            else {
                return XCTFail("Expected arrayOfNulls to return Array<T?>")
            }
            XCTAssertEqual(ctx.interner.resolve(arraySymbol.name), "Array")
            XCTAssertEqual(returnClass.args.count, 1)

            guard case let .invariant(elementType) = returnClass.args[0],
                  case let .typeParam(typeParam) = sema.types.kind(of: elementType)
            else {
                return XCTFail("Expected arrayOfNulls element type to be nullable type parameter")
            }
            XCTAssertEqual(typeParam.symbol, signature.typeParameterSymbols[0])
            XCTAssertEqual(typeParam.nullability, .nullable)
        }
    }

    func testArrayBinarySearchComparatorOverloadUsesRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(
                sema.symbols.lookupAll(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("Array"),
                        ctx.interner.intern("binarySearch$compare"),
                    ]
                ).first(where: { sema.symbols.externalLinkName(for: $0) == "kk_array_binarySearch_compare" }),
                "Expected synthetic Array member binarySearch to be registered"
            )
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
            XCTAssertEqual(signature.parameterTypes.count, 4)
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false, false, true, true])
            XCTAssertEqual(signature.valueParameterIsVararg, [false, false, false, false])

            guard let receiverType = signature.receiverType,
                  case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                  let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
            else {
                return XCTFail("Expected Array receiver type")
            }
            XCTAssertEqual(ctx.interner.resolve(receiverSymbol.name), "Array")
            XCTAssertEqual(receiverClass.args.count, 1)

            guard case let .classType(comparatorType) = sema.types.kind(of: signature.parameterTypes[1]),
                  let comparatorSymbol = sema.symbols.symbol(comparatorType.classSymbol)
            else {
                return XCTFail("Expected Comparator parameter type")
            }
            XCTAssertEqual(ctx.interner.resolve(comparatorSymbol.name), "Comparator")
            XCTAssertEqual(comparatorType.args.count, 1)
        }
    }

    func testArrayReversedArrayUsesRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(
                sema.symbols.lookup(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("Array"),
                        ctx.interner.intern("reversedArray"),
                    ]
                ),
                "Expected synthetic Array.reversedArray to be registered"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbolID), "kk_array_reversedArray")

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
            XCTAssertTrue(signature.parameterTypes.isEmpty)
            let receiverType = try XCTUnwrap(signature.receiverType)
            XCTAssertEqual(signature.returnType, receiverType)
            XCTAssertTrue(signature.valueParameterHasDefaultValues.isEmpty)
            XCTAssertTrue(signature.valueParameterIsVararg.isEmpty)
            XCTAssertEqual(signature.typeParameterSymbols.count, 1)
        }
    }

    func testArrayContentDeepToStringUsesRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(
                sema.symbols.lookup(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("Array"),
                        ctx.interner.intern("contentDeepToString"),
                    ]
                ),
                "Expected synthetic Array.contentDeepToString to be registered"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbolID), "kk_array_contentDeepToString")

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
            XCTAssertEqual(signature.parameterTypes, [])
            XCTAssertEqual(signature.returnType, sema.types.stringType)
            XCTAssertEqual(signature.typeParameterSymbols.count, 1)

            guard let receiverType = signature.receiverType,
                  case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                  let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
            else {
                return XCTFail("Expected Array receiver type")
            }
            XCTAssertEqual(ctx.interner.resolve(receiverSymbol.name), "Array")
            XCTAssertEqual(receiverClass.args.count, 1)
        }
    }

    func testArrayContentDeepHashCodeUsesRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(
                sema.symbols.lookup(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("Array"),
                        ctx.interner.intern("contentDeepHashCode"),
                    ]
                ),
                "Expected synthetic Array.contentDeepHashCode to be registered"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbolID), "kk_array_contentDeepHashCode")

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
            XCTAssertEqual(signature.parameterTypes, [])
            XCTAssertEqual(signature.returnType, sema.types.intType)
            XCTAssertEqual(signature.typeParameterSymbols.count, 1)

            guard let receiverType = signature.receiverType,
                  case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                  let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
            else {
                return XCTFail("Expected Array receiver type")
            }
            XCTAssertEqual(ctx.interner.resolve(receiverSymbol.name), "Array")
            XCTAssertEqual(receiverClass.args.count, 1)
        }
    }

    func testArrayContentToStringUsesRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(
                sema.symbols.lookup(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("Array"),
                        ctx.interner.intern("contentToString"),
                    ]
                ),
                "Expected synthetic Array.contentToString to be registered"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbolID), "kk_array_contentToString")

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
            XCTAssertEqual(signature.parameterTypes, [])
            XCTAssertEqual(signature.returnType, sema.types.stringType)
            XCTAssertEqual(signature.typeParameterSymbols.count, 1)

            guard let receiverType = signature.receiverType,
                  case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                  let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
            else {
                return XCTFail("Expected Array receiver type")
            }
            XCTAssertEqual(ctx.interner.resolve(receiverSymbol.name), "Array")
            XCTAssertEqual(receiverClass.args.count, 1)
        }
    }

    func testArrayContentDeepEqualsUsesRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(
                sema.symbols.lookup(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("Array"),
                        ctx.interner.intern("contentDeepEquals"),
                    ]
                ),
                "Expected synthetic Array.contentDeepEquals to be registered"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbolID), "kk_array_contentDeepEquals")

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
            XCTAssertEqual(signature.parameterTypes.count, 1)
            XCTAssertEqual(signature.returnType, sema.types.booleanType)
            XCTAssertEqual(signature.typeParameterSymbols.count, 1)

            guard let receiverType = signature.receiverType,
                  case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                  case let .classType(parameterClass) = sema.types.kind(of: signature.parameterTypes[0]),
                  let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol),
                  let parameterSymbol = sema.symbols.symbol(parameterClass.classSymbol)
            else {
                return XCTFail("Expected Array receiver and parameter types")
            }
            XCTAssertEqual(ctx.interner.resolve(receiverSymbol.name), "Array")
            XCTAssertEqual(ctx.interner.resolve(parameterSymbol.name), "Array")
            XCTAssertEqual(receiverClass.args.count, 1)
            XCTAssertEqual(parameterClass.args.count, 1)
        }
    }

    func testArrayCopyIntoUsesRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(
                sema.symbols.lookup(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("Array"),
                        ctx.interner.intern("copyInto"),
                    ]
                ),
                "Expected synthetic Array.copyInto to be registered"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbolID), "kk_array_copyInto")

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
            XCTAssertEqual(signature.parameterTypes.count, 4)
            let receiverType = try XCTUnwrap(signature.receiverType)
            XCTAssertEqual(signature.returnType, receiverType)
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false, true, true, true])
            XCTAssertEqual(signature.valueParameterIsVararg, [false, false, false, false])
            XCTAssertEqual(signature.typeParameterSymbols.count, 1)

            let parameterNames = signature.valueParameterSymbols.compactMap { symbolID in
                sema.symbols.symbol(symbolID).map { ctx.interner.resolve($0.name) }
            }
            XCTAssertEqual(parameterNames, ["destination", "destinationOffset", "startIndex", "endIndex"])
        }
    }

    func testPrimitiveArrayContentToStringOverloadsUseRuntimeExternalLinks() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let expectedLinks = [
                "IntArray": "kk_intArray_contentToString",
                "LongArray": "kk_longArray_contentToString",
                "ByteArray": "kk_byteArray_contentToString",
                "ShortArray": "kk_shortArray_contentToString",
                "UIntArray": "kk_uIntArray_contentToString",
                "ULongArray": "kk_uLongArray_contentToString",
                "DoubleArray": "kk_doubleArray_contentToString",
                "FloatArray": "kk_floatArray_contentToString",
                "BooleanArray": "kk_booleanArray_contentToString",
                "CharArray": "kk_charArray_contentToString",
                "UByteArray": "kk_uByteArray_contentToString",
                "UShortArray": "kk_uShortArray_contentToString",
            ]

            for (arrayName, externalLink) in expectedLinks {
                let symbolID = try XCTUnwrap(
                    sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern(arrayName),
                            ctx.interner.intern("contentToString"),
                        ]
                    ),
                    "Expected \(arrayName).contentToString to be registered"
                )
                XCTAssertEqual(sema.symbols.externalLinkName(for: symbolID), externalLink)

                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
                XCTAssertEqual(signature.parameterTypes, [], "\(arrayName).contentToString should not take parameters")
                XCTAssertEqual(signature.returnType, sema.types.stringType)

                guard let receiverType = signature.receiverType,
                      case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                      let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
                else {
                    return XCTFail("Expected \(arrayName) receiver type")
                }
                XCTAssertEqual(ctx.interner.resolve(receiverSymbol.name), arrayName)
                XCTAssertEqual(receiverClass.args.count, 0)
            }
        }
    }

    func testPrimitiveArrayReversedArrayOverloadsUseRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
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
                let symbolID = try XCTUnwrap(
                    sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern(arrayName),
                            ctx.interner.intern("reversedArray"),
                        ]
                    ),
                    "Expected \(arrayName).reversedArray to be registered"
                )
                XCTAssertEqual(sema.symbols.externalLinkName(for: symbolID), "kk_array_reversedArray")

                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
                XCTAssertTrue(signature.parameterTypes.isEmpty, "\(arrayName).reversedArray should take no parameters")
                let receiverType = try XCTUnwrap(signature.receiverType)
                XCTAssertEqual(signature.returnType, receiverType, "\(arrayName).reversedArray should return the same array type")
                XCTAssertTrue(signature.valueParameterHasDefaultValues.isEmpty)
                XCTAssertTrue(signature.valueParameterIsVararg.isEmpty)
            }
        }
    }

    func testArraySortedArrayWithUsesRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(
                sema.symbols.lookup(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("Array"),
                        ctx.interner.intern("sortedArrayWith"),
                    ]
                ),
                "Expected synthetic Array.sortedArrayWith to be registered"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbolID), "kk_array_sortedArrayWith")

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
            XCTAssertEqual(signature.parameterTypes.count, 1)
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
            XCTAssertEqual(signature.valueParameterIsVararg, [false])
            XCTAssertEqual(signature.typeParameterSymbols.count, 1)

            guard let receiverType = signature.receiverType,
                  case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                  case let .classType(returnClass) = sema.types.kind(of: signature.returnType),
                  let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
            else {
                return XCTFail("Expected Array.sortedArrayWith receiver and return class types")
            }
            XCTAssertEqual(ctx.interner.resolve(receiverSymbol.name), "Array")
            XCTAssertEqual(receiverClass.classSymbol, returnClass.classSymbol)

            guard case let .classType(comparatorType) = sema.types.kind(of: signature.parameterTypes[0]),
                  let comparatorSymbol = sema.symbols.symbol(comparatorType.classSymbol)
            else {
                return XCTFail("Expected Comparator parameter type")
            }
            XCTAssertEqual(ctx.interner.resolve(comparatorSymbol.name), "Comparator")
            XCTAssertEqual(comparatorType.args.count, 1)
        }
    }

    func testArraySortedArrayUsesRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(
                sema.symbols.lookup(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("Array"),
                        ctx.interner.intern("sortedArray"),
                    ]
                ),
                "Expected synthetic Array.sortedArray to be registered"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbolID), "kk_array_sortedArray")

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
            XCTAssertTrue(signature.parameterTypes.isEmpty)
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [])
            XCTAssertEqual(signature.valueParameterIsVararg, [])
            XCTAssertEqual(signature.typeParameterSymbols.count, 1)
            XCTAssertEqual(signature.typeParameterUpperBoundsList.count, 1)
            let receiverType = try XCTUnwrap(signature.receiverType)
            guard case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                  case let .classType(returnClass) = sema.types.kind(of: signature.returnType)
            else {
                return XCTFail("Expected Array.sortedArray receiver and return class types")
            }
            XCTAssertEqual(receiverClass.classSymbol, returnClass.classSymbol)
        }
    }

    func testArraySortedArrayDescendingUsesRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(
                sema.symbols.lookup(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("Array"),
                        ctx.interner.intern("sortedArrayDescending"),
                    ]
                ),
                "Expected synthetic Array.sortedArrayDescending to be registered"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbolID), "kk_array_sortedArrayDescending")

            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
            XCTAssertTrue(signature.parameterTypes.isEmpty)
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [])
            XCTAssertEqual(signature.valueParameterIsVararg, [])
            XCTAssertEqual(signature.typeParameterSymbols.count, 1)
            XCTAssertEqual(signature.typeParameterUpperBoundsList.count, 1)
            let receiverType = try XCTUnwrap(signature.receiverType)
            guard case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                  case let .classType(returnClass) = sema.types.kind(of: signature.returnType)
            else {
                return XCTFail("Expected Array.sortedArrayDescending receiver and return class types")
            }
            XCTAssertEqual(receiverClass.classSymbol, returnClass.classSymbol)
        }
    }

    func testPrimitiveArraySortedArrayOverloadsUseRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
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
                let symbolID = try XCTUnwrap(
                    sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern(arrayName),
                            ctx.interner.intern("sortedArray"),
                        ]
                    ),
                    "Expected \(arrayName).sortedArray to be registered"
                )
                XCTAssertEqual(sema.symbols.externalLinkName(for: symbolID), "kk_array_sortedArray")

                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
                XCTAssertTrue(signature.parameterTypes.isEmpty, "\(arrayName).sortedArray should take no parameters")
                let receiverType = try XCTUnwrap(signature.receiverType)
                XCTAssertEqual(signature.returnType, receiverType, "\(arrayName).sortedArray should return the same array type")
                XCTAssertTrue(signature.valueParameterHasDefaultValues.isEmpty)
                XCTAssertTrue(signature.valueParameterIsVararg.isEmpty)
            }
        }
    }

    func testPrimitiveArraySortedArrayDescendingOverloadsUseRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
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
                let symbolID = try XCTUnwrap(
                    sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern(arrayName),
                            ctx.interner.intern("sortedArrayDescending"),
                        ]
                    ),
                    "Expected \(arrayName).sortedArrayDescending to be registered"
                )
                XCTAssertEqual(sema.symbols.externalLinkName(for: symbolID), "kk_array_sortedArrayDescending")

                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
                XCTAssertTrue(signature.parameterTypes.isEmpty, "\(arrayName).sortedArrayDescending should take no parameters")
                let receiverType = try XCTUnwrap(signature.receiverType)
                XCTAssertEqual(signature.returnType, receiverType, "\(arrayName).sortedArrayDescending should return the same array type")
                XCTAssertTrue(signature.valueParameterHasDefaultValues.isEmpty)
                XCTAssertTrue(signature.valueParameterIsVararg.isEmpty)
            }
        }
    }

    func testArraySliceArrayOverloadsUseRuntimeExternalLinks() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols.lookupAll(
                fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("Array"),
                    ctx.interner.intern("sliceArray"),
                ]
            )
            let links = Set(symbols.compactMap { sema.symbols.externalLinkName(for: $0) })
            XCTAssertTrue(links.contains("kk_array_sliceArray_range"))
            XCTAssertTrue(links.contains("kk_array_sliceArray_iterable"))

            for linkName in ["kk_array_sliceArray_range", "kk_array_sliceArray_iterable"] {
                let symbolID = try XCTUnwrap(
                    symbols.first(where: { sema.symbols.externalLinkName(for: $0) == linkName }),
                    "Expected Array.sliceArray overload linked to \(linkName)"
                )
                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
                XCTAssertEqual(signature.parameterTypes.count, 1)
                let receiverType = try XCTUnwrap(signature.receiverType)
                XCTAssertEqual(signature.returnType, receiverType)
                XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
                XCTAssertEqual(signature.valueParameterIsVararg, [false])
                XCTAssertEqual(signature.typeParameterSymbols.count, 1)
            }
        }
    }

    func testPrimitiveArraySliceArrayOverloadsUseRuntimeExternalLinks() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
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
                let symbols = sema.symbols.lookupAll(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern(arrayName),
                        ctx.interner.intern("sliceArray"),
                    ]
                )
                let links = Set(symbols.compactMap { sema.symbols.externalLinkName(for: $0) })
                XCTAssertTrue(links.contains("kk_array_sliceArray_range"), "\(arrayName) missing range sliceArray")
                XCTAssertTrue(links.contains("kk_array_sliceArray_iterable"), "\(arrayName) missing iterable sliceArray")

                for linkName in ["kk_array_sliceArray_range", "kk_array_sliceArray_iterable"] {
                    let symbolID = try XCTUnwrap(
                        symbols.first(where: { sema.symbols.externalLinkName(for: $0) == linkName }),
                        "Expected \(arrayName).sliceArray overload linked to \(linkName)"
                    )
                    let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
                    XCTAssertEqual(signature.parameterTypes.count, 1, "\(arrayName).sliceArray should take one parameter")
                    let receiverType = try XCTUnwrap(signature.receiverType)
                    XCTAssertEqual(signature.returnType, receiverType, "\(arrayName).sliceArray should return the same array type")
                    XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
                    XCTAssertEqual(signature.valueParameterIsVararg, [false])
                }
            }
        }
    }

    func testPrimitiveArrayCopyIntoOverloadsUseRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
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
                let symbolID = try XCTUnwrap(
                    sema.symbols.lookup(
                        fqName: [
                            ctx.interner.intern("kotlin"),
                            ctx.interner.intern(arrayName),
                            ctx.interner.intern("copyInto"),
                        ]
                    ),
                    "Expected \(arrayName).copyInto to be registered"
                )
                XCTAssertEqual(sema.symbols.externalLinkName(for: symbolID), "kk_array_copyInto")

                let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
                XCTAssertEqual(signature.parameterTypes.count, 4, "\(arrayName).copyInto should take four parameters")
                let receiverType = try XCTUnwrap(signature.receiverType)
                XCTAssertEqual(signature.returnType, receiverType, "\(arrayName).copyInto should return destination array type")
                XCTAssertEqual(signature.valueParameterHasDefaultValues, [false, true, true, true])
                XCTAssertEqual(signature.valueParameterIsVararg, [false, false, false, false])
            }
        }
    }
}
