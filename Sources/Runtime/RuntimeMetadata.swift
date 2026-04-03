import Foundation

// MARK: - kotlinx-metadata compatible runtime models

public struct KmAnnotation: Codable, Equatable, Sendable {
    public let className: String
    public let arguments: [String]

    public init(className: String, arguments: [String] = []) {
        self.className = className
        self.arguments = arguments
    }
}

public struct KmValueParameter: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case instance
        case extensionReceiver
        case value

        init(runtimeKind: Int) {
            switch runtimeKind {
            case 0:
                self = .instance
            case 1:
                self = .extensionReceiver
            default:
                self = .value
            }
        }
    }

    public let name: String?
    public let type: String?
    public let isOptional: Bool
    public let kind: Kind

    public init(
        name: String? = nil,
        type: String? = nil,
        isOptional: Bool = false,
        kind: Kind = .value
    ) {
        self.name = name
        self.type = type
        self.isOptional = isOptional
        self.kind = kind
    }
}

public struct KmFunction: Codable, Equatable, Sendable {
    public let name: String
    public let returnType: String?
    public let valueParameters: [KmValueParameter]
    public let annotations: [KmAnnotation]
    public let isSuspend: Bool
    public let typeSignature: String?

    public init(
        name: String,
        returnType: String? = nil,
        valueParameters: [KmValueParameter] = [],
        annotations: [KmAnnotation] = [],
        isSuspend: Bool = false,
        typeSignature: String? = nil
    ) {
        self.name = name
        self.returnType = returnType
        self.valueParameters = valueParameters
        self.annotations = annotations
        self.isSuspend = isSuspend
        self.typeSignature = typeSignature
    }
}

public struct KmConstructor: Codable, Equatable, Sendable {
    public let name: String
    public let valueParameters: [KmValueParameter]
    public let annotations: [KmAnnotation]
    public let isPrimary: Bool
    public let visibility: String?
    public let declaringClassName: String?

    public init(
        name: String = "<init>",
        valueParameters: [KmValueParameter] = [],
        annotations: [KmAnnotation] = [],
        isPrimary: Bool = false,
        visibility: String? = nil,
        declaringClassName: String? = nil
    ) {
        self.name = name
        self.valueParameters = valueParameters
        self.annotations = annotations
        self.isPrimary = isPrimary
        self.visibility = visibility
        self.declaringClassName = declaringClassName
    }
}

public struct KmCompilerPluginMetadata: Codable, Equatable, Sendable {
    public let pluginId: String
    public let version: String?
    public let data: [String: String]

    public init(
        pluginId: String,
        version: String? = nil,
        data: [String: String] = [:]
    ) {
        self.pluginId = pluginId
        self.version = version
        self.data = data
    }
}

public func compilerPluginMetadata(
    pluginId: String,
    version: String? = nil,
    data: [String: String] = [:]
) -> KmCompilerPluginMetadata {
    KmCompilerPluginMetadata(pluginId: pluginId, version: version, data: data)
}

public struct KotlinMetadata: Codable, Equatable, Sendable {
    public let functions: [KmFunction]
    public let constructors: [KmConstructor]
    public let annotations: [KmAnnotation]
    public let compilerPlugins: [KmCompilerPluginMetadata]

    public init(
        functions: [KmFunction] = [],
        constructors: [KmConstructor] = [],
        annotations: [KmAnnotation] = [],
        compilerPlugins: [KmCompilerPluginMetadata] = []
    ) {
        self.functions = functions
        self.constructors = constructors
        self.annotations = annotations
        self.compilerPlugins = compilerPlugins
    }
}

public enum RuntimeMetadataCodec {
    public enum Error: Swift.Error, Equatable {
        case invalidUTF8
        case decodingFailed(String)
    }

    public static func serialize(_ metadata: KotlinMetadata) throws -> String {
        let encoder = JSONEncoder()
        if #available(macOS 10.13, *) {
            encoder.outputFormatting = [.sortedKeys]
        }
        let data = try encoder.encode(metadata)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw Error.invalidUTF8
        }
        return encoded
    }

    public static func deserialize(_ string: String) throws -> KotlinMetadata {
        let decoder = JSONDecoder()
        guard let data = string.data(using: .utf8) else {
            throw Error.invalidUTF8
        }
        do {
            return try decoder.decode(KotlinMetadata.self, from: data)
        } catch {
            throw Error.decodingFailed(String(describing: error))
        }
    }
}

// MARK: - Runtime box conversion helpers

extension KmAnnotation {
    init(_ record: RuntimeAnnotationRecord) {
        self.init(className: record.annotationFQName, arguments: record.arguments)
    }

    init(_ box: RuntimeAnnotationBox) {
        self.init(className: box.annotationFQName, arguments: box.arguments)
    }
}

extension KmValueParameter {
    init(_ box: RuntimeKParameterBox) {
        let resolvedName = runtimeMetadataString(from: box.nameRaw)
        let resolvedType = runtimeMetadataString(from: box.typeRaw)
        self.init(
            name: resolvedName?.isEmpty == true ? nil : resolvedName,
            type: resolvedType?.isEmpty == true ? nil : resolvedType,
            isOptional: box.isOptional,
            kind: Kind(runtimeKind: box.kind)
        )
    }
}

extension KmFunction {
    init(_ box: RuntimeKFunctionBox, annotations: [KmAnnotation] = []) {
        let parameters = box.parameterRaws.compactMap(runtimeMetadataKParameterBox(from:)).map(KmValueParameter.init)
        self.init(
            name: runtimeMetadataString(from: box.nameRaw) ?? "",
            returnType: runtimeMetadataString(from: box.returnTypeRaw),
            valueParameters: parameters,
            annotations: annotations,
            isSuspend: box.isSuspend,
            typeSignature: runtimeMetadataString(from: box.typeStringRaw)
        )
    }
}

extension KmConstructor {
    init(_ box: RuntimeKConstructorBox, annotations: [KmAnnotation] = []) {
        let parameters = box.parameterNameRaws.map { raw in
            KmValueParameter(name: runtimeMetadataString(from: raw), type: nil, isOptional: false, kind: .value)
        }
        let declaringClassName: String?
        if let kclass = runtimeMetadataKClassBox(from: box.declaringClassRaw) {
            declaringClassName = kclass.metadata?.qualifiedName ?? runtimeMetadataString(from: box.returnTypeRaw)
        } else {
            declaringClassName = runtimeMetadataString(from: box.returnTypeRaw)
        }
        self.init(
            name: runtimeMetadataString(from: box.nameRaw) ?? "<init>",
            valueParameters: parameters,
            annotations: annotations,
            isPrimary: box.isPrimary,
            visibility: runtimeMetadataString(from: box.visibilityRaw),
            declaringClassName: declaringClassName
        )
    }
}

private func runtimeMetadataString(from raw: Int) -> String? {
    guard raw != 0, raw != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: raw)
    else {
        return nil
    }
    return extractString(from: ptr)
}

private func runtimeMetadataKParameterBox(from raw: Int) -> RuntimeKParameterBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeKParameterBox.self)
}

private func runtimeMetadataKClassBox(from raw: Int) -> RuntimeKClassBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeKClassBox.self)
}
