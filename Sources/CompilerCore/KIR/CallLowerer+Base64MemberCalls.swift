/// Base64 member-call lowerings (kotlin.io.encoding.Base64.* helpers).
///
/// Split out from `CallLowerer+MemberCalls.swift`.
extension CallLowerer {
    func tryLowerBase64MemberCall(
        receiverExpr: ExprID,
        loweredReceiverID: KIRExprID,
        calleeName: InternedString,
        chosenCallee: SymbolID?,
        argExprIDs: [ExprID],
        loweredArgIDs: [KIRExprID],
        argInstructionStart: Int,
        result: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> Bool {
        let isResolvedBase64SyntheticMember = chosenCallee.map {
            isBase64SyntheticMemberSymbol(
                $0,
                sema: sema,
                interner: interner
            )
        } ?? true
        guard loweredArgIDs.count == 1,
              isResolvedBase64SyntheticMember,
              let receiverType = sema.bindings.exprTypes[receiverExpr],
              let receiverKind = base64RuntimeReceiverKind(
                  for: receiverType,
                  loweredReceiverID: loweredReceiverID,
                  arena: arena,
                  sema: sema,
                  interner: interner
              )
        else {
            return false
        }

        let callee = interner.resolve(calleeName)
        if callee == "withPadding" {
            let paddingArg: KIRExprID
            let rawPaddingValue = argExprIDs.first.flatMap {
                base64PaddingOptionRawValue(forExpr: $0, sema: sema, interner: interner)
            } ?? {
                guard case let .symbolRef(symbolID) = arena.expr(loweredArgIDs[0]) else {
                    return nil
                }
                return base64PaddingOptionRawValue(forSymbol: symbolID, sema: sema, interner: interner)
            }()
            if let rawValue = rawPaddingValue {
                if argInstructionStart < instructions.count {
                    instructions.removeSubrange(argInstructionStart ..< instructions.count)
                }
                paddingArg = arena.appendExpr(.intLiteral(Int64(rawValue)), type: sema.types.intType)
                instructions.append(.constValue(result: paddingArg, value: .intLiteral(Int64(rawValue))))
            } else {
                paddingArg = arena.appendExpr(
                    .temporary(Int32(arena.expressions.count)),
                    type: sema.types.intType
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_unbox_int"),
                    arguments: [loweredArgIDs[0]],
                    result: paddingArg,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            switch receiverKind {
            case .variant(let suffix):
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_base64_withPadding_\(suffix)"),
                    arguments: [paddingArg],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            case .instance:
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_base64_withPadding_instance"),
                    arguments: [loweredReceiverID, paddingArg],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            return true
        }

        let operation: String
        let canThrow: Bool
        switch callee {
        case "encode":
            operation = "encode"
            canThrow = false
        case "decode":
            operation = "decode"
            canThrow = true
        case "encodeToByteArray":
            operation = "encodeToByteArray"
            canThrow = false
        case "decodeFromByteArray":
            operation = "decodeFromByteArray"
            canThrow = true
        default:
            return false
        }

        switch receiverKind {
        case .variant(let suffix):
            let paddingPresent = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
            instructions.append(.constValue(result: paddingPresent, value: .intLiteral(0)))
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_base64_\(operation)_\(suffix)"),
                arguments: [loweredArgIDs[0], paddingPresent],
                result: result,
                canThrow: canThrow,
                thrownResult: nil
            ))
        case .instance:
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_base64_\(operation)_instance"),
                arguments: [loweredReceiverID, loweredArgIDs[0]],
                result: result,
                canThrow: canThrow,
                thrownResult: nil
            ))
        }
        return true
    }

    func isBase64SyntheticMemberSymbol(
        _ symbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let symbolInfo = sema.symbols.symbol(symbol),
              symbolInfo.flags.contains(.synthetic),
              let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
              let ownerInfo = sema.symbols.symbol(ownerSymbol),
              ownerInfo.kind == .class || ownerInfo.kind == .object,
              let externalLink = sema.symbols.externalLinkName(for: symbol),
              externalLink.hasPrefix("kk_base64_"),
              !externalLink.hasSuffix("_fn")
        else {
            return false
        }

        let ownerFQName = ownerInfo.fqName.map { interner.resolve($0) }
        let base64FQName = ["kotlin", "io", "encoding", "Base64"]
        return ownerFQName == base64FQName
            || (ownerFQName.count == base64FQName.count + 1
                && Array(ownerFQName.prefix(base64FQName.count)) == base64FQName)
    }

    enum Base64RuntimeReceiverKind {
        case variant(String)
        case instance
    }

    func base64RuntimeReceiverKind(
        for receiverType: TypeID,
        loweredReceiverID: KIRExprID,
        arena: KIRArena,
        sema: SemaModule,
        interner: StringInterner
    ) -> Base64RuntimeReceiverKind? {
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        switch sema.types.kind(of: nonNullReceiver) {
        case let .classType(classType):
            guard let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                return nil
            }

            let fqName = symbol.fqName.map { interner.resolve($0) }
            let base64FQName = ["kotlin", "io", "encoding", "Base64"]
            if fqName == base64FQName {
                return .instance
            }
            if let suffix = base64RuntimeVariantSuffix(forSymbol: classType.classSymbol, sema: sema, interner: interner) {
                return .variant(suffix)
            }
            return nil
        case let .typeParam(typeParam):
            guard let base64Symbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("io"),
                interner.intern("encoding"),
                interner.intern("Base64"),
            ]),
                  let base64Info = sema.symbols.symbol(base64Symbol),
                  base64Info.kind == .class
            else {
                return nil
            }
            let base64Type = sema.types.make(.classType(ClassType(
                classSymbol: base64Symbol,
                args: [],
                nullability: .nonNull
            )))
            guard sema.symbols.typeParameterUpperBounds(for: typeParam.symbol).contains(where: {
                sema.types.isSubtype(sema.types.makeNonNullable($0), base64Type)
            }) else {
                return nil
            }
            return .instance
        default:
            return nil
        }
    }

    func base64RuntimeVariantSuffix(
        forSymbol symbolID: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> String? {
        guard let symbol = sema.symbols.symbol(symbolID) else {
            return nil
        }
        let fqName = symbol.fqName.map { interner.resolve($0) }
        let base64FQName = ["kotlin", "io", "encoding", "Base64"]
        guard fqName.count == base64FQName.count + 1,
              Array(fqName.prefix(base64FQName.count)) == base64FQName
        else {
            return nil
        }

        switch fqName.last {
        case "Default":
            return "default"
        case "UrlSafe":
            return "urlsafe"
        case "Mime", "Pem":
            return "mime"
        default:
            return nil
        }
    }

    func base64PaddingOptionRawValue(
        forExpr exprID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Int? {
        guard let symbolID = sema.bindings.identifierSymbol(for: exprID)
        else {
            return nil
        }
        return base64PaddingOptionRawValue(forSymbol: symbolID, sema: sema, interner: interner)
    }

    func base64PaddingOptionRawValue(
        forSymbol symbolID: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Int? {
        guard let symbol = sema.symbols.symbol(symbolID) else {
            return nil
        }
        let fqName = symbol.fqName.map { interner.resolve($0) }
        guard fqName.count == 6,
              Array(fqName.prefix(5)) == ["kotlin", "io", "encoding", "Base64", "PaddingOption"]
        else {
            return nil
        }
        switch fqName.last {
        case "PRESENT":
            return 0
        case "ABSENT":
            return 1
        case "PRESENT_OPTIONAL":
            return 2
        case "ABSENT_OPTIONAL":
            return 3
        default:
            return nil
        }
    }
}
