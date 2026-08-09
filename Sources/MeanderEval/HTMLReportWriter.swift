import Foundation

/// Renders the eval as a self-contained, theme-aware HTML page: a model
/// comparison strip, a pass/fail matrix by rule, and per-case detail with the
/// actual outputs. No external assets — inline CSS only — so it opens anywhere
/// and regenerates on every `swift run meander-eval`.
enum HTMLReportWriter {
    static func html(reports: [ProviderReport], caseCount: Int) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Meander cleanup eval</title>
        <style>\(css)</style>
        </head>
        <body>
        <main>
          <header class="page-head">
            <h1>Meander cleanup eval</h1>
            <p class="sub">\(timestamp()) · \(caseCount) contract cases · median of timed runs</p>
          </header>
          \(modelCards(reports))
          \(ruleMatrix(reports))
          \(perCaseDetail(reports))
        </main>
        </body>
        </html>
        """
    }

    // MARK: Model comparison cards

    private static func modelCards(_ reports: [ProviderReport]) -> String {
        let cards = reports.map { r -> String in
            let rate = Int((r.passRate * 100).rounded())
            let tone = rate >= 80 ? "good" : (rate >= 55 ? "warn" : "bad")
            return """
            <div class="card">
              <div class="card-name">\(esc(r.name))\(r.requiresNetwork ? "<span class=\"tag\">network</span>" : "")</div>
              <div class="rate \(tone)">\(rate)<span class="pct">%</span></div>
              <div class="rate-bar"><span style="width:\(rate)%"></span></div>
              <div class="card-stats">
                <div><span class="k">Passed</span><span class="v">\(r.passed)/\(r.total)</span></div>
                <div><span class="k">Avg</span><span class="v">\(ms(r.avgLatencyMs))</span></div>
                <div><span class="k">p95</span><span class="v">\(ms(r.p95LatencyMs))</span></div>
              </div>
            </div>
            """
        }.joined(separator: "\n")
        return "<section><h2>Models at a glance</h2><div class=\"cards\">\(cards)</div></section>"
    }

    // MARK: Failures-by-rule matrix

    private static func ruleMatrix(_ reports: [ProviderReport]) -> String {
        var ruleOrder: [String] = []
        for r in reports { for res in r.results where !ruleOrder.contains(res.rule) { ruleOrder.append(res.rule) } }

        let head = "<tr><th class=\"rule-col\">Rule</th>" + reports.map { "<th>\(esc($0.name))</th>" }.joined() + "</tr>"
        let rows = ruleOrder.map { rule -> String in
            var cells = "<td class=\"rule-col\">\(esc(rule))</td>"
            for r in reports {
                let cases = r.results.filter { $0.rule == rule }
                let failed = cases.filter { !$0.passed }.count
                cells += failed == 0
                    ? "<td class=\"cell pass\">✓</td>"
                    : "<td class=\"cell fail\">✗<span class=\"n\">\(failed)</span></td>"
            }
            return "<tr>\(cells)</tr>"
        }.joined()
        return "<section><h2>Failures by rule</h2><div class=\"scroll\"><table class=\"matrix\">\(head)\(rows)</table></div></section>"
    }

    // MARK: Per-case detail

    private static func perCaseDetail(_ reports: [ProviderReport]) -> String {
        guard let first = reports.first else { return "" }
        let blocks = first.results.enumerated().map { (i, sample) -> String in
            let rows = reports.compactMap { r -> String? in
                guard i < r.results.count else { return nil }
                let res = r.results[i]
                let verdict = res.passed
                    ? "<span class=\"chip pass\">pass</span>"
                    : "<span class=\"chip fail\">\(esc(res.failures.joined(separator: " · ")))</span>"
                return """
                <tr>
                  <td class="m">\(esc(r.name))</td>
                  <td class="out"><code>\(esc(res.output))</code></td>
                  <td>\(verdict)</td>
                  <td class="lat">\(ms(res.latencyMs))</td>
                </tr>
                """
            }.joined()
            return """
            <div class="case">
              <div class="case-head"><span class="case-name">\(esc(sample.caseName))</span><span class="case-rule">\(esc(sample.rule))</span></div>
              <div class="case-in"><span class="in-label">in</span><code>\(esc(sample.input))</code></div>
              <table class="io"><tr><th>Model</th><th>Output</th><th>Verdict</th><th>Latency</th></tr>\(rows)</table>
            </div>
            """
        }.joined(separator: "\n")
        return "<section><h2>Per-case detail</h2>\(blocks)</section>"
    }

    // MARK: Formatting

    private static func ms(_ x: Double) -> String {
        if x < 1 { return String(format: "%.2f ms", x) }
        if x < 1000 { return String(format: "%.0f ms", x) }
        return String(format: "%.2f s", x / 1000)
    }

    private static func timestamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date())
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<span class=\"nl\">⏎</span>")
    }

    // MARK: Styles

    private static let css = """
    :root{
      --bg:#f6f7f5; --panel:#ffffff; --ink:#1a1d1a; --ink-2:#5c6560; --line:#e4e7e3;
      --accent:#2f7d4f; --good:#2f7d4f; --good-bg:#e8f3ec; --warn:#b6791f; --warn-bg:#faf1df;
      --bad:#c0413b; --bad-bg:#fbeceb; --code-bg:#f2f4f1; --shadow:0 1px 2px rgba(20,30,20,.06),0 6px 16px rgba(20,30,20,.05);
    }
    @media (prefers-color-scheme:dark){
      :root{
        --bg:#14161a; --panel:#1c1f24; --ink:#e9edea; --ink-2:#98a2a0; --line:#2b2f36;
        --accent:#5cc98a; --good:#5cc98a; --good-bg:#173026; --warn:#e0b060; --warn-bg:#332811;
        --bad:#f0817b; --bad-bg:#331f1e; --code-bg:#23272e; --shadow:0 1px 2px rgba(0,0,0,.3),0 8px 24px rgba(0,0,0,.28);
      }
    }
    *{box-sizing:border-box}
    body{margin:0;background:var(--bg);color:var(--ink);
      font:15px/1.55 -apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",system-ui,sans-serif;
      -webkit-font-smoothing:antialiased;}
    main{max-width:1080px;margin:0 auto;padding:40px 24px 80px}
    .page-head{margin-bottom:32px}
    h1{font-size:26px;font-weight:680;letter-spacing:-.02em;margin:0}
    .sub{color:var(--ink-2);margin:6px 0 0;font-variant-numeric:tabular-nums}
    section{margin-top:40px}
    h2{font-size:13px;font-weight:640;text-transform:uppercase;letter-spacing:.06em;color:var(--ink-2);margin:0 0 16px}
    code{font-family:ui-monospace,"SF Mono",Menlo,monospace;font-size:13px}
    .nl{color:var(--accent);opacity:.7;padding:0 2px}

