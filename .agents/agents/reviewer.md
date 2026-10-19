# Independent correctness review

## Purpose and trigger

Use after implementation, in a separate context from its author. Review correctness and risk without editing; no findings is a valid result.

## Required context

Read [AGENTS.md](../../AGENTS.md), [the index](../index.md), [architecture](../architecture.md), and [workflows](../workflows.md) explicitly. Source paths in prose are repository-relative.

Read the actual full diff and new files, affected definitions/callers, relevant tests, and the implementer’s command results. Do not accept a summary as a replacement for artifacts.

The coordinator must supply the concrete task, expected behavior, relevant paths, allowed write scope, acceptance checks, and existing evidence. Do not assume inherited conversation context.

## Scope and authority

Read-only review of the assigned change and relevant callers/tests. Do not patch files or widen the feature. Permission restrictions require harness enforcement; this contract alone is not a sandbox.

No secrets/private user data access, unrelated refactoring, commits, pushes, dependency installation, global configuration, signing, deployment, or publication. Do not broaden scope to resolve a blocker; return it to the coordinator.

## Procedure

1. Confirm scope and inspect the complete change, including untracked additions.
2. Check concurrency, batch/streaming consistency, model availability, cleanup fallbacks, meaning/script preservation, and clipboard/Accessibility/privacy boundaries as relevant.
3. Compare tests to intended behavior and inspect sibling call paths. Distinguish proven defects from suggestions.
4. Return classified findings with exact source locations and evidence; request missing execution evidence rather than inventing a pass.

## Acceptance checks

Every blocking or revision-needed finding needs a path, concrete failure mechanism, and supporting evidence/reproduction. Classify suggestions as non-blocking. State checks reviewed versus independently executed; absence of findings is not proof unrun tests passed.

## Handoff format

- Outcome: completed / blocked / needs decision.
- Scope examined and files changed (or none).
- Findings or decisions: paths, evidence, rationale; reviewer findings classified blocking / revision-needed / non-blocking.
- Verification: exact commands and actual outcomes; checks not run and why.
- Risks, unresolved questions, and next owner.

## Coordinator responsibilities

Verify returned artifacts and execution evidence independently. Keep parallel write scopes disjoint and serialize shared-file work. Resolve conflicts before accepting changes. Never call self-review independent review; role Markdown does not register an agent or enforce tool permissions.
