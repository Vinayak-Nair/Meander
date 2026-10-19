# Project context index

Start with [AGENTS.md](../AGENTS.md) and [CONTRIBUTING.md](../CONTRIBUTING.md). Explicitly read the documents needed for the current task: this index does not recursively load them.

| Document | Purpose | When to read |
| --- | --- | --- |
| [Architecture](architecture.md) | Entry points, data flow, module and privacy boundaries | Before cross-module or lifecycle work |
| [Workflows](workflows.md) | Commands, prerequisites, side effects, verification status | Before builds, tests, evaluations, or manual checks |
| [Implementer](agents/implementer.md) | Bounded Swift changes and regression tests | When implementing an approved change |
| [Reviewer](agents/reviewer.md) | Independent read-only correctness review | Before accepting a change |
| [Tester](agents/tester.md) | Reproduction and evidence-based validation | When verifying behavior or coverage |
| [Speech pipeline specialist](agents/speech-pipeline-specialist.md) | Audio/STT/vocabulary/language/latency analysis | When changing dictation quality or backend behavior |

## Routing and delegation

Use the implementer as the change owner. Bring in the speech specialist for domain analysis, the tester for execution evidence, and a separate reviewer for independent findings. Do not create a standing team for every small task.

Supply each worker with its full role contract and a self-contained task: relevant source paths, evidence, allowed writes, acceptance checks, and expected output. Keep parallel writes disjoint; serialize edits to shared files. The coordinator verifies outputs and resolves conflicts. Read-only prose is not a runtime sandbox.

These roles are portable instructions only. No native harness adapters are installed by this layout. `.claude/launch.json` is an existing launch configuration, not a specialist registry. Personal ancestor instructions stay outside tracked project guidance.
