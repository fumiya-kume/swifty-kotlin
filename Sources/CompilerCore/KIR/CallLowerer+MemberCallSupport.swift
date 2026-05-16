import Foundation

struct MemberCallReceiver {
    let expr: ExprID
    let loweredID: KIRExprID
}

extension CallLowerer {
    static let unresolvedCoroutineHandleMemberNames: Set<String> = [
        "await", "join", "awaitCompletion",
        "cancel", "complete", "completeExceptionally",
        "isActive", "isCompleted", "isCancelled"
    ]
    static let unresolvedChannelMemberNames: Set<String> = ["send", "receive", "close", "isClosedForReceive", "isClosedForSend"]

    enum PrimitiveCompareABIKind: Int32 {
        case int = 0
        case long = 1
        case uint = 2
        case ulong = 3
        case boolean = 4
        case char = 5
        case float = 6
        case double = 7
    }

    func primitiveCompareABIKind(for type: TypeID, sema: SemaModule) -> PrimitiveCompareABIKind? {
        switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
        case .primitive(.int, _), .primitive(.ubyte, _), .primitive(.ushort, _):
            return .int
        case .primitive(.long, _):
            return .long
        case .primitive(.uint, _):
            return .uint
        case .primitive(.ulong, _):
            return .ulong
        case .primitive(.boolean, _):
            return .boolean
        case .primitive(.char, _):
            return .char
        case .primitive(.float, _):
            return .float
        case .primitive(.double, _):
            return .double
        default:
            return nil
        }
    }

    func anyFallbackTag(for type: TypeID, sema: SemaModule) -> Int64 {
        switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
        case .primitive(.boolean, _):
            2
        case .primitive(.string, _):
            3
        case .primitive(.char, _):
            4
        case .primitive(.float, _):
            5
        case .primitive(.double, _):
            6
        default:
            1
        }
    }

    func isCoroutineHandleReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isCoroutineHandleSymbol(symbol)
    }

    func isChannelReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return knownNames.isChannelSymbol(symbol)
    }

    func isCoroutineContextReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        guard interner.resolve(symbol.name) == "CoroutineContext" else {
            return false
        }
        let kotlinxCoroutinesPkg: [InternedString] = [
            interner.intern("kotlinx"),
            interner.intern("coroutines"),
        ]
        let kotlinCoroutinesPkg: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("coroutines"),
        ]
        return symbol.fqName.starts(with: kotlinxCoroutinesPkg)
            || symbol.fqName.starts(with: kotlinCoroutinesPkg)
    }
    static let unresolvedCollectionMemberNames: Set<String> = [
        "size", "get", "contains", "containsAll", "containsKey", "containsValue",
        "isEmpty", "first", "last", "indexOf", "lastIndexOf", "indexOfFirst", "indexOfLast",
        "count", "iterator",
        "map", "filter", "filterNot", "mapNotNull", "mapIndexedNotNullTo", "firstNotNullOf", "firstNotNullOfOrNull", "filterNotNull", "requireNoNulls", "forEach", "flatMap",
        "any", "none", "all",
        "fold", "foldIndexed", "foldRight", "foldRightIndexed",
        "reduce", "reduceRight", "reduceRightOrNull", "reduceRightIndexed", "reduceRightIndexedOrNull", "reduceIndexed", "reduceIndexedOrNull",
        "scan", "scanIndexed", "scanReduce", "runningFold", "runningFoldIndexed",
        "runningReduce", "runningReduceIndexed",
        "groupBy", "groupingBy", "sortedBy", "find", "findLast", "associateBy", "associateWith", "associate", "zip", "zipWithNext", "unzip",
        "eachCount", "eachCountTo", "aggregate", "aggregateTo",
        "withIndex", "forEachIndexed", "mapIndexed", "mapIndexedNotNull", "filterIndexed", "mapValues", "mapValuesTo", "mapKeys", "mapKeysTo", "filterKeys", "filterValues",
        "getValue", "getOrDefault", "getOrElse", "getOrPut", "getOrNull", "elementAtOrNull", "elementAt", "elementAtOrElse",
        "putAll", "addAll",
        "maxBy", "minBy", "max", "min", "maxByOrNull", "minByOrNull", "maxOfOrNull", "minOfOrNull", "maxOrNull", "minOrNull",
        "plus", "plusElement", "minus", "minusElement",
        "asSequence", "asIterable", "toList", "toSet", "toMap", "toCollection", "toMutableList", "toMutableSet", "toTypedArray",
        "toBooleanArray", "toCharArray", "toShortArray", "toDoubleArray", "toFloatArray", "toIntArray", "toLongArray", "toByteArray", "toUByteArray", "toUShortArray", "toUIntArray", "toULongArray",
        "take", "takeWhile", "takeLast", "drop", "reversed", "asReversed", "sorted", "distinct", "flatten", "chunked", "windowed", "collect", "subList",
        "sortedDescending", "sortedByDescending", "sortedWith", "partition",
        "sortedArrayWith",
        "maxWith", "maxWithOrNull", "minWith", "minWithOrNull",
        "maxOf", "minOf",
        "maxOfWith", "maxOfWithOrNull", "minOfWith", "minOfWithOrNull",
        "replaceFirstChar",
        "sort", "sortWith", "sortBy", "sortByDescending",
        "onEach", "onEachIndexed",
        "copyOf", "copyOfRange", "fill", "replaceAll", "removeIf",
        "firstOrNull", "lastOrNull", "singleOrNull",
        "addAll", "removeAll", "retainAll",
        "intersect", "union", "subtract",
        "toHashSet",
        "containsAll", "binarySearch", "average",
        "addFirst", "addLast",
        "sum", "sumOf", "sumBy", "sumByDouble",
        "to", // FUNC-002
    ]

}
