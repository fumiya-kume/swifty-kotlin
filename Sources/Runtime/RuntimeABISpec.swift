public enum RuntimeABICType: String, Equatable {
    case void = "void"
    case uint32 = "uint32_t"
    case int32 = "int32_t"
    case intptr = "intptr_t"
    case opaquePointer = "void *"
    case nullableOpaquePointer = "void * _Nullable"
    case constUInt8Pointer = "const uint8_t *"
    case constCCharPointer = "const char *"
    case fieldAddrPointer = "void **"
    case constTypeInfoPointer = "const KTypeInfo *"
    case noreturn = "_Noreturn void"
}

public struct RuntimeABIParameter: Equatable {
    public let name: String
    public let type: RuntimeABICType

    public init(name: String, type: RuntimeABICType) {
        self.name = name
        self.type = type
    }
}

public struct RuntimeABIFunctionSpec: Equatable {
    public let name: String
    public let parameters: [RuntimeABIParameter]
    public let returnType: RuntimeABICType
    public let section: String

    public init(
        name: String,
        parameters: [RuntimeABIParameter],
        returnType: RuntimeABICType,
        section: String
    ) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.section = section
    }

    public var cDeclaration: String {
        let params: String
        if parameters.isEmpty {
            params = "void"
        } else {
            params = parameters.map { "\($0.type.rawValue) \($0.name)" }.joined(separator: ", ")
        }
        return "\(returnType.rawValue) \(name)(\(params));"
    }
}

public enum RuntimeABISpec {
    public static let specVersion = "J16.1"

    public static let memoryFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_alloc",
            parameters: [
                RuntimeABIParameter(name: "size", type: .uint32),
                RuntimeABIParameter(name: "typeInfo", type: .opaquePointer)
            ],
            returnType: .opaquePointer,
            section: "Memory"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_gc_collect",
            parameters: [],
            returnType: .void,
            section: "Memory"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_write_barrier",
            parameters: [
                RuntimeABIParameter(name: "owner", type: .opaquePointer),
                RuntimeABIParameter(name: "fieldAddr", type: .fieldAddrPointer)
            ],
            returnType: .void,
            section: "Memory"
        )
    ]

    public static let exceptionFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_throwable_new",
            parameters: [
                RuntimeABIParameter(name: "message", type: .nullableOpaquePointer)
            ],
            returnType: .opaquePointer,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_panic",
            parameters: [
                RuntimeABIParameter(name: "cstr", type: .constCCharPointer)
            ],
            returnType: .noreturn,
            section: "Exception"
        )
    ]

    public static let stringFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_string_from_utf8",
            parameters: [
                RuntimeABIParameter(name: "ptr", type: .constUInt8Pointer),
                RuntimeABIParameter(name: "len", type: .int32)
            ],
            returnType: .opaquePointer,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_concat",
            parameters: [
                RuntimeABIParameter(name: "a", type: .nullableOpaquePointer),
                RuntimeABIParameter(name: "b", type: .nullableOpaquePointer)
            ],
            returnType: .opaquePointer,
            section: "String"
        )
    ]

    public static let printlnFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_println_any",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .nullableOpaquePointer)
            ],
            returnType: .void,
            section: "Println"
        )
    ]

    public static let coroutineFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_suspended",
            parameters: [],
            returnType: .opaquePointer,
            section: "Coroutine"
        )
    ]

    public static let allFunctions: [RuntimeABIFunctionSpec] =
        memoryFunctions
        + exceptionFunctions
        + stringFunctions
        + printlnFunctions
        + coroutineFunctions

    public static func generateCHeader() -> String {
        var lines: [String] = []
        lines.append("#ifndef KK_RUNTIME_ABI_H")
        lines.append("#define KK_RUNTIME_ABI_H")
        lines.append("")
        lines.append("#include <stdint.h>")
        lines.append("#include <stddef.h>")
        lines.append("")
        lines.append("/* KSwiftK Runtime C ABI \u{2013} spec \(specVersion) */")
        lines.append("/* Auto-generated from RuntimeABISpec. Do NOT edit manually. */")
        lines.append("")
        lines.append("typedef struct KTypeInfo KTypeInfo;")
        lines.append("")

        var currentSection = ""
        for spec in allFunctions {
            if spec.section != currentSection {
                currentSection = spec.section
                lines.append("")
                lines.append("/* --- \(currentSection) --- */")
            }
            lines.append(spec.cDeclaration)
        }

        lines.append("")
        lines.append("#endif /* KK_RUNTIME_ABI_H */")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
