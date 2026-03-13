import Foundation

enum KnownCompilerAnnotation {
    case deprecated
    case jvmStatic
    case jvmName
    case suppress

    var simpleName: String {
        switch self {
        case .deprecated:
            "Deprecated"
        case .jvmStatic:
            "JvmStatic"
        case .jvmName:
            "JvmName"
        case .suppress:
            "Suppress"
        }
    }

    var qualifiedName: String {
        switch self {
        case .deprecated:
            "kotlin.Deprecated"
        case .jvmStatic:
            "kotlin.jvm.JvmStatic"
        case .jvmName:
            "kotlin.jvm.JvmName"
        case .suppress:
            "kotlin.Suppress"
        }
    }

    func matches(_ rawName: String) -> Bool {
        rawName == simpleName || rawName == qualifiedName
    }
}

enum KnownCollectionKind {
    case list
    case set
    case map
    case collection
    case array
}

struct KnownCompilerNames {
    let interner: StringInterner

    let byte: InternedString
    let short: InternedString
    let int: InternedString
    let long: InternedString
    let float: InternedString
    let double: InternedString
    let boolean: InternedString
    let char: InternedString
    let string: InternedString
    let uint: InternedString
    let ulong: InternedString
    let ubyte: InternedString
    let ushort: InternedString
    let any: InternedString
    let unit: InternedString
    let nothing: InternedString

    let map: InternedString
    let mutableMap: InternedString
    let list: InternedString
    let mutableList: InternedString
    let set: InternedString
    let mutableSet: InternedString
    let collection: InternedString
    let array: InternedString
    let intArray: InternedString
    let longArray: InternedString
    let doubleArray: InternedString
    let booleanArray: InternedString
    let charArray: InternedString

    let regex: InternedString
    let sequence: InternedString
    let channel: InternedString
    let job: InternedString
    let deferred: InternedString
    let dispatchers: InternedString
    let throwable: InternedString
    let exception: InternedString
    let cancellationException: InternedString

    let null: InternedString
    let field: InternedString
    let thisName: InternedString
    let it: InternedString
    let main: InternedString
    let with: InternedString
    let withContext: InternedString
    let flow: InternedString
    let emit: InternedString
    let to: InternedString
    let lazy: InternedString
    let observable: InternedString
    let vetoable: InternedString
    let buildList: InternedString
    let buildMap: InternedString
    let buildSet: InternedString
    let buildString: InternedString
    let className: InternedString
    let isInitialized: InternedString
    let simpleName: InternedString
    let qualifiedName: InternedString
    let size: InternedString
    let isEmpty: InternedString
    let getOrDefault: InternedString
    let getOrElse: InternedString
    let getOrPut: InternedString
    let regexCtor: InternedString
    let runBlocking: InternedString
    let launch: InternedString
    let async: InternedString

    let kotlinRegexFQName: [InternedString]
    let kotlinSequenceFQName: [InternedString]
    let kotlinCollectionsListFQName: [InternedString]
    let kotlinCollectionsMutableListFQName: [InternedString]
    let kotlinCollectionsSetFQName: [InternedString]
    let kotlinCollectionsMutableSetFQName: [InternedString]
    let kotlinCollectionsMapFQName: [InternedString]
    let kotlinCollectionsMutableMapFQName: [InternedString]
    let kotlinCollectionsCollectionFQName: [InternedString]
    let kotlinxCoroutinesJobFQName: [InternedString]
    let kotlinxCoroutinesDeferredFQName: [InternedString]
    let kotlinxCoroutinesChannelFQName: [InternedString]
    let kotlinxCoroutinesFlowFQName: [InternedString]
    let kotlinxCoroutinesRunBlockingFQName: [InternedString]
    let kotlinxCoroutinesLaunchFQName: [InternedString]
    let kotlinxCoroutinesAsyncFQName: [InternedString]

