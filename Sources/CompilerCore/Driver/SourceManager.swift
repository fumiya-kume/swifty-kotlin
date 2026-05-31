import Foundation

/// Concurrency model:
/// `SourceManager` is populated sequentially during `LoadSourcesPhase`,
/// and treated as read-only after that phase completes.
public final class SourceManager: @unchecked Sendable {
    private struct FileRecord {
        let path: String
        let contents: Data
        let lineStartOffsets: [Int]
    }

    private var files: [FileRecord] = []
    private var fileIDByPath: [String: FileID] = [:]

    public init() {}

    public func addFile(path: String, contents: Data) -> FileID {
        if let existingID = fileIDByPath[path] {
            let index = Int(existingID.rawValue)
            guard index >= 0, index < files.count else {
                return existingID
            }
            let existingRecord = files[index]
            if existingRecord.contents != contents {
                files[index] = FileRecord(
                    path: path,
                    contents: contents,
                    lineStartOffsets: computeLineStartOffsets(contents: contents)
                )
            }
            return existingID
        }
        let id = FileID(rawValue: files.count)
        let record = FileRecord(
            path: path,
            contents: contents,
            lineStartOffsets: computeLineStartOffsets(contents: contents)
        )
        files.append(record)
        fileIDByPath[path] = id
        return id
    }

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

    var fileCount: Int {
        files.count
    }

    func containsFile(path: String) -> Bool {
        fileIDByPath[path] != nil
    }

    public func fileID(forPath path: String) -> FileID? {
        fileIDByPath[path]
    }

    func fileIDs() -> [FileID] {
        files.indices.map { FileID(rawValue: $0) }
    }

    public func lineColumn(of loc: SourceLocation) -> LineColumn {
        guard let record = fileRecord(for: loc.file), !record.contents.isEmpty else {
            return LineColumn(line: 1, column: 1)
        }

        let clampedOffset = max(0, min(loc.offset, record.contents.count))
        let lineIndex = lineIndex(for: clampedOffset, in: record.lineStartOffsets)
        let lineStartOffset = record.lineStartOffsets[lineIndex]
        let lineText = String(decoding: record.contents[lineStartOffset ..< clampedOffset], as: UTF8.self)
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
        let text = String(decoding: record.contents[start ..< end], as: UTF8.self)
        return Substring(text)
    }

    // MARK: - LSP position conversion (0-based, UTF-16)

    /// Converts a byte `SourceLocation` to a 0-based LSP position. `character`
    /// counts UTF-16 code units from the start of the line, matching LSP's
    /// default `utf-16` position encoding.
    public func lspPosition(of loc: SourceLocation) -> (line: Int, character: Int) {
        guard let record = fileRecord(for: loc.file), !record.contents.isEmpty else {
            return (0, 0)
        }
        let clampedOffset = max(0, min(loc.offset, record.contents.count))
        let lineIdx = lineIndex(for: clampedOffset, in: record.lineStartOffsets)
        let lineStartOffset = record.lineStartOffsets[lineIdx]
        let prefix = record.contents[lineStartOffset ..< clampedOffset]
        let utf16Count = String(decoding: prefix, as: UTF8.self).utf16.count
        return (lineIdx, utf16Count)
    }

    /// Converts a 0-based LSP position (line + UTF-16 character offset) into a
    /// byte offset within the given file. Returns `nil` when the file is
    /// unknown. Out-of-range lines and characters are clamped to the nearest
    /// valid offset so callers always receive a usable location.
    public func offset(ofLine line: Int, utf16Character character: Int, in file: FileID) -> Int? {
        guard let record = fileRecord(for: file) else {
            return nil
        }
        let lineStarts = record.lineStartOffsets
        guard !lineStarts.isEmpty else { return 0 }
        if line < 0 { return 0 }
        if line >= lineStarts.count { return record.contents.count }

        let lineStart = lineStarts[line]
        let lineEnd = (line + 1 < lineStarts.count) ? lineStarts[line + 1] : record.contents.count
        if character <= 0 { return lineStart }

        let lineText = String(decoding: record.contents[lineStart ..< lineEnd], as: UTF8.self)
        var utf16Seen = 0
        var byteOffset = lineStart
        for scalar in lineText.unicodeScalars {
            if utf16Seen >= character { break }
            if scalar == "\n" || scalar == "\r" { break }
            utf16Seen += scalar.value > 0xFFFF ? 2 : 1
            byteOffset += utf8Length(of: scalar)
        }
        return byteOffset
    }

    private func utf8Length(of scalar: Unicode.Scalar) -> Int {
        switch scalar.value {
        case 0 ... 0x7F: 1
        case 0x80 ... 0x7FF: 2
        case 0x800 ... 0xFFFF: 3
        default: 4
        }
    }

    private func fileRecord(for id: FileID) -> FileRecord? {
        let index = Int(id.rawValue)
        guard index >= 0, index < files.count else {
            return nil
        }
        return files[index]
    }

    private func computeLineStartOffsets(contents: Data) -> [Int] {
        var lineStarts = [0]
        for index in 0 ..< contents.count where contents[index] == 0x0A {
            lineStarts.append(index + 1)
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
