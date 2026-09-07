#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1537: Long.toChar() is backed by bundled Kotlin source while the other
/// Long numeric conversions remain compiler/runtime-owned residuals.
@Suite
struct LongConversionMemberCallTests {
    @Test
    func longToCharResolvesThroughBundledKotlin() throws {
        let ctx = makeContextFromSource("""
        @Suppress("DEPRECATION")
        fun longToChar(value: Long): Char = value.toChar()
        """)

        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected Long.toChar() to type-check, got: \(ctx.diagnostics.diagnostics)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        var userCall: (ExprID, SymbolID)?
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, name, _, _, range) = expr,
                  ctx.interner.resolve(name) == "toChar",
                  !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_"),
                  let binding = sema.bindings.callBinding(for: exprID)
            else {
                continue
            }
            userCall = (exprID, binding.chosenCallee)
            break
        }

        let (_, chosenCallee) = try #require(userCall)
        #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
        #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
        let sourceFileID = try #require(sema.symbols.sourceFileID(for: chosenCallee))
        #expect(ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/Numbers.kt")

        let residualConversions: [(name: String, result: TypeID, link: String)] = [
            ("toByte", sema.types.byteType, "kk_long_to_byte"),
            ("toDouble", sema.types.doubleType, "kk_long_to_double"),
            ("toFloat", sema.types.floatType, "kk_long_to_float"),
            ("toInt", sema.types.intType, "kk_long_to_int"),
            ("toShort", sema.types.shortType, "kk_long_to_short"),
            ("toUByte", sema.types.ubyteType, "kk_long_to_ubyte"),
            ("toUInt", sema.types.uintType, "kk_long_to_uint"),
            ("toULong", sema.types.ulongType, "kk_long_to_ulong"),
            ("toUShort", sema.types.ushortType, "kk_long_to_ushort"),
        ]
        for conversion in residualConversions {
            let candidates = sema.symbols.lookupAll(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern(conversion.name),
            ])
            let residual = candidates.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.longType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == conversion.result
            }
            let symbol = try #require(residual, "Expected Long.\(conversion.name) residual")
            #expect(sema.symbols.externalLinkName(for: symbol) == conversion.link)
        }
    }
}
#endif
