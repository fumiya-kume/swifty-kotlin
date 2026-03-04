import Foundation

/// Records wall-clock timing for each compiler phase and optionally prints
/// a summary table when the `time-phases` frontend flag is active.
public final class PhaseTimer {
    /// A single recorded phase timing.
    public struct PhaseRecord {
        public let name: String
        public let startTime: UInt64
        public let endTime: UInt64
        /// Sub-phase records (e.g. individual subprocess invocations).
        public let subRecords: [PhaseRecord]

        /// Duration in nanoseconds.
        public var durationNanos: UInt64 {
            endTime - startTime
        }

        /// Duration in milliseconds (floating point).
        public var durationMs: Double {
            Double(durationNanos) / 1_000_000.0
        }

        public init(name: String, startTime: UInt64, endTime: UInt64, subRecords: [PhaseRecord] = []) {
            self.name = name
            self.startTime = startTime
            self.endTime = endTime
            self.subRecords = subRecords
        }
    }

    private var records: [PhaseRecord] = []
    private var currentPhaseName: String?
    private var currentPhaseStart: UInt64 = 0
    private var currentSubRecords: [PhaseRecord] = []

    public init() {}

    // MARK: - Recording

    /// Mark the beginning of a phase.
    public func beginPhase(_ name: String) {
        currentPhaseName = name
        currentPhaseStart = DispatchTime.now().uptimeNanoseconds
        currentSubRecords = []
    }

    /// Mark the end of the current phase.
    public func endPhase() {
        guard let name = currentPhaseName else { return }
        let endTime = DispatchTime.now().uptimeNanoseconds
        records.append(PhaseRecord(
            name: name,
            startTime: currentPhaseStart,
            endTime: endTime,
            subRecords: currentSubRecords
        ))
        currentPhaseName = nil
        currentSubRecords = []
    }

    /// Record a sub-phase timing within the current phase.
    /// Typically used to measure individual subprocess invocations
    /// (e.g. clang calls during Codegen or Link).
    public func recordSubPhase(_ name: String, startTime: UInt64, endTime: UInt64) {
        currentSubRecords.append(PhaseRecord(
            name: name,
            startTime: startTime,
            endTime: endTime
        ))
    }

    // MARK: - Access

    /// All recorded phase timings.
    public var phaseRecords: [PhaseRecord] {
        records
    }

    /// Total wall-clock duration across all phases in nanoseconds.
    public var totalNanos: UInt64 {
        records.reduce(0) { $0 + $1.durationNanos }
    }

    /// Total wall-clock duration across all phases in milliseconds.
    public var totalMs: Double {
        Double(totalNanos) / 1_000_000.0
    }

    // MARK: - Summary output

    /// Pad or truncate `text` to exactly `width` characters (left-aligned).
    private func pad(_ text: String, to width: Int) -> String {
        if text.count >= width { return String(text.prefix(width)) }
        return text + String(repeating: " ", count: width - text.count)
    }

    /// Print a human-readable timing summary to stderr.
    public func printSummary() {
        let total = totalMs
        FileHandle.standardError.write(Data("===== Phase Timing Summary =====\n".utf8))
        let header = "\(pad("Phase", to: 24)) \(pad("Time (ms)", to: 10)) \(pad("%", to: 8))\n"
        FileHandle.standardError.write(Data(header.utf8))
        let separator = String(repeating: "-", count: 46) + "\n"
        FileHandle.standardError.write(Data(separator.utf8))

        for record in records {
            let ms = record.durationMs
            let pct = total > 0 ? (ms / total) * 100.0 : 0.0
            let line = "\(pad(record.name, to: 24)) \(String(format: "%10.2f", ms)) \(String(format: "%7.1f%%", pct))\n"
            FileHandle.standardError.write(Data(line.utf8))
            for sub in record.subRecords {
                let subMs = sub.durationMs
                let subPct = total > 0 ? (subMs / total) * 100.0 : 0.0
                let subLine = "  \(pad(sub.name, to: 22)) \(String(format: "%10.2f", subMs)) \(String(format: "%7.1f%%", subPct))\n"
                FileHandle.standardError.write(Data(subLine.utf8))
            }
        }

        FileHandle.standardError.write(Data(separator.utf8))
        let totalLine = "\(pad("TOTAL", to: 24)) \(String(format: "%10.2f", total)) \(String(format: "%7.1f%%", 100.0))\n"
        FileHandle.standardError.write(Data(totalLine.utf8))
    }

    // MARK: - Machine-readable export

    /// Export timing data as a TSV string.
    ///
    /// Columns: phase, duration_ms, percent
    public func exportTSV() -> String {
        let total = totalMs
        var lines = ["phase\tduration_ms\tpercent"]
        for record in records {
            let ms = record.durationMs
            let pct = total > 0 ? (ms / total) * 100.0 : 0.0
            lines.append("\(record.name)\t\(String(format: "%.2f", ms))\t\(String(format: "%.1f", pct))")
            for sub in record.subRecords {
                let subMs = sub.durationMs
                let subPct = total > 0 ? (subMs / total) * 100.0 : 0.0
                lines.append("  \(sub.name)\t\(String(format: "%.2f", subMs))\t\(String(format: "%.1f", subPct))")
            }
        }
        lines.append("TOTAL\t\(String(format: "%.2f", total))\t100.0")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Export timing data as a JSON-compatible dictionary array.
    public func exportJSON() -> [[String: Any]] {
        let total = totalMs
        var result: [[String: Any]] = []
        for record in records {
            let ms = record.durationMs
            let pct = total > 0 ? (ms / total) * 100.0 : 0.0
            var entry: [String: Any] = [
                "phase": record.name,
                "duration_ms": round(ms * 100) / 100,
                "percent": round(pct * 10) / 10
            ]
            if !record.subRecords.isEmpty {
                entry["sub_phases"] = record.subRecords.map { sub in
                    let subMs = sub.durationMs
                    let subPct = total > 0 ? (subMs / total) * 100.0 : 0.0
                    return [
                        "phase": sub.name,
                        "duration_ms": round(subMs * 100) / 100,
                        "percent": round(subPct * 10) / 10
                    ] as [String: Any]
                }
            }
            result.append(entry)
        }
        result.append([
            "phase": "TOTAL",
            "duration_ms": round(total * 100) / 100,
            "percent": 100.0
        ])
        return result
    }
}
