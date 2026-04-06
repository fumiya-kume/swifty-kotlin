import Foundation

enum GoldenHarnessGoldenIOError: Error, CustomStringConvertible {
    case missingGolden(String)

    var description: String {
        switch self {
        case let .missingGolden(path):
            "Missing golden file: \(path). Run with UPDATE_GOLDEN=1."
        }
    }
}

enum GoldenHarnessGoldenFileIO {
    static var isUpdateMode: Bool {
        ProcessInfo.processInfo.environment["UPDATE_GOLDEN"] == "1"
    }

    /// When `UPDATE_GOLDEN=1`, writes `actual` to the `.golden` path and returns `true`.
    /// Otherwise returns `false` so the caller can load and compare.
    @discardableResult
    static func persistIfUpdating(caseFile: GoldenHarnessCaseFile, actual: String) throws -> Bool {
        guard isUpdateMode else {
            return false
        }
        try actual.write(to: caseFile.goldenURL, atomically: false, encoding: .utf8)
        return true
    }

    static func loadExpectedGolden(caseFile: GoldenHarnessCaseFile) throws -> String {
        guard FileManager.default.fileExists(atPath: caseFile.goldenURL.path) else {
            throw GoldenHarnessGoldenIOError.missingGolden(caseFile.goldenURL.path)
        }
        return try String(contentsOf: caseFile.goldenURL, encoding: .utf8)
    }
}
