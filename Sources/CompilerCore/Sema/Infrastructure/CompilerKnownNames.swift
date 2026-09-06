
package enum KnownCompilerAnnotation {
    case deprecated
    case deprecatedSinceKotlin
    case replaceWith
    case metadata
    case requiresOptIn
    case target
    case experimentalStdlibApi
    case experimentalVersionOverloading
    case jvmStatic
    case jvmName
    case jvmField
    case jvmOverloads
    case throws_
    case rootThrows
    case suppress
    case dslMarker
    case parameterName
    case publishedApi
    case wasExperimental
    case sinceKotlin
    case introducedAt
    case optIn
    case subclassOptInRequired
    case consistentCopyVisibility
    case exposedCopyVisibility
    case optionalExpectation
    case builderInference
    case experimentalTypeInference
    case overloadResolutionByLambdaReturnType
    case contextFunctionTypeParams
    case unsafeVariance
    case ksSymbolName

    var simpleName: String {
        switch self {
        case .deprecated:
            "Deprecated"
        case .deprecatedSinceKotlin:
            "DeprecatedSinceKotlin"
        case .replaceWith:
            "ReplaceWith"
        case .metadata:
            "Metadata"
        case .requiresOptIn:
            "RequiresOptIn"
        case .target:
            "Target"
        case .experimentalStdlibApi:
            "ExperimentalStdlibApi"
        case .experimentalVersionOverloading:
            "ExperimentalVersionOverloading"
        case .jvmStatic:
            "JvmStatic"
        case .jvmName:
            "JvmName"
        case .jvmField:
            "JvmField"
        case .jvmOverloads:
            "JvmOverloads"
        case .throws_:
            "Throws"
        case .rootThrows:
            "Throws"
        case .suppress:
            "Suppress"
        case .dslMarker:
            "DslMarker"
        case .parameterName:
            "ParameterName"
        case .publishedApi:
            "PublishedApi"
        case .wasExperimental:
            "WasExperimental"
        case .sinceKotlin:
            "SinceKotlin"
        case .introducedAt:
            "IntroducedAt"
        case .optIn:
            "OptIn"
        case .subclassOptInRequired:
            "SubclassOptInRequired"
        case .consistentCopyVisibility:
            "ConsistentCopyVisibility"
        case .exposedCopyVisibility:
            "ExposedCopyVisibility"
        case .optionalExpectation:
            "OptionalExpectation"
        case .builderInference:
            "BuilderInference"
        case .experimentalTypeInference:
            "ExperimentalTypeInference"
        case .overloadResolutionByLambdaReturnType:
            "OverloadResolutionByLambdaReturnType"
        case .contextFunctionTypeParams:
            "ContextFunctionTypeParams"
        case .unsafeVariance:
            "UnsafeVariance"
        case .ksSymbolName:
            "KsSymbolName"
        }
    }

    var qualifiedName: String {
        switch self {
        case .deprecated:
            "kotlin.Deprecated"
        case .deprecatedSinceKotlin:
            "kotlin.DeprecatedSinceKotlin"
        case .replaceWith:
            "kotlin.ReplaceWith"
        case .metadata:
            "kotlin.Metadata"
        case .requiresOptIn:
            "kotlin.RequiresOptIn"
        case .target:
            "kotlin.annotation.Target"
        case .experimentalStdlibApi:
            "kotlin.ExperimentalStdlibApi"
        case .experimentalVersionOverloading:
            "kotlin.ExperimentalVersionOverloading"
        case .jvmStatic:
            "kotlin.jvm.JvmStatic"
        case .jvmName:
            "kotlin.jvm.JvmName"
        case .jvmField:
            "kotlin.jvm.JvmField"
        case .jvmOverloads:
            "kotlin.jvm.JvmOverloads"
        case .throws_:
            "kotlin.jvm.Throws"
        case .rootThrows:
            "kotlin.Throws"
        case .suppress:
            "kotlin.Suppress"
        case .dslMarker:
            "kotlin.DslMarker"
        case .parameterName:
            "kotlin.ParameterName"
        case .publishedApi:
            "kotlin.PublishedApi"
        case .wasExperimental:
            "kotlin.WasExperimental"
        case .sinceKotlin:
            "kotlin.SinceKotlin"
        case .introducedAt:
            "kotlin.IntroducedAt"
        case .optIn:
            "kotlin.OptIn"
        case .subclassOptInRequired:
            "kotlin.SubclassOptInRequired"
        case .consistentCopyVisibility:
            "kotlin.ConsistentCopyVisibility"
        case .exposedCopyVisibility:
            "kotlin.ExposedCopyVisibility"
        case .optionalExpectation:
            "kotlin.OptionalExpectation"
        case .builderInference:
            "kotlin.BuilderInference"
        case .experimentalTypeInference:
            "kotlin.experimental.ExperimentalTypeInference"
        case .overloadResolutionByLambdaReturnType:
            "kotlin.OverloadResolutionByLambdaReturnType"
        case .contextFunctionTypeParams:
            "kotlin.ContextFunctionTypeParams"
        case .unsafeVariance:
            "kotlin.UnsafeVariance"
        case .ksSymbolName:
            "kotlin.internal.KsSymbolName"
        }
    }

    package func matches(_ rawName: String) -> Bool {
        rawName == simpleName || rawName == qualifiedName
    }
}

