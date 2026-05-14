enum MemberDispatchReceiverKind: String, Equatable, Hashable {
    case intRange
    case longRange
    case charRange
    case uintRange
    case ulongRange
    case intProgression
    case longProgression
    case charProgression
    case uintProgression
    case ulongProgression
    case iterable
    case list
    case set
    case collection
    case map
    case sequence

    var isCharRangeLike: Bool {
        self == .charRange || self == .charProgression
    }

    var isLongRangeLike: Bool {
        self == .longRange || self == .longProgression
    }

    var isUIntRangeLike: Bool {
        self == .uintRange || self == .uintProgression
    }

    var isULongRangeLike: Bool {
        self == .ulongRange || self == .ulongProgression
    }
}

enum MemberDispatchLambdaShape: String, Equatable, Hashable {
    case none
    case hofLambda
}

struct MemberDispatchKey: Equatable, Hashable {
    let receiverKind: MemberDispatchReceiverKind
    let memberName: String
    let arity: Int
    let lambdaShape: MemberDispatchLambdaShape

    init(
        receiverKind: MemberDispatchReceiverKind,
        memberName: String,
        arity: Int,
        lambdaShape: MemberDispatchLambdaShape = .none
    ) {
        self.receiverKind = receiverKind
        self.memberName = memberName
        self.arity = arity
        self.lambdaShape = lambdaShape
    }
}

