import Foundation

struct GoldenHarnessCaseFile: Sendable {
    var sourcePath: String { sourceURL.path }
    let sourceURL: URL
    var goldenURL: URL { sourceURL.deletingPathExtension().appendingPathExtension("golden") }
    var basename: String { sourceURL.lastPathComponent }

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
    }
}

enum GoldenHarnessCaseDiscoveryError: Error, CustomStringConvertible {
    case missingSuiteDirectory(String)
    case noKtFiles(String)

    var description: String {
        switch self {
        case let .missingSuiteDirectory(path):
            "Golden suite directory does not exist: \(path)"
        case let .noKtFiles(path):
            "No golden .kt files in \(path)"
        }
    }
}

enum GoldenHarnessCaseDiscovery {
    static func loadCases(suite: GoldenHarnessGoldenSuite) throws -> [GoldenHarnessCaseFile] {
        let suiteURL = GoldenHarnessPaths.goldenCasesDirectory.appendingPathComponent(suite.rawValue, isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: suiteURL.path) else {
            throw GoldenHarnessCaseDiscoveryError.missingSuiteDirectory(suiteURL.path)
        }

        let sourceFiles = try fm.contentsOfDirectory(at: suiteURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "kt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !sourceFiles.isEmpty else {
            throw GoldenHarnessCaseDiscoveryError.noKtFiles(suiteURL.path)
        }
        return sourceFiles.map { GoldenHarnessCaseFile(sourceURL: $0) }
    }
}
