import Foundation

public final class SourceManager: @unchecked Sendable {
    private struct FileRecord {
        let path: String
        let contents: Data
        let lineStartOffsets: [Int]
    }

    private var files: [FileRecord] = []

    public init() {}

    @discardableResult
    public func addFile(path: String, contents: Data) -> FileID {
        let id = FileID(rawValue: files.count)
        let record = FileRecord(
            path: path,
            contents: contents,
            lineStartOffsets: computeLineStartOffsets(contents: contents)
        )
        files.append(record)
        return id
    }

    @discardableResult
    public func addFile(path: String) throws -> FileID {
        let contents = try Data(contentsOf: URL(fileURLWithPath: path))
        return addFile(path: path, contents: contents)
    }

    public func contents(of file: FileID) -> Data {
        guard let record = fileRecord(for: file) else {
            return Data()
        }
        return record.contents
    }

    public func path(of file: FileID) -> String {
        guard let record = fileRecord(for: file) else {
            return ""
        }
        return record.path
    }

    internal var fileCount: Int {
        files.count
    }

    internal func containsFile(path: String) -> Bool {
        files.contains { $0.path == path }
    }

    internal func fileIDs() -> [FileID] {
        return files.enumerated().map { FileID(rawValue: $0.offset) }
    }

    public func lineColumn(of loc: SourceLocation) -> LineColumn {
        guard let record = fileRecord(for: loc.file), !record.contents.isEmpty else {
            return LineColumn(line: 1, column: 1)
        }

        let clampedOffset = max(0, min(loc.offset, record.contents.count))
        let lineIndex = lineIndex(for: clampedOffset, in: record.lineStartOffsets)
        let lineStartOffset = record.lineStartOffsets[lineIndex]
        let lineText = String(decoding: record.contents[lineStartOffset..<clampedOffset], as: UTF8.self)
        let column = lineText.unicodeScalars.count + 1
        return LineColumn(line: lineIndex + 1, column: column)
    }

    public func slice(_ range: SourceRange) -> Substring {
        guard let record = fileRecord(for: range.start.file) else {
            return ""
        }

        let fileSize = record.contents.count
        let start = max(0, min(range.start.offset, fileSize))
        let end = max(start, min(range.end.offset, fileSize))
        let text = String(decoding: record.contents[start..<end], as: UTF8.self)
        return Substring(text)
    }

    private func fileRecord(for id: FileID) -> FileRecord? {
        let index = Int(id.rawValue)
        guard index >= 0 && index < files.count else {
            return nil
        }
        return files[index]
    }

    private func computeLineStartOffsets(contents: Data) -> [Int] {
        var lineStarts = [0]
        for index in 0..<contents.count {
            if contents[index] == 0x0A {
                lineStarts.append(index + 1)
            }
        }
        return lineStarts
    }

    private func lineIndex(for offset: Int, in lineStarts: [Int]) -> Int {
        var low = 0
        var high = lineStarts.count
        while low < high {
            let mid = (low + high) >> 1
            if lineStarts[mid] <= offset {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return max(0, low - 1)
    }
}