enum MemberRuntimeDispatch {
    static func rangeReceiverKind(
        receiverExpr: ExprID,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> MemberDispatchReceiverKind? {
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        let nominalName: String? = {
            guard case let .classType(classType) = sema.types.kind(of: nonNullReceiverType),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                return nil
            }
            return interner.resolve(symbol.name)
        }()

        switch nominalName {
        case "IntProgression":
            return .intProgression
        case "LongProgression":
            return .longProgression
        case "CharProgression":
            return .charProgression
        case "UIntProgression":
            return .uintProgression
        case "ULongProgression":
            return .ulongProgression
        case "IntRange":
            return .intRange
        case "LongRange":
            return .longRange
        case "CharRange":
            return .charRange
        case "UIntRange":
            return .uintRange
        case "ULongRange":
            return .ulongRange
        default:
            break
        }

        guard sema.bindings.isRangeExpr(receiverExpr) else {
            return nil
        }
        if sema.bindings.isCharRangeExpr(receiverExpr) {
            return .charRange
        }
        if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
            return .ulongRange
        }
        if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
            return .uintRange
        }
        if nonNullReceiverType == sema.types.longType {
            return .longRange
        }
        return .intRange
    }

    static func collectionReceiverKind(
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> MemberDispatchReceiverKind? {
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        guard case let .classType(classType) = sema.types.kind(of: nonNullReceiverType),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return nil
        }

        let knownNames = KnownCompilerNames(interner: interner)
        switch knownNames.collectionKind(of: symbol) {
        case .map?:
            return .map
        case .set?:
            return .set
        case .list?:
            return .list
        case .collection?:
            return .collection
        case .sequence?:
            return .sequence
        case .array?, nil:
            break
        }

        if symbol.name == interner.intern("Iterable")
            || symbol.fqName == [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Iterable"),
            ]
        {
            return .iterable
        }
        return nil
    }

    static func rangeRuntimeLinkName(for key: MemberDispatchKey) -> String? {
        let kind = key.receiverKind
        let hasArgument = key.arity > 0

        switch key.memberName {
        case "random":
            if hasArgument {
                if kind.isCharRangeLike { return "kk_char_range_random_random" }
                return rangeRuntimeName(kind: kind, member: "random_random", longMember: "random_random")
            }
            return rangeRuntimeName(kind: kind, member: "random", longMember: "random")
        case "randomOrNull":
            if kind == .charRange {
                return hasArgument ? "kk_char_range_randomOrNull_random" : "kk_char_range_randomOrNull"
            }
            return rangeRuntimeName(
                kind: kind,
                member: hasArgument ? "randomOrNull_random" : "randomOrNull",
                longMember: hasArgument ? "randomOrNull_random" : "randomOrNull"
            )
        case "contains":
            if kind.isULongRangeLike { return "kk_ulong_range_contains" }
            if kind.isUIntRangeLike { return "kk_uint_range_contains" }
            if kind.isLongRangeLike { return "kk_long_range_contains" }
            return "kk_op_contains"
        case "isEmpty":
            return rangeRuntimeName(
                kind: kind,
                member: "isEmpty",
                longMember: "isEmpty",
                charMember: "isEmpty",
                charProgressionUsesChar: true
            )
        case "endExclusive":
            return "kk_range_endExclusive"
        case "sum":
            if kind.isUIntRangeLike { return "kk_uint_range_sum" }
            return "kk_range_sum"
        case "count":
            return rangeRuntimeName(kind: kind, member: "count", longMember: "count")
        case "toList":
            return rangeRuntimeName(
                kind: kind,
                member: "toList",
                longMember: "toList",
                charMember: "toList",
                charProgressionUsesChar: true
            )
        case "toUIntArray":
            return "kk_uint_range_toUIntArray"
        case "toULongArray":
            return "kk_ulong_range_toULongArray"
        case "toLongArray":
            return "kk_long_range_toLongArray"
        case "iterator":
            return rangeRuntimeName(kind: kind, member: "iterator", longMember: "iterator")
        case "forEach":
            return rangeRuntimeName(kind: kind, member: "forEach", longMember: "forEach")
        case "map":
            return rangeRuntimeName(kind: kind, member: "map", longMember: "map")
        case "mapIndexed":
            return rangeRuntimeName(kind: kind, member: "mapIndexed")
        case "mapNotNull":
            return rangeRuntimeName(kind: kind, member: "mapNotNull")
        case "filter":
            return rangeRuntimeName(kind: kind, member: "filter")
        case "filterIndexed":
            return rangeRuntimeName(kind: kind, member: "filterIndexed")
        case "filterNot":
            return rangeRuntimeName(kind: kind, member: "filterNot")
        case "reduce":
            return rangeRuntimeName(kind: kind, member: "reduce")
        case "reduceIndexed":
            return rangeRuntimeName(kind: kind, member: "reduceIndexed")
        case "fold":
            return rangeRuntimeName(kind: kind, member: "fold")
        case "foldIndexed":
            return rangeRuntimeName(kind: kind, member: "foldIndexed")
        case "find":
            return rangeRuntimeName(kind: kind, member: "find")
        case "findLast":
            return rangeRuntimeName(kind: kind, member: "findLast")
        case "first":
            if key.arity > 1 {
                return rangeRuntimeName(kind: kind, member: "first_predicate")
            }
            return rangeRuntimeName(kind: kind, member: "first", longMember: "first")
        case "start":
            return rangeRuntimeName(kind: kind, member: "first", longMember: "first")
        case "firstOrNull":
            if key.arity == 0 {
                return rangeRuntimeName(kind: kind, member: "firstOrNull", longMember: "firstOrNull")
            }
            return rangeRuntimeName(kind: kind, member: "firstOrNull_predicate")
        case "last":
            if key.arity > 1 {
                return rangeRuntimeName(kind: kind, member: "last_predicate")
            }
            return rangeRuntimeName(kind: kind, member: "last", longMember: "last")
        case "end":
            return rangeRuntimeName(kind: kind, member: "last", longMember: "last")
        case "lastOrNull":
            if key.arity == 0 {
                return rangeRuntimeName(kind: kind, member: "lastOrNull", longMember: "lastOrNull")
            }
            return rangeRuntimeName(kind: kind, member: "lastOrNull_predicate")
        case "any":
            return rangeRuntimeName(kind: kind, member: "any")
        case "all":
            return rangeRuntimeName(kind: kind, member: "all")
        case "none":
            return rangeRuntimeName(kind: kind, member: "none")
        case "chunked":
            return rangeRuntimeName(kind: kind, member: "chunked")
        case "windowed":
            return rangeRuntimeName(kind: kind, member: "windowed")
        case "take":
            return rangeRuntimeName(kind: kind, member: "take", longMember: "take", charMember: "take")
        case "drop":
            return rangeRuntimeName(kind: kind, member: "drop", longMember: "drop", charMember: "drop")
        case "average":
            return rangeRuntimeName(kind: kind, member: "average", longMember: "average")
        case "sorted":
            return rangeRuntimeName(kind: kind, member: "sorted", longMember: "sorted", charMember: "sorted")
        case "reversed":
            return rangeRuntimeName(kind: kind, member: "reversed", longMember: "reversed")
        case "step":
            if key.arity <= 1 {
                return rangeRuntimeName(
                    kind: kind,
                    member: "step",
                    longMember: "step",
                    charMember: "step",
                    charProgressionUsesChar: true
                )
            }
            if kind.isULongRangeLike { return "kk_ulong_step" }
            if kind.isUIntRangeLike { return "kk_uint_step" }
            if kind.isCharRangeLike { return "kk_char_range_step" }
            return "kk_op_step"
        default:
            return nil
        }
    }

    static func collectionRuntimeLinkName(for key: MemberDispatchKey) -> String? {
        guard let ownerKind = stdlibSurfaceOwnerKind(for: key.receiverKind) else {
            return nil
        }
        return StdlibSurfaceSpec.collectionHOFMember(
            ownerKind: ownerKind,
            memberName: key.memberName,
            arity: key.arity
        )?.runtimeLinkName
    }

    private static func rangeRuntimeName(
        kind: MemberDispatchReceiverKind,
        member: String,
        longMember: String? = nil,
        charMember: String? = nil,
        charProgressionUsesChar: Bool = false
    ) -> String {
        if (kind == .charRange || (kind == .charProgression && charProgressionUsesChar)), let charMember {
            return "kk_char_range_\(charMember)"
        }
        if kind.isULongRangeLike {
            return "kk_ulong_range_\(member)"
        }
        if kind.isUIntRangeLike {
            return "kk_uint_range_\(member)"
        }
        if kind.isLongRangeLike, let longMember {
            return "kk_long_range_\(longMember)"
        }
        return "kk_range_\(member)"
    }

    private static func stdlibSurfaceOwnerKind(
        for receiverKind: MemberDispatchReceiverKind
    ) -> StdlibSurfaceOwnerKind? {
        switch receiverKind {
        case .map:
            return .map
        case .sequence:
            return .sequence
        case .iterable, .list, .set, .collection:
            return .list
        default:
            return nil
        }
    }
}
