import Foundation

/// Records wall-clock timing for each compiler phase and optionally prints
/// a summary table when the `time-phases` frontend flag is active.
public final class PhaseTimer {

    /// A single recorded phase timing.
    public struct PhaseRecord {
        public let name: String
        public let startTime: UInt64
        public let endTime: UInt64

        /// Duration in nanoseconds.
        public var durationNanos: UInt64 {
            endTime - startTime
        }

        /// Duration in milliseconds (floating point).
        public var durationMs: Double {
            Double(durationNanos) / 1_000_000.0
        }
    }

    private var records: [PhaseRecord] = []
    private var currentPhaseName: String?
    private var currentPhaseStart: UInt64 = 0

    public init() {}

    // MARK: - Recording

    /// Mark the beginning of a phase.
    public func beginPhase(_ name: String) {
        currentPhaseName = name
        currentPhaseStart = DispatchTime.now().uptimeNanoseconds
    }

    /// Mark the end of the current phase.
    public func endPhase() {
        guard let name = currentPhaseName else { return }
        let endTime = DispatchTime.now().uptimeNanoseconds
        records.append(PhaseRecord(
            name: name,
            startTime: currentPhaseStart,
            endTime: endTime
        ))
        currentPhaseName = nil
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

    /// Print a human-readable timing summary to stderr.
    public func printSummary() {
        let total = totalMs
        FileHandle.standardError.write(Data("===== Phase Timing Summary =====\n".utf8))
        let header = String(format: "%-20s %10s %8s\n", "Phase", "Time (ms)", "%")
        FileHandle.standardError.write(Data(header.utf8))
        let separator = String(repeating: "-", count: 42) + "\n"
        FileHandle.standardError.write(Data(separator.utf8))

        for record in records {
            let ms = record.durationMs
            let pct = total > 0 ? (ms / total) * 100.0 : 0.0
            let line = String(format: "%-20s %10.2f %7.1f%%\n", record.name, ms, pct)
            FileHandle.standardError.write(Data(line.utf8))
        }

        FileHandle.standardError.write(Data(separator.utf8))
        let totalLine = String(format: "%-20s %10.2f %7.1f%%\n", "TOTAL", total, 100.0)
        FileHandle.standardError.write(Data(totalLine.utf8))
    }

    // MARK: - Machine-readable export

    /// Export timing data as a TSV string.
    ///
    /// Columns: phase, duration_ms, percent
    public func exportTSV() -> String {
        let total = totalMs
        var lines: [String] = ["phase\tduration_ms\tpercent"]
        for record in records {
            let ms = record.durationMs
            let pct = total > 0 ? (ms / total) * 100.0 : 0.0
            lines.append("\(record.name)\t\(String(format: "%.2f", ms))\t\(String(format: "%.1f", pct))")
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
            result.append([
                "phase": record.name,
                "duration_ms": round(ms * 100) / 100,
                "percent": round(pct * 10) / 10
            ])
        }
        result.append([
            "phase": "TOTAL",
            "duration_ms": round(total * 100) / 100,
            "percent": 100.0
        ])
        return result
    }
}
