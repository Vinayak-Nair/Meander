import Foundation

/// Renders the eval results as a human-readable Markdown report: a model
/// comparison table up top (pass rate + latency), then a per-case breakdown so
/// you can read the actual outputs and judge the fuzzy rules yourself.
enum ReportWriter {
    static func markdown(reports: [ProviderReport], caseCount: Int) -> String {
        var md = ""
        md += "# Meander cleanup eval\n\n"
        md += "_Generated \(timestamp()) · \(caseCount) contract cases · median of timed runs_\n\n"

        md += modelComparisonTable(reports)
        md += "\n"
        md += ruleBreakdown(reports)
        md += "\n"
        md += perCaseDetail(reports)
        return md
    }

    // MARK: Summary table — models side by side

    private static func modelComparisonTable(_ reports: [ProviderReport]) -> String {
        var md = "## Models at a glance\n\n"
        md += "| Model | Contract pass | Avg | p50 | p95 | Network |\n"
        md += "|---|---|---|---|---|---|\n"
        for r in reports {
            let pass = "\(r.passed)/\(r.total) (\(pct(r.passRate)))"
            md += "| \(r.name) | \(pass) | \(ms(r.avgLatencyMs)) | \(ms(r.p50LatencyMs)) | \(ms(r.p95LatencyMs)) | \(r.requiresNetwork ? "yes" : "no") |\n"
        }
        return md
    }

    // MARK: Which rules each model struggles with

    private static func ruleBreakdown(_ reports: [ProviderReport]) -> String {
        var md = "## Failures by rule\n\n"
        md += "| Rule | " + reports.map(\.name).joined(separator: " | ") + " |\n"
        md += "|---" + String(repeating: "|---", count: reports.count) + "|\n"

        // Preserve first-seen rule order across all providers.
        var ruleOrder: [String] = []
        for r in reports { for res in r.results where !ruleOrder.contains(res.rule) { ruleOrder.append(res.rule) } }

        for rule in ruleOrder {
            var row = "| \(rule) "
            for r in reports {
                let cases = r.results.filter { $0.rule == rule }
                let failed = cases.filter { !$0.passed }.count
                row += failed == 0 ? "| ✅ " : "| ❌ \(failed) "
            }
            md += row + "|\n"
        }
        return md
    }

    // MARK: Per-case detail — read the actual outputs

    private static func perCaseDetail(_ reports: [ProviderReport]) -> String {
        var md = "## Per-case detail\n\n"
        guard let first = reports.first else { return md }

        for (i, sample) in first.results.enumerated() {
            md += "### \(sample.caseName) — _\(sample.rule)_\n\n"
            md += "> **In:** \(inlineText(sample.input))\n\n"
            md += "| Model | Output | Verdict | Latency |\n"
            md += "|---|---|---|---|\n"
            for r in reports {
                guard i < r.results.count else { continue }
                let res = r.results[i]
                let verdict = res.passed ? "✅ pass" : "❌ " + res.failures.joined(separator: "; ")
                md += "| \(r.name) | \(inlineText(res.output)) | \(verdict) | \(ms(res.latencyMs)) |\n"
            }
            md += "\n"
        }
        return md
    }

    // MARK: Formatting helpers

    private static func pct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }

    private static func ms(_ x: Double) -> String {
        if x < 1 { return String(format: "%.2f ms", x) }
        if x < 1000 { return String(format: "%.0f ms", x) }
        return String(format: "%.2f s", x / 1000)
    }

    /// Makes text safe for a single Markdown table cell: escape pipes, show
    /// newlines as ⏎ so a paragraph break stays visible on one line.
    private static func inlineText(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ⏎ ")
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date())
    }
}
