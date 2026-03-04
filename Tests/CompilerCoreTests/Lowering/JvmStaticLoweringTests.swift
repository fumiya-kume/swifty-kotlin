@testable import CompilerCore
import Foundation
import XCTest

final class JvmStaticLoweringTests: XCTestCase {
    func testJvmStaticCompanionSourceCreatesStaticWrapperAndRewritesCall() throws {
        let source = """
        class Host {
            companion object {
                @JvmStatic
                fun create(x: Int): Int = x
            }
        }

        fun caller(): Int = Host.create(7)
        """

        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let module = try XCTUnwrap(ctx.kir)
        let interner = ctx.interner

        let hostSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class && interner.resolve(symbol.name) == "Host"
        })?.id)
        let companionSymbol = try XCTUnwrap(sema.symbols.companionObjectSymbol(for: hostSymbol))

        let originalSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            guard symbol.kind == .function,
                  interner.resolve(symbol.name) == "create"
            else {
                return false
            }
            return sema.symbols.parentSymbol(for: symbol.id) == companionSymbol
        })?.id)

        let wrapperSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            guard symbol.kind == .function,
                  interner.resolve(symbol.name) == "create",
                  symbol.flags.contains(.synthetic),
                  symbol.flags.contains(.static)
            else {
                return false
            }
            return sema.symbols.parentSymbol(for: symbol.id) == hostSymbol
        })?.id)

        let wrapperSignature = try XCTUnwrap(sema.symbols.functionSignature(for: wrapperSymbol))
        XCTAssertNil(wrapperSignature.receiverType, "JvmStatic wrapper must be receiver-less")
        XCTAssertEqual(wrapperSignature.parameterTypes.count, 1)

        let callerFunction = try findKIRFunction(named: "caller", in: module, interner: interner)
        XCTAssertFalse(hasCall(to: originalSymbol, in: callerFunction.body), "Caller should not keep direct companion-member call after lowering")
        XCTAssertTrue(hasCall(to: wrapperSymbol, in: callerFunction.body), "Caller should be rewritten to JvmStatic wrapper call")
        let rewrittenCallArgs = callerFunction.body.compactMap { instruction -> [KIRExprID]? in
            guard case let .call(symbol, _, arguments, _, _, _, _) = instruction,
                  symbol == wrapperSymbol
            else {
                return nil
            }
            return arguments
        }
        XCTAssertEqual(
            try XCTUnwrap(rewrittenCallArgs.first).count,
            1,
            "Caller should keep one value argument when rewritten to wrapper call"
        )
    }

    func testJvmStaticLoweringRewritesVirtualCallToStaticWrapperCall() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let bindings = BindingTable()
        let diagnostics = DiagnosticEngine()
        let sema = SemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)

        let hostName = interner.intern("Host")
        let companionName = interner.intern("Companion")
        let createName = interner.intern("create")

        let hostSymbol = symbols.define(
            kind: .class,
            name: hostName,
            fqName: [hostName],
            declSite: nil,
            visibility: .public
        )
        let companionSymbol = symbols.define(
            kind: .object,
            name: companionName,
            fqName: [hostName, companionName],
            declSite: nil,
            visibility: .public
        )
        symbols.setParentSymbol(hostSymbol, for: companionSymbol)
        symbols.setCompanionObjectSymbol(companionSymbol, for: hostSymbol)

        let originalSymbol = symbols.define(
            kind: .function,
            name: createName,
            fqName: [hostName, companionName, createName],
            declSite: nil,
            visibility: .public
        )
        symbols.setParentSymbol(companionSymbol, for: originalSymbol)

        let intType = types.make(.primitive(.int, .nonNull))
        let companionType = types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: companionType,
                parameterTypes: [intType],
                returnType: intType
            ),
            for: originalSymbol
        )
        symbols.setAnnotations(
            [MetadataAnnotationRecord(annotationFQName: "kotlin.jvm.JvmStatic")],
            for: originalSymbol
        )

        let callUserSymbol = symbols.define(
            kind: .function,
            name: interner.intern("callUser"),
            fqName: [interner.intern("callUser")],
            declSite: nil,
            visibility: .public
        )
        let virtualUserSymbol = symbols.define(
            kind: .function,
            name: interner.intern("virtualUser"),
            fqName: [interner.intern("virtualUser")],
            declSite: nil,
            visibility: .public
        )

        let arena = KIRArena()

        let receiverParam = KIRParameter(symbol: SymbolID(rawValue: 7000), type: companionType)
        let valueParam = KIRParameter(symbol: SymbolID(rawValue: 7001), type: intType)
        let originalRet = arena.appendExpr(.symbolRef(valueParam.symbol), type: intType)
        let originalFn = KIRFunction(
            symbol: originalSymbol,
            name: createName,
            params: [receiverParam, valueParam],
            returnType: intType,
            body: [.returnValue(originalRet)],
            isSuspend: false,
            isInline: false
        )

        let callRecv = arena.appendExpr(.temporary(0), type: companionType)
        let callArg = arena.appendExpr(.temporary(1), type: intType)
        let callResult = arena.appendExpr(.temporary(2), type: intType)
        let callUserFn = KIRFunction(
            symbol: callUserSymbol,
            name: interner.intern("callUser"),
            params: [],
            returnType: intType,
            body: [
                .constValue(result: callRecv, value: .symbolRef(companionSymbol)),
                .constValue(result: callArg, value: .intLiteral(11)),
                .call(symbol: originalSymbol, callee: createName, arguments: [callRecv, callArg], result: callResult, canThrow: false, thrownResult: nil),
                .returnValue(callResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let virtualRecv = arena.appendExpr(.temporary(3), type: companionType)
        let virtualArg = arena.appendExpr(.temporary(4), type: intType)
        let virtualResult = arena.appendExpr(.temporary(5), type: intType)
        let virtualUserFn = KIRFunction(
            symbol: virtualUserSymbol,
            name: interner.intern("virtualUser"),
            params: [],
            returnType: intType,
            body: [
                .constValue(result: virtualRecv, value: .symbolRef(companionSymbol)),
                .constValue(result: virtualArg, value: .intLiteral(13)),
                .virtualCall(
                    symbol: originalSymbol,
                    callee: createName,
                    receiver: virtualRecv,
                    arguments: [virtualArg],
                    result: virtualResult,
                    canThrow: false,
                    thrownResult: nil,
                    dispatch: .vtable(slot: 0)
                ),
                .returnValue(virtualResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let originalID = arena.appendDecl(.function(originalFn))
        let callUserID = arena.appendDecl(.function(callUserFn))
        let virtualUserID = arena.appendDecl(.function(virtualUserFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [originalID, callUserID, virtualUserID])], arena: arena)

        let options = CompilerOptions(
            moduleName: "JvmStaticLoweringManual",
            inputs: [],
            outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let kirCtx = KIRContext(
            diagnostics: diagnostics,
            options: options,
            interner: interner,
            sema: sema
        )

        let pass = JvmStaticLoweringPass()
        XCTAssertTrue(pass.shouldRun(module: module, ctx: kirCtx))
        try pass.run(module: module, ctx: kirCtx)

        let wrapperSymbol = try XCTUnwrap(symbols.allSymbols().first(where: { symbol in
            guard symbol.kind == .function,
                  interner.resolve(symbol.name) == "create",
                  symbol.flags.contains(.synthetic),
                  symbol.flags.contains(.static)
            else {
                return false
            }
            return symbols.parentSymbol(for: symbol.id) == hostSymbol
        })?.id)

        let wrapperFn = try XCTUnwrap(module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case let .function(function) = decl else {
                return nil
            }
            return function.symbol == wrapperSymbol ? function : nil
        }.first)
        XCTAssertEqual(wrapperFn.params.count, 1)
        XCTAssertTrue(hasCall(to: originalSymbol, in: wrapperFn.body), "Wrapper should forward to original companion member")

        let loweredCallUser = try XCTUnwrap(module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case let .function(function) = decl else {
                return nil
            }
            return function.symbol == callUserSymbol ? function : nil
        }.first)
        XCTAssertFalse(hasCall(to: originalSymbol, in: loweredCallUser.body))
        XCTAssertTrue(hasCall(to: wrapperSymbol, in: loweredCallUser.body))

        let loweredVirtualUser = try XCTUnwrap(module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case let .function(function) = decl else {
                return nil
            }
            return function.symbol == virtualUserSymbol ? function : nil
        }.first)

        let hasOriginalVirtual = loweredVirtualUser.body.contains { instruction in
            guard case let .virtualCall(symbol, _, _, _, _, _, _, _) = instruction else {
                return false
            }
            return symbol == originalSymbol
        }
        XCTAssertFalse(hasOriginalVirtual, "virtualCall to original symbol should be rewritten")
        XCTAssertTrue(hasCall(to: wrapperSymbol, in: loweredVirtualUser.body), "virtualCall should become static wrapper .call")
    }

    private func hasCall(to symbol: SymbolID, in body: [KIRInstruction]) -> Bool {
        body.contains { instruction in
            guard case let .call(calleeSymbol, _, _, _, _, _, _) = instruction else {
                return false
            }
            return calleeSymbol == symbol
        }
    }
}
