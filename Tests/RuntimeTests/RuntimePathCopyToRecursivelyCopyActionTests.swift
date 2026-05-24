import Foundation
@testable import Runtime
import XCTest

private typealias RuntimePathCopyAction = @convention(c) (
    Int,
    Int,
    Int,
    UnsafeMutablePointer<Int>?
) -> Int

private let pathCopyActionContinue: RuntimePathCopyAction = { _, sourceRaw, targetRaw, outThrown in
    runtimePathCopyActionCopyEntry(sourceRaw: sourceRaw, targetRaw: targetRaw, outThrown: outThrown)
}

private let pathCopyActionSkipNamedDirectory: RuntimePathCopyAction = { _, sourceRaw, targetRaw, outThrown in
    guard let sourcePath = runtimePathCopyActionPathString(sourceRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid source Path")
        return 2
    }
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: sourcePath, isDirectory: &isDirectory),
       isDirectory.boolValue,
       URL(fileURLWithPath: sourcePath).lastPathComponent == "skip" {
        _ = runtimePathCopyActionCopyEntry(sourceRaw: sourceRaw, targetRaw: targetRaw, outThrown: outThrown)
        return 1
    }
    return runtimePathCopyActionCopyEntry(sourceRaw: sourceRaw, targetRaw: targetRaw, outThrown: outThrown)
}

final class RuntimePathCopyToRecursivelyCopyActionTests: IsolatedRuntimeXCTestCase {
    func testPathCopyToRecursivelyCopyActionCopiesDirectoryTree() throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nestedURL = sourceURL.appendingPathComponent("nested")
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try "root".write(to: sourceURL.appendingPathComponent("root.txt"), atomically: true, encoding: .utf8)
        try "child".write(to: nestedURL.appendingPathComponent("child.txt"), atomically: true, encoding: .utf8)

        var thrown = 0
        let targetRaw = runtimeTestPathHandle(targetURL.path)
        let resultRaw = kk_path_copyToRecursively_copyAction(
            runtimeTestPathHandle(sourceURL.path),
            targetRaw,
            0,
            kk_box_bool(0),
            runtimePathCopyActionRaw(pathCopyActionContinue),
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(resultRaw, targetRaw)
        XCTAssertEqual(
            try String(contentsOf: targetURL.appendingPathComponent("root.txt"), encoding: .utf8),
            "root"
        )
        XCTAssertEqual(
            try String(contentsOf: targetURL.appendingPathComponent("nested").appendingPathComponent("child.txt"), encoding: .utf8),
            "child"
        )
    }

    func testPathCopyToRecursivelyCopyActionSkipsSubtree() throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let keepURL = sourceURL.appendingPathComponent("keep")
        let skipURL = sourceURL.appendingPathComponent("skip")
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.createDirectory(at: keepURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skipURL, withIntermediateDirectories: true)
        try "visible".write(to: keepURL.appendingPathComponent("visible.txt"), atomically: true, encoding: .utf8)
        try "hidden".write(to: skipURL.appendingPathComponent("hidden.txt"), atomically: true, encoding: .utf8)

        var thrown = 0
        let targetRaw = runtimeTestPathHandle(targetURL.path)
        let resultRaw = kk_path_copyToRecursively_copyAction(
            runtimeTestPathHandle(sourceURL.path),
            targetRaw,
            0,
            kk_box_bool(0),
            runtimePathCopyActionRaw(pathCopyActionSkipNamedDirectory),
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(resultRaw, targetRaw)
        XCTAssertEqual(
            try String(contentsOf: targetURL.appendingPathComponent("keep").appendingPathComponent("visible.txt"), encoding: .utf8),
            "visible"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetURL.appendingPathComponent("skip").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetURL.appendingPathComponent("skip").appendingPathComponent("hidden.txt").path))
    }

    private func runtimeTestPathHandle(_ path: String) -> Int {
        kk_path_new(makeRuntimeString(path))
    }

    private func makeRuntimeString(_ value: String) -> Int {
        let bytes = Array(value.utf8)
        return bytes.withUnsafeBufferPointer { buffer -> Int in
            let baseAddress = buffer.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 0x1)!
            return Int(bitPattern: kk_string_from_utf8(baseAddress, Int32(bytes.count)))
        }
    }
}

private func runtimePathCopyActionRaw(_ action: RuntimePathCopyAction) -> Int {
    Int(bitPattern: unsafeBitCast(action, to: UnsafeRawPointer.self))
}

private func runtimePathCopyActionPathString(_ pathRaw: Int) -> String? {
    let stringRaw = kk_path_pathString(pathRaw)
    return extractString(from: UnsafeMutableRawPointer(bitPattern: stringRaw))
}

private func runtimePathCopyActionCopyEntry(
    sourceRaw: Int,
    targetRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let sourcePath = runtimePathCopyActionPathString(sourceRaw),
          let targetPath = runtimePathCopyActionPathString(targetRaw)
    else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid Path")
        return 2
    }

    do {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourcePath, isDirectory: &isDirectory) else {
            throw NSError(
                domain: "KSwiftKRuntimePathTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Source path does not exist: \(sourcePath)"]
            )
        }

        if isDirectory.boolValue {
            if !fileManager.fileExists(atPath: targetPath) {
                try fileManager.createDirectory(atPath: targetPath, withIntermediateDirectories: false)
            }
        } else {
            try fileManager.copyItem(atPath: sourcePath, toPath: targetPath)
        }
        outThrown?.pointee = 0
        return 0
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return 2
    }
}
