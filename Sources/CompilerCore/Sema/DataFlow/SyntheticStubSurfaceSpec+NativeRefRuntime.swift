enum SyntheticNativeRefRuntimeSurfaceSpec {
    private static let weakReferenceT = SyntheticStubTypeRef.typeParameter("T")
    static let weakReferenceType = SyntheticStubTypeRef.namedClass(
        ["kotlin", "native", "ref", "WeakReference"],
        args: [.invariant(weakReferenceT)]
    )
    static let weakReferenceConstructor = SyntheticConstructorStubSpec(
        externalLinkName: "kk_weak_ref_create",
        parameters: [
            SyntheticStubParameterSpec(name: "value", type: weakReferenceT),
        ],
        typeParameterNames: ["T"],
        classTypeParameterCount: 1
    )
    static let weakReferenceMembers: [SyntheticFunctionStubSpec] = [
        SyntheticFunctionStubSpec(
            name: "get",
            externalLinkName: "kk_weak_ref_get",
            receiverType: weakReferenceType,
            returnType: .nullable(weakReferenceT),
            typeParameterNames: ["T"],
            classTypeParameterCount: 1
        ),
        SyntheticFunctionStubSpec(
            name: "clear",
            externalLinkName: "kk_weak_ref_clear",
            receiverType: weakReferenceType,
            returnType: .unit,
            typeParameterNames: ["T"],
            classTypeParameterCount: 1
        ),
    ]

    static let gcType = nativeRuntimeClass("GC")
    static let gcFunctions: [SyntheticFunctionStubSpec] = [
        SyntheticFunctionStubSpec(
            name: "collect",
            externalLinkName: "kk_gc_collect",
            receiverType: gcType,
            returnType: .unit
        ),
        SyntheticFunctionStubSpec(
            name: "schedule",
            externalLinkName: "kk_gc_schedule",
            receiverType: gcType,
            returnType: .unit
        ),
    ]
    static let gcProperties: [SyntheticPropertyStubSpec] = [
        SyntheticPropertyStubSpec(
            name: "targetHeapBytes",
            propertyType: .long,
            externalLinkName: "kk_gc_target_heap_bytes"
        ),
        SyntheticPropertyStubSpec(
            name: "targetHeapUtilization",
            propertyType: .double,
            externalLinkName: "kk_gc_target_heap_utilization"
        ),
        SyntheticPropertyStubSpec(
            name: "maxHeapBytes",
            propertyType: .long,
            externalLinkName: "kk_gc_max_heap_bytes"
        ),
    ]

    static let rootSetStatisticsType = nativeRuntimeClass("RootSetStatistics")
    static let rootSetStatisticsProperties: [SyntheticPropertyStubSpec] = [
        SyntheticPropertyStubSpec(name: "threadLocalReferences", propertyType: .long),
        SyntheticPropertyStubSpec(name: "stackReferences", propertyType: .long),
        SyntheticPropertyStubSpec(name: "globalReferences", propertyType: .long),
        SyntheticPropertyStubSpec(name: "stableReferences", propertyType: .long),
    ]
    static let rootSetStatisticsConstructor = constructor(from: rootSetStatisticsProperties)

    static let sweepStatisticsType = nativeRuntimeClass("SweepStatistics")
    static let sweepStatisticsProperties: [SyntheticPropertyStubSpec] = [
        SyntheticPropertyStubSpec(name: "sweptCount", propertyType: .long),
        SyntheticPropertyStubSpec(name: "keptCount", propertyType: .long),
    ]
    static let sweepStatisticsConstructor = constructor(from: sweepStatisticsProperties)

    static let gcInfoType = nativeRuntimeClass("GCInfo")
    static let memoryUsageType = nativeRuntimeClass("MemoryUsage")
    static let gcInfoProperties: [SyntheticPropertyStubSpec] = [
        SyntheticPropertyStubSpec(name: "epoch", propertyType: .long),
        SyntheticPropertyStubSpec(name: "startTimeNs", propertyType: .long),
        SyntheticPropertyStubSpec(name: "endTimeNs", propertyType: .long),
        SyntheticPropertyStubSpec(name: "firstPauseRequestTimeNs", propertyType: .long),
        SyntheticPropertyStubSpec(name: "firstPauseStartTimeNs", propertyType: .long),
        SyntheticPropertyStubSpec(name: "firstPauseEndTimeNs", propertyType: .long),
        SyntheticPropertyStubSpec(name: "secondPauseRequestTimeNs", propertyType: .nullable(.long)),
        SyntheticPropertyStubSpec(name: "secondPauseStartTimeNs", propertyType: .nullable(.long)),
        SyntheticPropertyStubSpec(name: "secondPauseEndTimeNs", propertyType: .nullable(.long)),
        SyntheticPropertyStubSpec(name: "postGcCleanupTimeNs", propertyType: .nullable(.long)),
        SyntheticPropertyStubSpec(name: "rootSet", propertyType: rootSetStatisticsType),
        SyntheticPropertyStubSpec(name: "markedCount", propertyType: .long),
        SyntheticPropertyStubSpec(name: "sweepStatistics", propertyType: mapOfString(to: sweepStatisticsType)),
        SyntheticPropertyStubSpec(name: "memoryUsageBefore", propertyType: mapOfString(to: memoryUsageType)),
        SyntheticPropertyStubSpec(name: "memoryUsageAfter", propertyType: mapOfString(to: memoryUsageType)),
    ]
    static let gcInfoConstructor = constructor(from: gcInfoProperties)

    static let memoryUsageProperties: [SyntheticPropertyStubSpec] = [
        SyntheticPropertyStubSpec(name: "totalObjectsSizeBytes", propertyType: .long),
    ]

    static let debuggingProperties: [SyntheticPropertyStubSpec] = [
        SyntheticPropertyStubSpec(
            name: "isThreadStateRunnable",
            propertyType: .boolean,
            externalLinkName: "kk_debugging_is_thread_state_runnable"
        ),
        SyntheticPropertyStubSpec(
            name: "gcSuspendCount",
            propertyType: .int,
            externalLinkName: "kk_debugging_gc_suspend_count"
        ),
        SyntheticPropertyStubSpec(
            name: "threadCount",
            propertyType: .int,
            externalLinkName: "kk_debugging_thread_count"
        ),
        SyntheticPropertyStubSpec(
            name: "globalObjectCount",
            propertyType: .int,
            externalLinkName: "kk_debugging_global_object_count"
        ),
    ]

    private static func nativeRuntimeClass(_ name: String) -> SyntheticStubTypeRef {
        .namedClass(["kotlin", "native", "runtime", name])
    }

    private static func mapOfString(to valueType: SyntheticStubTypeRef) -> SyntheticStubTypeRef {
        .fallback(
            primary: .namedClass(
                ["kotlin", "collections", "Map"],
                args: [.out(.string), .out(valueType)]
            ),
            fallback: .any
        )
    }

    private static func constructor(
        from properties: [SyntheticPropertyStubSpec]
    ) -> SyntheticConstructorStubSpec {
        SyntheticConstructorStubSpec(
            parameters: properties.map {
                SyntheticStubParameterSpec(name: $0.name, type: $0.propertyType)
            }
        )
    }
}