    init(interner: StringInterner) {
        self.interner = interner

        byte = interner.intern("Byte")
        short = interner.intern("Short")
        int = interner.intern("Int")
        long = interner.intern("Long")
        float = interner.intern("Float")
        double = interner.intern("Double")
        boolean = interner.intern("Boolean")
        char = interner.intern("Char")
        string = interner.intern("String")
        uint = interner.intern("UInt")
        ulong = interner.intern("ULong")
        ubyte = interner.intern("UByte")
        ushort = interner.intern("UShort")
        any = interner.intern("Any")
        unit = interner.intern("Unit")
        nothing = interner.intern("Nothing")

        map = interner.intern("Map")
        mutableMap = interner.intern("MutableMap")
        list = interner.intern("List")
        mutableList = interner.intern("MutableList")
        set = interner.intern("Set")
        mutableSet = interner.intern("MutableSet")
        collection = interner.intern("Collection")
        array = interner.intern("Array")
        intArray = interner.intern("IntArray")
        longArray = interner.intern("LongArray")
        doubleArray = interner.intern("DoubleArray")
        booleanArray = interner.intern("BooleanArray")
        charArray = interner.intern("CharArray")

        regex = interner.intern("Regex")
        sequence = interner.intern("Sequence")
        channel = interner.intern("Channel")
        job = interner.intern("Job")
        deferred = interner.intern("Deferred")
        dispatchers = interner.intern("Dispatchers")
        throwable = interner.intern("Throwable")
        exception = interner.intern("Exception")
        cancellationException = interner.intern("CancellationException")

        null = interner.intern("null")
        field = interner.intern("field")
        thisName = interner.intern("this")
        it = interner.intern("it")
        main = interner.intern("main")
        with = interner.intern("with")
        withContext = interner.intern("withContext")
        flow = interner.intern("flow")
        emit = interner.intern("emit")
        to = interner.intern("to")
        lazy = interner.intern("lazy")
        observable = interner.intern("observable")
        vetoable = interner.intern("vetoable")
        buildList = interner.intern("buildList")
        buildMap = interner.intern("buildMap")
        buildSet = interner.intern("buildSet")
        buildString = interner.intern("buildString")
        className = interner.intern("class")
        isInitialized = interner.intern("isInitialized")
        simpleName = interner.intern("simpleName")
        qualifiedName = interner.intern("qualifiedName")
        size = interner.intern("size")
        isEmpty = interner.intern("isEmpty")
        getOrDefault = interner.intern("getOrDefault")
        getOrElse = interner.intern("getOrElse")
        getOrPut = interner.intern("getOrPut")
        regexCtor = interner.intern("Regex")
        runBlocking = interner.intern("runBlocking")
        launch = interner.intern("launch")
        async = interner.intern("async")

        let kotlin = interner.intern("kotlin")
        let kotlinText = interner.intern("text")
        let kotlinCollections = interner.intern("collections")
        let kotlinSequences = interner.intern("sequences")
        let kotlinx = interner.intern("kotlinx")
        let coroutines = interner.intern("coroutines")
        let channels = interner.intern("channels")
        let flowPkg = interner.intern("flow")

        kotlinRegexFQName = [kotlin, kotlinText, regex]
        kotlinSequenceFQName = [kotlin, kotlinSequences, sequence]
        kotlinCollectionsListFQName = [kotlin, kotlinCollections, list]
        kotlinCollectionsMutableListFQName = [kotlin, kotlinCollections, mutableList]
        kotlinCollectionsSetFQName = [kotlin, kotlinCollections, set]
        kotlinCollectionsMutableSetFQName = [kotlin, kotlinCollections, mutableSet]
        kotlinCollectionsMapFQName = [kotlin, kotlinCollections, map]
        kotlinCollectionsMutableMapFQName = [kotlin, kotlinCollections, mutableMap]
        kotlinCollectionsCollectionFQName = [kotlin, kotlinCollections, collection]
        kotlinxCoroutinesJobFQName = [kotlinx, coroutines, job]
        kotlinxCoroutinesDeferredFQName = [kotlinx, coroutines, deferred]
        kotlinxCoroutinesChannelFQName = [kotlinx, coroutines, channels, channel]
        kotlinxCoroutinesFlowFQName = [kotlinx, coroutines, flowPkg, flow]
        kotlinxCoroutinesRunBlockingFQName = [kotlinx, coroutines, runBlocking]
        kotlinxCoroutinesLaunchFQName = [kotlinx, coroutines, launch]
        kotlinxCoroutinesAsyncFQName = [kotlinx, coroutines, async]
    }

