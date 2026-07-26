import Foundation
import DriftKit

/// Everything the report needs to know about one provider's run over the suite.
struct ProviderReport {
    let name: String
    let requiresNetwork: Bool
    let results: [CaseResult]

    var passed: Int { results.filter(\.passed).count }
    var total: Int { results.count }
    var passRate: Double { total == 0 ? 0 : Double(passed) / Double(total) }

    var avgLatencyMs: Double {
        let xs = results.map(\.latencyMs)
        return xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count)
    }
    var p50LatencyMs: Double { percentile(results.map(\.latencyMs), 0.50) }
    var p95LatencyMs: Double { percentile(results.map(\.latencyMs), 0.95) }
}

/// A cleanup provider paired with a display name for the report.
struct NamedProvider {
    let name: String
    let provider: CleanupProvider
}

enum EvalRunner {
    /// Runs every case through every provider. Each cleanup call is timed
    /// `repeats` times and the median is recorded, so a one-off hitch (GC, a
    /// cold cache) doesn't dominate the reported latency.
    static func run(
        providers: [NamedProvider],
        cases: [ContractCase],
        repeats: Int = 3
    ) async -> [ProviderReport] {
        var reports: [ProviderReport] = []
        for named in providers {
            print("Running \(named.name) over \(cases.count) cases…")
            var results: [CaseResult] = []
            for c in cases {
                var timings: [Double] = []
                var lastOutput = ""
                for _ in 0..<max(1, repeats) {
                    let start = DispatchTime.now()
                    let output = (try? await named.provider.clean(c.input, language: .english)) ?? "<error>"
                    let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
                    timings.append(ms)
                    lastOutput = output
                }
                results.append(CaseResult(
                    caseName: c.name,
                    rule: c.rule,
                    input: c.input,
                    output: lastOutput,
                    failures: ContractChecker.failures(for: c, output: lastOutput),
                    latencyMs: median(timings)
                ))
            }
            reports.append(ProviderReport(
                name: named.name,
                requiresNetwork: named.provider.requiresNetwork,
                results: results
            ))
        }
        return reports
    }
}

// MARK: - Small stats helpers

private func median(_ xs: [Double]) -> Double { percentile(xs, 0.50) }

private func percentile(_ xs: [Double], _ p: Double) -> Double {
    guard !xs.isEmpty else { return 0 }
    let sorted = xs.sorted()
    let rank = p * Double(sorted.count - 1)
    let low = Int(rank.rounded(.down))
    let high = Int(rank.rounded(.up))
    if low == high { return sorted[low] }
    let weight = rank - Double(low)
    return sorted[low] * (1 - weight) + sorted[high] * weight
}