    /* Model cards */
    .cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:14px}
    .card{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:18px 18px 16px;box-shadow:var(--shadow)}
    .card-name{font-weight:600;font-size:14px;display:flex;align-items:center;gap:8px;flex-wrap:wrap}
    .tag{font-size:10px;font-weight:600;letter-spacing:.04em;text-transform:uppercase;color:var(--warn);background:var(--warn-bg);padding:2px 6px;border-radius:5px}
    .rate{font-size:38px;font-weight:720;letter-spacing:-.03em;margin:10px 0 2px;font-variant-numeric:tabular-nums}
    .rate .pct{font-size:18px;font-weight:600;margin-left:2px}
    .rate.good{color:var(--good)} .rate.warn{color:var(--warn)} .rate.bad{color:var(--bad)}
    .rate-bar{height:5px;border-radius:99px;background:var(--code-bg);overflow:hidden;margin:8px 0 14px}
    .rate-bar span{display:block;height:100%;background:var(--accent);border-radius:99px}
    .card-stats{display:flex;gap:18px}
    .card-stats .k{display:block;font-size:11px;color:var(--ink-2);text-transform:uppercase;letter-spacing:.04em}
    .card-stats .v{display:block;font-weight:600;font-variant-numeric:tabular-nums;margin-top:2px}

    /* Rule matrix */
    .scroll{overflow-x:auto}
    table.matrix{border-collapse:separate;border-spacing:0;width:100%;background:var(--panel);border:1px solid var(--line);border-radius:12px;overflow:hidden}
    table.matrix th,table.matrix td{padding:9px 12px;text-align:center;border-bottom:1px solid var(--line);font-size:13px}
    table.matrix tr:last-child td{border-bottom:none}
    table.matrix th{font-weight:600;color:var(--ink-2);background:var(--code-bg);font-size:12px}
    .rule-col{text-align:left!important;color:var(--ink)}
    td.cell{font-weight:700}
    td.pass{color:var(--good)} td.fail{color:var(--bad)}
    td.fail .n{font-size:11px;font-weight:600;margin-left:3px;opacity:.8}

    /* Per-case */
    .case{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:16px;margin-bottom:12px;box-shadow:var(--shadow)}
    .case-head{display:flex;align-items:baseline;gap:10px;margin-bottom:10px}
    .case-name{font-weight:640;font-size:14px}
    .case-rule{font-size:12px;color:var(--ink-2)}
    .case-in{background:var(--code-bg);border-radius:8px;padding:8px 12px;margin-bottom:12px;display:flex;gap:10px;align-items:baseline}
    .in-label{font-size:10px;text-transform:uppercase;letter-spacing:.05em;color:var(--ink-2);flex:none;padding-top:1px}
    table.io{width:100%;border-collapse:collapse}
    table.io th{text-align:left;font-size:11px;text-transform:uppercase;letter-spacing:.04em;color:var(--ink-2);font-weight:600;padding:4px 10px 8px;border-bottom:1px solid var(--line)}
    table.io td{padding:9px 10px;border-bottom:1px solid var(--line);vertical-align:top}
    table.io tr:last-child td{border-bottom:none}
    td.m{font-weight:600;white-space:nowrap;font-size:13px}
    td.out code{color:var(--ink)}
    td.lat{font-variant-numeric:tabular-nums;color:var(--ink-2);white-space:nowrap;text-align:right}
    .chip{display:inline-block;font-size:12px;font-weight:600;padding:2px 9px;border-radius:99px;line-height:1.5}
    .chip.pass{color:var(--good);background:var(--good-bg)}
    .chip.fail{color:var(--bad);background:var(--bad-bg);font-weight:500}
    """
}