    func builtinType(named name: InternedString, nullability: Nullability = .nonNull, types: TypeSystem) -> TypeID? {
        switch name {
        case byte, short, int:
            types.withNullability(nullability, for: types.intType)
        case long:
            types.withNullability(nullability, for: types.longType)
        case float:
            types.withNullability(nullability, for: types.floatType)
        case double:
            types.withNullability(nullability, for: types.doubleType)
        case boolean:
            types.withNullability(nullability, for: types.booleanType)
        case char:
            types.withNullability(nullability, for: types.charType)
        case string:
            types.withNullability(nullability, for: types.stringType)
        case uint:
            types.withNullability(nullability, for: types.uintType)
        case ulong:
            types.withNullability(nullability, for: types.ulongType)
        case ubyte:
            types.withNullability(nullability, for: types.ubyteType)
        case ushort:
            types.withNullability(nullability, for: types.ushortType)
        case any:
            types.withNullability(nullability, for: types.anyType)
        case unit:
            types.unitType
        case nothing:
            types.withNullability(nullability, for: types.nothingType)
        default:
            nil
        }
    }

    func annotationMatches(_ rawName: String, _ annotation: KnownCompilerAnnotation) -> Bool {
        annotation.matches(rawName)
    }

    func symbolMatches(_ symbol: SemanticSymbol, fqName: [InternedString]) -> Bool {
        symbol.fqName == fqName
    }

    func isRegexSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == regex || symbolMatches(symbol, fqName: kotlinRegexFQName)
    }

    func isSequenceSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == sequence || symbolMatches(symbol, fqName: kotlinSequenceFQName)
    }

    func isCoroutineHandleSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == job || symbol.name == deferred
            || symbolMatches(symbol, fqName: kotlinxCoroutinesJobFQName)
            || symbolMatches(symbol, fqName: kotlinxCoroutinesDeferredFQName)
    }

    func isChannelSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == channel || symbolMatches(symbol, fqName: kotlinxCoroutinesChannelFQName)
    }

    func isThrowableCatchAllSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == throwable || symbol.name == exception
    }

    func isCancellationExceptionSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == cancellationException
    }

    func isArrayLikeName(_ name: InternedString) -> Bool {
        name == array
            || name == intArray
            || name == longArray
            || name == doubleArray
            || name == booleanArray
            || name == charArray
    }

    func isConcreteListLikeSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == list || symbol.name == mutableList
            || symbolMatches(symbol, fqName: kotlinCollectionsListFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsMutableListFQName)
    }

    func isMapLikeSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == map || symbol.name == mutableMap
            || symbolMatches(symbol, fqName: kotlinCollectionsMapFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsMutableMapFQName)
    }

    func isMutableMapSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == mutableMap || symbolMatches(symbol, fqName: kotlinCollectionsMutableMapFQName)
    }

    func isCollectionLikeSymbol(_ symbol: SemanticSymbol) -> Bool {
        isConcreteListLikeSymbol(symbol)
            || symbol.name == set
            || symbol.name == mutableSet
            || symbol.name == collection
            || symbolMatches(symbol, fqName: kotlinCollectionsSetFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsMutableSetFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsCollectionFQName)
            || isMapLikeSymbol(symbol)
    }

    func collectionKind(of symbol: SemanticSymbol) -> KnownCollectionKind? {
        if isMapLikeSymbol(symbol) {
            return .map
        }
        if symbol.name == set || symbol.name == mutableSet
            || symbolMatches(symbol, fqName: kotlinCollectionsSetFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsMutableSetFQName)
        {
            return .set
        }
        if isArrayLikeName(symbol.name) {
            return .array
        }
        if isConcreteListLikeSymbol(symbol) {
            return .list
        }
        if symbol.name == collection || symbolMatches(symbol, fqName: kotlinCollectionsCollectionFQName) {
            return .collection
        }
        return nil
    }
}
