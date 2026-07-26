import Foundation
import DriftKit
import DriftMLX

// Cleanup-quality eval. Add a new model as one more NamedProvider and it shows
// up as another column/row in the report.
var providers: [NamedProvider] = [
    NamedProvider(name: "Raw (no cleanup)", provider: PassthroughCleanup()),
    NamedProvider(name: "Deterministic", provider: DeterministicCleanup()),
]

// MLX models are included only when their local dir exists (run
// scripts/fetch-eval-model.sh first), so the eval still works model-free.
let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let mlxModels: [(name: String, id: String, dir: String)] = [
    ("MLX Qwen 0.5B", "mlx-qwen-0.5b", "eval/models/qwen2.5-0.5b-4bit"),
    ("MLX Qwen 1.5B", "mlx-qwen-1.5b", "eval/models/qwen2.5-1.5b-4bit"),
]
for m in mlxModels {
    let dir = cwd.appendingPathComponent(m.dir)
    guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.json").path) else {
        print("Skipping \(m.name) — no model at \(m.dir)")
        continue
    }
    providers.append(NamedProvider(
        name: m.name,
        provider: MLXCleanup(id: m.id, displayName: m.name, modelDirectory: dir)
    ))
}

let cases = EnhancementContractCases.all

let reports = await EvalRunner.run(providers: providers, cases: cases)

// Write next to the repo so it's easy to open and diff across runs. Markdown is
// the diffable source of truth; the HTML is the polished view for eyeballing.
let evalDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("eval")
try? FileManager.default.createDirectory(at: evalDir, withIntermediateDirectories: true)

let mdURL = evalDir.appendingPathComponent("report.md")
let htmlURL = evalDir.appendingPathComponent("report.html")
do {
    try ReportWriter.markdown(reports: reports, caseCount: cases.count)
        .write(to: mdURL, atomically: true, encoding: .utf8)
    try HTMLReportWriter.html(reports: reports, caseCount: cases.count)
        .write(to: htmlURL, atomically: true, encoding: .utf8)
} catch {
    print("Failed to write report: \(error)")
}

// Terminal summary so you get the headline without opening the file.
print("\n=== Cleanup eval ===")
for r in reports {
    print(String(
        format: "%-18@  %2d/%-2d passed  ·  avg %7.2fms  p95 %7.2fms",
        r.name as NSString, r.passed, r.total, r.avgLatencyMs, r.p95LatencyMs
    ))
}
print("\nReports: \(htmlURL.path)\n         \(mdURL.path)")
