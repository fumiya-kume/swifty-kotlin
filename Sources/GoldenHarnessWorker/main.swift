import Foundation
import GoldenHarnessSupport

@main
struct GoldenHarnessWorkerMain {
    static func main() {
        do {
            guard CommandLine.arguments.count == 3 else {
                throw WorkerError.invalidArguments
            }
            let suiteName = CommandLine.arguments[1]
            let sourcePath = CommandLine.arguments[2]
            let output = try GoldenHarness.render(suiteName: suiteName, sourcePath: sourcePath)
            FileHandle.standardOutput.write(Data(output.utf8))
        } catch {
            let message = String(describing: error) + "\n"
            FileHandle.standardError.write(Data(message.utf8))
            Foundation.exit(1)
        }
    }
}

enum WorkerError: Error, CustomStringConvertible {
    case invalidArguments

    var description: String {
        switch self {
        case .invalidArguments:
            "usage: GoldenHarnessWorker <suite> <sourcePath>"
        }
    }
}
