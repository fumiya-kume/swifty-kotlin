#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-1512/KSP-1513: primitive-array and generic-array conversions are bundled
/// Kotlin declarations with private runtime bridges.
@Suite(.serialized)
struct PrimitiveArrayConversionSourceMigrationTests {
    @Test
    func signedPrimitiveArraySizeAndToListResolveToBundledSource() throws {
        let source = """
        fun exercise(
            ints: IntArray,
            longs: LongArray,
            shorts: ShortArray,
            bytes: ByteArray,
            chars: CharArray,
            booleans: BooleanArray,
            doubles: DoubleArray,
            floats: FloatArray
        ) {
            ints.size
            ints.toList()
            longs.size
            longs.toList()
            shorts.size
            shorts.toList()
            bytes.size
            bytes.toList()
            chars.size
            chars.toList()
            booleans.size
            booleans.toList()
            doubles.size
            doubles.toList()
            floats.size
            floats.toList()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected signed primitive-array members to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let signedTypes: Set<String> = [
                "IntArray", "LongArray", "ShortArray", "ByteArray",
                "CharArray", "BooleanArray", "DoubleArray", "FloatArray",
            ]

            for memberName in ["size", "toList"] {
                var calls: [(ExprID, SymbolID, String)] = []
                for index in ast.arena.exprs.indices {
                    let exprID = ExprID(rawValue: Int32(index))
                    guard case let .memberCall(receiver, callee, _, args, range) = ast.arena.expr(exprID),
                          ctx.interner.resolve(callee) == memberName,
                          args.isEmpty,
                          ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_") == false,
                          let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee,
                          let receiverType = sema.bindings.exprType(for: receiver),
                          let (_, receiverSymbol) = resolveClassTypeSymbol(receiverType, sema: sema)
                    else { continue }
                    calls.append((exprID, chosenCallee, ctx.interner.resolve(receiverSymbol.name)))
                }

                #expect(calls.count == signedTypes.count, "Expected one user call for each signed array type: \(memberName)")
                let receiverNames = Set(calls.map { $0.2 })
                #expect(receiverNames == signedTypes, "Expected all signed array receiver types for \(memberName), got: \(receiverNames)")
                for (exprID, chosenCallee, _) in calls {
                    #expect(sema.symbols.isSourceBackedSymbol(chosenCallee), "Expected \(memberName) call \(exprID) to be source-backed")
                    #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected \(memberName) call \(exprID) to have no public runtime link")
                    if memberName == "size" {
                        #expect(sema.bindings.exprType(for: exprID) == sema.types.intType)
                    }
                }
            }
        }
    }

    @Test
    func unsignedAndGenericArrayMembersResolveToBundledSource() throws {
        let source = """
        fun exercise(
            ubytes: UByteArray,
            ushorts: UShortArray,
            uints: UIntArray,
            ulongs: ULongArray,
            objects: Array<Int>
        ) {
            val ubyteSize: Int = ubytes.size
            val ubyteCopy: List<UByte> = ubytes.toList()
            val ubyteView: List<UByte> = ubytes.asList()
            val ushortSize: Int = ushorts.size
            val ushortCopy: List<UShort> = ushorts.toList()
            val ushortView: List<UShort> = ushorts.asList()
            val uintSize: Int = uints.size
            val uintCopy: List<UInt> = uints.toList()
            val uintView: List<UInt> = uints.asList()
            val ulongSize: Int = ulongs.size
            val ulongCopy: List<ULong> = ulongs.toList()
            val ulongView: List<ULong> = ulongs.asList()
            val objectSize: Int = objects.size
            val objectCopy: List<Int> = objects.toList()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected unsigned and generic array members to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let expectedMembers: Set<String> = [
                "UByteArray.size", "UByteArray.toList", "UByteArray.asList",
                "UShortArray.size", "UShortArray.toList", "UShortArray.asList",
                "UIntArray.size", "UIntArray.toList", "UIntArray.asList",
                "ULongArray.size", "ULongArray.toList", "ULongArray.asList",
                "Array.size", "Array.toList",
            ]
            var observedMembers: Set<String> = []

            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard case let .memberCall(receiver, callee, _, args, range) = ast.arena.expr(exprID),
                      args.isEmpty,
                      ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_") == false,
                      let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee
                          ?? sema.bindings.identifierSymbol(for: exprID),
                      let receiverType = sema.bindings.exprType(for: receiver),
                      let (_, receiverSymbol) = resolveClassTypeSymbol(receiverType, sema: sema)
                else { continue }
                let key = "\(ctx.interner.resolve(receiverSymbol.name)).\(ctx.interner.resolve(callee))"
                guard expectedMembers.contains(key) else { continue }
                observedMembers.insert(key)
                #expect(sema.symbols.isSourceBackedSymbol(chosenCallee), "Expected \(key) to resolve to bundled source")
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected \(key) to have no public runtime link")
                if ctx.interner.resolve(callee) == "size" {
                    #expect(sema.bindings.exprType(for: exprID) == sema.types.intType)
                }
            }

            #expect(observedMembers == expectedMembers, "Unexpected unsigned/generic array members: \(observedMembers)")
        }
    }

    @Test
    func arrayConversionMembersResolveToBundledSource() throws {
        let source = """
        fun exercise(
            objects: Array<Int>,
            ints: IntArray,
            longs: LongArray,
            shorts: ShortArray,
            bytes: ByteArray,
            chars: CharArray,
            booleans: BooleanArray,
            doubles: DoubleArray,
            floats: FloatArray,
            ubytes: UByteArray,
            ushorts: UShortArray,
            uints: UIntArray,
            ulongs: ULongArray
        ) {
            objects.sliceArray(1..2)
            objects.sliceArray(listOf(2, 0))
            objects.reversedArray()
            objects.asList()

            ints.sliceArray(1..2)
            ints.sliceArray(listOf(2, 0))
            ints.reversedArray()
            ints.asList()
            ints.toTypedArray()

            longs.sliceArray(1..2)
            longs.sliceArray(listOf(2, 0))
            longs.reversedArray()
            longs.asList()
            longs.toTypedArray()

            shorts.sliceArray(1..2)
            shorts.sliceArray(listOf(2, 0))
            shorts.reversedArray()
            shorts.asList()
            shorts.toTypedArray()

            bytes.sliceArray(1..2)
            bytes.sliceArray(listOf(2, 0))
            bytes.reversedArray()
            bytes.asList()
            bytes.toTypedArray()

            chars.sliceArray(1..2)
            chars.sliceArray(listOf(2, 0))
            chars.reversedArray()
            chars.asList()
            chars.toTypedArray()

            booleans.sliceArray(1..2)
            booleans.sliceArray(listOf(2, 0))
            booleans.reversedArray()
            booleans.asList()
            booleans.toTypedArray()

            doubles.sliceArray(1..2)
            doubles.sliceArray(listOf(2, 0))
            doubles.reversedArray()
            doubles.asList()
            doubles.toTypedArray()

            floats.sliceArray(1..2)
            floats.sliceArray(listOf(2, 0))
            floats.reversedArray()
            floats.asList()
            floats.toTypedArray()

            ubytes.sliceArray(1..2)
            ubytes.sliceArray(listOf(2, 0))
            ubytes.reversedArray()
            ubytes.asList()
            ubytes.toTypedArray()

            ushorts.sliceArray(1..2)
            ushorts.sliceArray(listOf(2, 0))
            ushorts.reversedArray()
            ushorts.asList()
            ushorts.toTypedArray()

            uints.sliceArray(1..2)
            uints.sliceArray(listOf(2, 0))
            uints.reversedArray()
            uints.asList()
            uints.toTypedArray()

            ulongs.sliceArray(1..2)
            ulongs.sliceArray(listOf(2, 0))
            ulongs.reversedArray()
            ulongs.asList()
            ulongs.toTypedArray()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected array conversion members to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let expectedArrayNames = [
                "Array", "IntArray", "LongArray", "ShortArray", "ByteArray",
                "CharArray", "BooleanArray", "DoubleArray", "FloatArray",
                "UByteArray", "UShortArray", "UIntArray", "ULongArray",
            ]
            var observedCounts: [String: Int] = [:]

            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard case let .memberCall(receiver, callee, _, _, range) = ast.arena.expr(exprID),
                      ["sliceArray", "reversedArray", "asList", "toTypedArray"].contains(ctx.interner.resolve(callee)),
                      ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_") == false,
                      let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee,
                      let receiverType = sema.bindings.exprType(for: receiver),
                      let (_, receiverSymbol) = resolveClassTypeSymbol(receiverType, sema: sema)
                else { continue }

                let receiverName = ctx.interner.resolve(receiverSymbol.name)
                let memberName = ctx.interner.resolve(callee)
                guard expectedArrayNames.contains(receiverName) else { continue }
                let key = "\(receiverName).\(memberName)"
                observedCounts[key, default: 0] += 1
                #expect(sema.symbols.isSourceBackedSymbol(chosenCallee), "Expected \(key) to resolve to bundled source")
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected \(key) to have no public runtime link")
            }

            var expectedCounts: [String: Int] = [:]
            for receiverName in expectedArrayNames {
                expectedCounts["\(receiverName).sliceArray"] = 2
                expectedCounts["\(receiverName).reversedArray"] = 1
                expectedCounts["\(receiverName).asList"] = 1
                if receiverName != "Array" {
                    expectedCounts["\(receiverName).toTypedArray"] = 1
                }
            }
            #expect(observedCounts == expectedCounts, "Unexpected array conversion calls: \(observedCounts)")
        }
    }
}
#endif
