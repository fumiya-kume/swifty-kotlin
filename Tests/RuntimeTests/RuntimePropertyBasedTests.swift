@testable import Runtime
import XCTest

final class RuntimePropertyBasedTests: XCTestCase {
    private struct PropertyStats: Equatable {
        let checked: Int
        let failures: Int
        let shrinks: Int
        let minimizedCounterexample: Int?
    }

    private func seededSamples(seed: Int, count: Int) -> [Int] {
        let random = kk_random_create_seeded(seed)
        return (0..<count).map { _ in kk_random_nextInt_range(random, -32, 33, nil) }
    }

    private func shrinkTowardZero(_ value: Int) -> Int? {
        guard value != 0 else {
            return nil
        }
        let next = value / 2
        return next == value ? nil : next
    }

    private func runPropertyCheck(
        samples: [Int],
        predicate: (Int) -> Bool
    ) -> PropertyStats {
        var checked = 0
        var shrinks = 0

        for sample in samples {
            checked += 1
            if predicate(sample) {
                continue
            }

            var current = sample
            var minimized = sample

            while let next = shrinkTowardZero(current), next != current {
                if predicate(next) {
                    break
                }
                shrinks += 1
                minimized = next
                current = next
            }

            return PropertyStats(
                checked: checked,
                failures: 1,
                shrinks: shrinks,
                minimizedCounterexample: minimized
            )
        }

        return PropertyStats(
            checked: checked,
            failures: 0,
            shrinks: 0,
            minimizedCounterexample: nil
        )
    }

    func testPropertyCheckReportsSuccessAcrossGeneratedSamples() {
        let samples = seededSamples(seed: 42, count: 32)
        let stats = runPropertyCheck(samples: samples) { sample in
            sample + 0 == sample
        }

        XCTAssertEqual(stats.checked, 32)
        XCTAssertEqual(stats.failures, 0)
        XCTAssertEqual(stats.shrinks, 0)
        XCTAssertNil(stats.minimizedCounterexample)
    }

    func testPropertyCheckShrinksCounterexamplesTowardZero() {
        let samples = [13] + seededSamples(seed: 31415, count: 15).map { abs($0 % 17) * 2 + 1 }
        let stats = runPropertyCheck(samples: samples) { sample in
            sample == 0
        }

        XCTAssertEqual(stats.checked, 1)
        XCTAssertEqual(stats.failures, 1)
        XCTAssertEqual(stats.shrinks, 3)
        XCTAssertEqual(stats.minimizedCounterexample, 1)
    }

    func testSeededSampleGenerationIsDeterministic() {
        let samplesA = seededSamples(seed: 2026, count: 8)
        let samplesB = seededSamples(seed: 2026, count: 8)
        let samplesC = seededSamples(seed: 2027, count: 8)

        XCTAssertEqual(samplesA, samplesB)
        XCTAssertNotEqual(samplesA, samplesC)
    }
}