enum KnownCollectionKind {
    case list
    case set
    case map
    case collection
    case array
    case sequence
}

package struct KnownCompilerNames {

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
    let hashSet: InternedString
    let linkedHashSet: InternedString
    let collection: InternedString
    let mutableCollection: InternedString
    let array: InternedString
    let intArray: InternedString
    let longArray: InternedString
    let shortArray: InternedString
    let byteArray: InternedString
    let ubyteArray: InternedString
    let ushortArray: InternedString
    let ulongArray: InternedString
    let doubleArray: InternedString
    let floatArray: InternedString
    let booleanArray: InternedString
    let charArray: InternedString
    let uintArray: InternedString

    let regex: InternedString
    let stringBuilder: InternedString
    let sequence: InternedString
    let continuation: InternedString
    let suspendCoroutine: InternedString
    let resume: InternedString
    let resumeWith: InternedString
    let resumeWithException: InternedString
    let channel: InternedString
    let job: InternedString
    let deferred: InternedString
    let dispatchers: InternedString
    let charsets: InternedString
    let throwable: InternedString
    let exception: InternedString
    let cancellationException: InternedString

    let null: InternedString
    let field: InternedString
    let thisName: InternedString
    package let main: InternedString
    let with: InternedString
    let run: InternedString
    let withContext: InternedString
    let withTimeout: InternedString
    let withTimeoutOrNull: InternedString
    let suspendCoroutineUninterceptedOrReturn: InternedString
    let flow: InternedString
    let emit: InternedString
    let notNull: InternedString
    let emptyListFn: InternedString
    let emptySetFn: InternedString
    let emptyMapFn: InternedString
    let buildList: InternedString
    let buildSet: InternedString
    let buildMap: InternedString
    let className: InternedString
    let isInitialized: InternedString
    let simpleName: InternedString
    let qualifiedName: InternedString
    let isInstanceName: InternedString
    let membersName: InternedString
    let constructorsName: InternedString
    let primaryConstructorName: InternedString
    // MIGRATION-REFLECT-002: KClass member introspection
    let nestedClassesName: InternedString
    // STDLIB-REFLECT-060: KClass basic reflection features
    let isFinalName: InternedString
    let isOpenName: InternedString
    let isAbstractName: InternedString
    let visibilityName: InternedString
    let typeParametersName: InternedString
    let supertypesName: InternedString
    // STDLIB-REFLECT-067: KClass kind/modifier boolean introspection
    let isDataName: InternedString
    let isSealedName: InternedString
    let isValueName: InternedString
    let isEnumName: InternedString
    let isInterfaceName: InternedString
    let isObjectName: InternedString
    let isInnerName: InternedString
    let isCompanionName: InternedString
    let isFunName: InternedString
    // STDLIB-REFLECT-061: KClass member access
    let propertiesName: InternedString
    let memberPropertiesName: InternedString
    let declaredMemberPropertiesName: InternedString
    let functionsName: InternedString
    let memberFunctionsName: InternedString
    let declaredMemberFunctionsName: InternedString
    // STDLIB-REFLECT-065: Annotation reflection
    let annotationsName: InternedString
    let findAnnotationName: InternedString
    let findAssociatedObjectName: InternedString
    let size: InternedString
    let isEmpty: InternedString
    let getValue: InternedString
    let getOrDefault: InternedString
    let getOrElse: InternedString
    let getOrPut: InternedString
    let putAll: InternedString
    let regexCtor: InternedString
    let runBlocking: InternedString
    let launch: InternedString
    let async: InternedString
    let produce: InternedString

    // Scope function names (STDLIB-004 / STDLIB-250)

    // StringBuilder member names
    let append: InternedString
    let appendLine: InternedString
    let appendRange: InternedString
    let deleteCharAt: InternedString
    let deleteAt: InternedString
    let deleteRange: InternedString
    let get: InternedString
    let sbSet: InternedString
    let insert: InternedString
    let insertRange: InternedString
    let delete: InternedString
    let setRange: InternedString
    let toString: InternedString
    let clear: InternedString
    let reverse: InternedString
    let length: InternedString
    // STDLIB-STR-123
    let replace: InternedString
    let setCharAt: InternedString
    let capacity: InternedString
    let ensureCapacity: InternedString
    let trimToSize: InternedString

    let kotlinRegexFQName: [InternedString]
    let kotlinStringBuilderFQName: [InternedString]
    let kotlinSequenceFQName: [InternedString]
    let kotlinContinuationFQName: [InternedString]
    let kotlinSuspendCoroutineFQName: [InternedString]
    let kotlinCollectionsListFQName: [InternedString]
    let kotlinCollectionsMutableListFQName: [InternedString]
    let kotlinCollectionsSetFQName: [InternedString]
    let kotlinCollectionsMutableSetFQName: [InternedString]
    let kotlinCollectionsHashSetFQName: [InternedString]
    let kotlinCollectionsLinkedHashSetFQName: [InternedString]
    let kotlinCollectionsMapFQName: [InternedString]
    let kotlinCollectionsMutableMapFQName: [InternedString]
    let kotlinCollectionsHashMapFQName: [InternedString]
    let kotlinCollectionsCollectionFQName: [InternedString]
    let kotlinCollectionsMutableCollectionFQName: [InternedString]
    let kotlinEnumsEnumEntriesFQName: [InternedString]
    let kotlinCoroutinesFQName: [InternedString]
    let kotlinCoroutinesIntrinsicsFQName: [InternedString]
    let kotlinxCoroutinesJobFQName: [InternedString]
    let kotlinxCoroutinesDeferredFQName: [InternedString]
    let kotlinxCoroutinesChannelFQName: [InternedString]
    let kotlinxCoroutinesProduceFQName: [InternedString]
    let kotlinxCoroutinesRunBlockingFQName: [InternedString]
    let kotlinxCoroutinesLaunchFQName: [InternedString]
    let kotlinxCoroutinesAsyncFQName: [InternedString]
    let kotlinCoroutinesContinuationFQName: [InternedString]
    let kotlinCoroutinesSuspendCoroutineUninterceptedOrReturnFQName: [InternedString]
    let kotlinResultFQName: [InternedString]
    let atomicScalarFactoryFQNames: Set<[InternedString]>

    package init(interner: StringInterner) {

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
        hashSet = interner.intern("HashSet")
        linkedHashSet = interner.intern("LinkedHashSet")
        collection = interner.intern("Collection")
        mutableCollection = interner.intern("MutableCollection")
        array = interner.intern("Array")
        intArray = interner.intern("IntArray")
        longArray = interner.intern("LongArray")
        shortArray = interner.intern("ShortArray")
        byteArray = interner.intern("ByteArray")
        ubyteArray = interner.intern("UByteArray")
        ushortArray = interner.intern("UShortArray")
        ulongArray = interner.intern("ULongArray")
        doubleArray = interner.intern("DoubleArray")
        floatArray = interner.intern("FloatArray")
        booleanArray = interner.intern("BooleanArray")
        charArray = interner.intern("CharArray")
        uintArray = interner.intern("UIntArray")

        regex = interner.intern("Regex")
        stringBuilder = interner.intern("StringBuilder")
        sequence = interner.intern("Sequence")
        continuation = interner.intern("Continuation")
        suspendCoroutine = interner.intern("suspendCoroutine")
        resume = interner.intern("resume")
        resumeWith = interner.intern("resumeWith")
        resumeWithException = interner.intern("resumeWithException")
        channel = interner.intern("Channel")
        job = interner.intern("Job")
        deferred = interner.intern("Deferred")
        dispatchers = interner.intern("Dispatchers")
        charsets = interner.intern("Charsets")
        throwable = interner.intern("Throwable")
        exception = interner.intern("Exception")
        cancellationException = interner.intern("CancellationException")

        null = interner.intern("null")
        field = interner.intern("field")
        thisName = interner.intern("this")
        main = interner.intern("main")
        with = interner.intern("with")
        run = interner.intern("run")
        withContext = interner.intern("withContext")
        withTimeout = interner.intern("withTimeout")
        withTimeoutOrNull = interner.intern("withTimeoutOrNull")
        suspendCoroutineUninterceptedOrReturn = interner.intern("suspendCoroutineUninterceptedOrReturn")
        flow = interner.intern("flow")
        emit = interner.intern("emit")
        notNull = interner.intern("notNull")
        emptyListFn = interner.intern("emptyList")
        emptySetFn = interner.intern("emptySet")
        emptyMapFn = interner.intern("emptyMap")
        buildList = interner.intern("buildList")
        buildSet = interner.intern("buildSet")
        buildMap = interner.intern("buildMap")
        className = interner.intern("class")
        isInitialized = interner.intern("isInitialized")
        simpleName = interner.intern("simpleName")
        qualifiedName = interner.intern("qualifiedName")
        isInstanceName = interner.intern("isInstance")
        membersName = interner.intern("members")
        constructorsName = interner.intern("constructors")
        primaryConstructorName = interner.intern("primaryConstructor")
        // MIGRATION-REFLECT-002: KClass member introspection
        nestedClassesName = interner.intern("nestedClasses")
        // STDLIB-REFLECT-060: KClass basic reflection features
        isFinalName = interner.intern("isFinal")
        isOpenName = interner.intern("isOpen")
        isAbstractName = interner.intern("isAbstract")
        visibilityName = interner.intern("visibility")
        typeParametersName = interner.intern("typeParameters")
        supertypesName = interner.intern("supertypes")
        // STDLIB-REFLECT-067: KClass kind/modifier boolean introspection
        isDataName = interner.intern("isData")
        isSealedName = interner.intern("isSealed")
        isValueName = interner.intern("isValue")
        isEnumName = interner.intern("isEnum")
        isInterfaceName = interner.intern("isInterface")
        isObjectName = interner.intern("isObject")
        isInnerName = interner.intern("isInner")
        isCompanionName = interner.intern("isCompanion")
        isFunName = interner.intern("isFun")
        // STDLIB-REFLECT-061: KClass member access
        propertiesName = interner.intern("properties")
        memberPropertiesName = interner.intern("memberProperties")
        declaredMemberPropertiesName = interner.intern("declaredMemberProperties")
        functionsName = interner.intern("functions")
        memberFunctionsName = interner.intern("memberFunctions")
        declaredMemberFunctionsName = interner.intern("declaredMemberFunctions")
        // STDLIB-REFLECT-065: Annotation reflection
        annotationsName = interner.intern("annotations")
        findAnnotationName = interner.intern("findAnnotation")
        findAssociatedObjectName = interner.intern("findAssociatedObject")
        size = interner.intern("size")
        isEmpty = interner.intern("isEmpty")
        getValue = interner.intern("getValue")
        getOrDefault = interner.intern("getOrDefault")
        getOrElse = interner.intern("getOrElse")
        getOrPut = interner.intern("getOrPut")
        putAll = interner.intern("putAll")
        regexCtor = interner.intern("Regex")
        runBlocking = interner.intern("runBlocking")
        launch = interner.intern("launch")
        async = interner.intern("async")
        produce = interner.intern("produce")

        // Scope function names (STDLIB-004 / STDLIB-250)

        // StringBuilder member names
        append = interner.intern("append")
        appendLine = interner.intern("appendLine")
        appendRange = interner.intern("appendRange")
        deleteCharAt = interner.intern("deleteCharAt")
        deleteAt = interner.intern("deleteAt")
        deleteRange = interner.intern("deleteRange")
        get = interner.intern("get")
        sbSet = interner.intern("set")
        insert = interner.intern("insert")
        insertRange = interner.intern("insertRange")
        delete = interner.intern("delete")
        setRange = interner.intern("setRange")
        toString = interner.intern("toString")
        clear = interner.intern("clear")
        reverse = interner.intern("reverse")
        length = interner.intern("length")
        // STDLIB-STR-123
        replace = interner.intern("replace")
        setCharAt = interner.intern("setCharAt")
        capacity = interner.intern("capacity")
        ensureCapacity = interner.intern("ensureCapacity")
        trimToSize = interner.intern("trimToSize")

        let kotlin = interner.intern("kotlin")
        let kotlinCoroutines = interner.intern("coroutines")
        let kotlinText = interner.intern("text")
        let kotlinCollections = interner.intern("collections")
        let kotlinSequences = interner.intern("sequences")
        let kotlinx = interner.intern("kotlinx")
        let coroutines = interner.intern("coroutines")
        let channels = interner.intern("channels")
        let coroutinesIntrinsics = interner.intern("intrinsics")

        kotlinRegexFQName = [kotlin, kotlinText, regex]
        kotlinStringBuilderFQName = [kotlin, kotlinText, stringBuilder]
        kotlinSequenceFQName = [kotlin, kotlinSequences, sequence]
        kotlinContinuationFQName = [kotlin, kotlinCoroutines, continuation]
        kotlinSuspendCoroutineFQName = [kotlin, kotlinCoroutines, suspendCoroutine]
        kotlinCollectionsListFQName = [kotlin, kotlinCollections, list]
        kotlinCollectionsMutableListFQName = [kotlin, kotlinCollections, mutableList]
        kotlinCollectionsSetFQName = [kotlin, kotlinCollections, set]
        kotlinCollectionsMutableSetFQName = [kotlin, kotlinCollections, mutableSet]
        kotlinCollectionsHashSetFQName = [kotlin, kotlinCollections, hashSet]
        kotlinCollectionsLinkedHashSetFQName = [kotlin, kotlinCollections, linkedHashSet]
        kotlinCollectionsMapFQName = [kotlin, kotlinCollections, map]
        kotlinCollectionsMutableMapFQName = [kotlin, kotlinCollections, mutableMap]
        kotlinCollectionsHashMapFQName = [kotlin, kotlinCollections, interner.intern("HashMap")]
        kotlinCollectionsCollectionFQName = [kotlin, kotlinCollections, collection]
        kotlinCollectionsMutableCollectionFQName = [kotlin, kotlinCollections, mutableCollection]
        kotlinEnumsEnumEntriesFQName = [kotlin, interner.intern("enums"), interner.intern("EnumEntries")]
        kotlinxCoroutinesJobFQName = [kotlinx, coroutines, job]
        kotlinxCoroutinesDeferredFQName = [kotlinx, coroutines, deferred]
        kotlinxCoroutinesChannelFQName = [kotlinx, coroutines, channels, channel]
        kotlinxCoroutinesProduceFQName = [kotlinx, coroutines, channels, produce]
        kotlinxCoroutinesRunBlockingFQName = [kotlinx, coroutines, runBlocking]
        kotlinxCoroutinesLaunchFQName = [kotlinx, coroutines, launch]
        kotlinxCoroutinesAsyncFQName = [kotlinx, coroutines, async]
        kotlinCoroutinesFQName = [kotlin, coroutines]
        kotlinCoroutinesIntrinsicsFQName = [kotlin, coroutines, coroutinesIntrinsics]
        kotlinCoroutinesContinuationFQName = [kotlin, coroutines, continuation]
        kotlinCoroutinesSuspendCoroutineUninterceptedOrReturnFQName = [kotlin, coroutines, coroutinesIntrinsics, suspendCoroutineUninterceptedOrReturn]

        let resultName = interner.intern("Result")
        kotlinResultFQName = [kotlin, resultName]

        let kotlinConcurrent = interner.intern("concurrent")
        let kotlinConcurrentAtomics = interner.intern("atomics")
        let atomicIntName = interner.intern("AtomicInt")
        let atomicLongName = interner.intern("AtomicLong")
        let atomicBooleanName = interner.intern("AtomicBoolean")
        let atomicReferenceName = interner.intern("AtomicReference")
        let javaAtomicIntegerName = interner.intern("AtomicInteger")
        let java = interner.intern("java")
        let util = interner.intern("util")
        let javaConcurrent = interner.intern("concurrent")
        let javaAtomic = interner.intern("atomic")
        atomicScalarFactoryFQNames = [
            [kotlin, kotlinConcurrent, atomicIntName],
            [kotlin, kotlinConcurrent, atomicLongName],
            [kotlin, kotlinConcurrent, atomicBooleanName],
            [kotlin, kotlinConcurrent, atomicReferenceName],
            [kotlin, kotlinConcurrent, kotlinConcurrentAtomics, atomicIntName],
            [kotlin, kotlinConcurrent, kotlinConcurrentAtomics, atomicLongName],
            [kotlin, kotlinConcurrent, kotlinConcurrentAtomics, atomicBooleanName],
            [kotlin, kotlinConcurrent, kotlinConcurrentAtomics, atomicReferenceName],
            [java, util, javaConcurrent, javaAtomic, javaAtomicIntegerName],
        ]
    }

    func builtinType(named name: InternedString, nullability: Nullability = .nonNull, types: TypeSystem) -> TypeID? {
        switch name {
        case byte:
            types.withNullability(nullability, for: types.byteType)
        case short:
            types.withNullability(nullability, for: types.shortType)
        case int:
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

    func symbolMatches(_ symbol: SemanticSymbol, fqName: [InternedString]) -> Bool {
        symbol.fqName == fqName
    }

    func isRegexSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == regex || symbolMatches(symbol, fqName: kotlinRegexFQName)
    }

    func isStringBuilderSymbol(_ symbol: SemanticSymbol) -> Bool {
        if symbolMatches(symbol, fqName: kotlinStringBuilderFQName) {
            return true
        }
        // Fall back to simple name match only for synthetic symbols (no FQN)
        return symbol.name == stringBuilder && symbol.fqName.isEmpty
    }

    /// True for synthetic runtime-backed atomic scalar classes whose constructors
    /// are factory functions (e.g. `kk_atomic_int_create`) rather than
    /// `(this, value)` initializers. These classes must not allocate a generic
    /// `kk_object_new` instance before calling the constructor.
    func isAtomicScalarFactorySymbol(_ symbol: SemanticSymbol) -> Bool {
        atomicScalarFactoryFQNames.contains(symbol.fqName)
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
            || name == shortArray
            || name == byteArray
            || name == ubyteArray
            || name == ushortArray
            || name == ulongArray
            || name == doubleArray
            || name == floatArray
            || name == booleanArray
            || name == charArray
            || name == uintArray
    }

    /// Returns true if the name is a primitive array constructor type name
    /// (e.g. Array, IntArray, LongArray, etc.).
    func isPrimitiveArrayConstructorTypeName(_ name: InternedString) -> Bool {
        name == array
            || name == intArray
            || name == longArray
            || name == shortArray
            || name == byteArray
            || name == ubyteArray
            || name == ushortArray
            || name == ulongArray
            || name == doubleArray
            || name == floatArray
            || name == booleanArray
            || name == charArray
            || name == uintArray
    }

    /// The set of stdlib collection factory function names used for marking
    /// collection literal expressions. Shared across call type-checking sites
    /// to avoid duplication.
    static let stdlibCollectionFactoryNames: Set<String> = [
        "listOf", "mutableListOf", "arrayListOf", "emptyList",
        "arrayOf", "emptyArray", "intArrayOf", "longArrayOf",
        "shortArrayOf", "byteArrayOf", "ubyteArrayOf", "ushortArrayOf", "uintArrayOf", "ulongArrayOf",
        "doubleArrayOf", "floatArrayOf", "booleanArrayOf", "charArrayOf",
        "mapOf", "mutableMapOf", "hashMapOf", "linkedMapOf", "emptyMap",
        "setOf", "setOfNotNull", "mutableSetOf", "hashSetOf", "linkedSetOf", "emptySet",
        "listOfNotNull",
        "sequenceOf", "generateSequence",
        "ArrayList",
        "HashMap", "LinkedHashMap",
        "HashSet", "LinkedHashSet",
    ]

    /// The subset of `stdlibCollectionFactoryNames` that produce `Array`/primitive-array
    /// literals rather than `List`/`Set`/`Map`/`Sequence` ones. Excluded from
    /// `markCollectionExpr` call sites: an `Array` receiver's runtime representation
    /// (RuntimeArrayBox) is not interchangeable with the List/Sequence-shaped box that
    /// collection member-call fallback resolution assumes, so flagging arrays as
    /// "collection expr" causes List/Sequence-only extension functions (e.g.
    /// `filterIsInstance`, `sortedBy`) to be resolved and lowered against the wrong
    /// runtime representation, corrupting memory or crashing.
    static let arrayFactoryFunctionNames: Set<String> = [
        "arrayOf", "emptyArray", "intArrayOf", "longArrayOf",
        "shortArrayOf", "byteArrayOf", "ubyteArrayOf", "ushortArrayOf", "uintArrayOf", "ulongArrayOf",
        "doubleArrayOf", "floatArrayOf", "booleanArrayOf", "charArrayOf",
    ]

    func isConcreteListLikeSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == list || symbol.name == mutableList
            || symbolMatches(symbol, fqName: kotlinCollectionsListFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsMutableListFQName)
            // kotlin.enums.EnumEntries<T> is a read-only List<T> subtype (Kotlin
            // 1.9+ `EnumClass.entries`). Treat it exactly like List so the
            // collection member-call fallback (.size, .forEach, etc.) resolves.
            || symbolMatches(symbol, fqName: kotlinEnumsEnumEntriesFQName)
    }

    func isMapLikeSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == map || symbol.name == mutableMap
            || symbolMatches(symbol, fqName: kotlinCollectionsMapFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsMutableMapFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsHashMapFQName)
    }

    func isMutableMapSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == mutableMap
            || symbolMatches(symbol, fqName: kotlinCollectionsMutableMapFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsHashMapFQName)
    }

    func isMutableSetSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == mutableSet || symbol.name == hashSet || symbol.name == linkedHashSet
            || symbolMatches(symbol, fqName: kotlinCollectionsMutableSetFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsHashSetFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsLinkedHashSetFQName)
    }

    func isSetLikeSymbol(_ symbol: SemanticSymbol) -> Bool {
        if symbolMatches(symbol, fqName: kotlinCollectionsSetFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsMutableSetFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsHashSetFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsLinkedHashSetFQName)
        {
            return true
        }
        // Fall back to simple name match only for synthetic symbols (no FQN)
        return (symbol.name == set
            || symbol.name == mutableSet
            || symbol.name == hashSet
            || symbol.name == linkedHashSet)
            && symbol.fqName.isEmpty
    }

    func isCollectionLikeSymbol(_ symbol: SemanticSymbol) -> Bool {
        isConcreteListLikeSymbol(symbol)
            || symbol.name == collection
            || symbol.name == mutableCollection
            || isSetLikeSymbol(symbol)
            || symbolMatches(symbol, fqName: kotlinCollectionsCollectionFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsMutableCollectionFQName)
            || isMapLikeSymbol(symbol)
            || isSequenceSymbol(symbol)
    }

    func collectionKind(of symbol: SemanticSymbol) -> KnownCollectionKind? {
        if isMapLikeSymbol(symbol) {
            return .map
        }
        if isSetLikeSymbol(symbol) {
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
        if isSequenceSymbol(symbol) {
            return .sequence
        }
        return nil
    }
}
