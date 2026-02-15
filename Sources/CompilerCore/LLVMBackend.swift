import Foundation

public struct RuntimeLinkInfo {
    public let libraryPaths: [String]
    public let libraries: [String]
    public let extraObjects: [String]

    public init(libraryPaths: [String], libraries: [String], extraObjects: [String]) {
        self.libraryPaths = libraryPaths
        self.libraries = libraries
        self.extraObjects = extraObjects
    }
}

public final class LLVMBackend {
    private let target: TargetTriple
    private let optLevel: OptimizationLevel
    private let debugInfo: Bool
    private let diagnostics: DiagnosticEngine

    public init(
        target: TargetTriple,
        optLevel: OptimizationLevel,
        debugInfo: Bool,
        diagnostics: DiagnosticEngine
    ) {
        self.target = target
        self.optLevel = optLevel
        self.debugInfo = debugInfo
        self.diagnostics = diagnostics
    }

    public func emitObject(
        module: KIRModule,
        runtime: RuntimeLinkInfo,
        outputObjectPath: String
    ) throws {
        let payload = """
        KSWIFTK-OBJECT
        target=\(targetTripleString())
        opt=\(optLevel.rawValue)
        debug=\(debugInfo)
        functions=\(module.functionCount)
        symbols=\(module.symbolCount)
        linkPaths=\(runtime.libraryPaths.joined(separator: ":"))
        libraries=\(runtime.libraries.joined(separator: ","))
        extraObjects=\(runtime.extraObjects.joined(separator: ","))
        """
        do {
            try payload.write(to: URL(fileURLWithPath: outputObjectPath), atomically: true, encoding: .utf8)
        } catch {
            diagnostics.error(
                "KSWIFTK-BACKEND-0001",
                "Failed to write object output: \(outputObjectPath)",
                range: nil
            )
            throw error
        }
    }

    public func emitLLVMIR(
        module: KIRModule,
        runtime: RuntimeLinkInfo,
        outputIRPath: String
    ) throws {
        let ir = """
        ; KSwiftK synthetic LLVM IR
        ; target \(targetTripleString())
        ; opt \(optLevel.rawValue) debug \(debugInfo)
        ; runtime libs \(runtime.libraries.joined(separator: ","))
        define i32 @kswiftk_module_entry() {
          ret i32 \(module.functionCount)
        }
        """
        do {
            try ir.write(to: URL(fileURLWithPath: outputIRPath), atomically: true, encoding: .utf8)
        } catch {
            diagnostics.error(
                "KSWIFTK-BACKEND-0002",
                "Failed to write LLVM IR output: \(outputIRPath)",
                range: nil
            )
            throw error
        }
    }

    private func targetTripleString() -> String {
        if let osVersion = target.osVersion, !osVersion.isEmpty {
            return "\(target.arch)-\(target.vendor)-\(target.os)\(osVersion)"
        }
        return "\(target.arch)-\(target.vendor)-\(target.os)"
    }
}
