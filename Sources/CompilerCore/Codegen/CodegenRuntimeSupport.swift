import Foundation

enum CodegenRuntimeSupport {
    private static let stubCache = RuntimeStubCache()

    static func runtimeStubObjectPath(target: TargetTriple) -> String? {
        let triple = targetTripleString(target)
        let source = fixedRuntimePreamble.joined(separator: "\n")
        let cacheKey = stableFNV1a64Hex(triple + "_" + stableFNV1a64Hex(source))
        let stubDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk_rt_stubs")
        let context = StubCompilationContext(
            source: source,
            cacheKey: cacheKey,
            clangTargetArgs: clangTargetArgs(target),
            stubDir: stubDir
        )

        return stubCache.getOrInsert(triple: triple, context: context)
    }

    static func clangTargetArgs(_ target: TargetTriple) -> [String] {
        ["-target", targetTripleString(target)]
    }

    static func targetTripleString(_ target: TargetTriple) -> String {
        if let osVersion = target.osVersion, !osVersion.isEmpty {
            return "\(target.arch)-\(target.vendor)-\(target.os)\(osVersion)"
        }
        return "\(target.arch)-\(target.vendor)-\(target.os)"
    }

    static func stableFNV1a64Hex(_ value: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}
