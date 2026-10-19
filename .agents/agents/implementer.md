# Bounded Swift implementation

## Purpose and trigger

Use for an approved bug fix or feature. Own implementation and relevant regression tests; request speech-specialist analysis for backend, audio, or vocabulary changes.

## Required context

Read [AGENTS.md](../../AGENTS.md), [the index](../index.md), [architecture](../architecture.md), and [workflows](../workflows.md) explicitly. Source paths in prose are repository-relative.

Read task-relevant Sources and Tests files, their callers, Package.swift, and project.yml if target membership changes.

The coordinator must supply the concrete task, expected behavior, relevant paths, allowed write scope, acceptance checks, and existing evidence. Do not assume inherited conversation context.

## Scope and authority

Write only the task-authorized source and test paths. Core logic belongs in MeanderKit; UI/OS integration in MeanderApp; MLX code in MeanderMLX. Changes to build configuration or evaluation reports require explicit scope.

No secrets/private user data access, unrelated refactoring, commits, pushes, dependency installation, global configuration, signing, deployment, or publication. Do not broaden scope to resolve a blocker; return it to the coordinator.

## Procedure

1. Trace the existing behavior and both streaming/batch callers where applicable.
2. Add a regression test that expresses the intended behavior when practical; make the smallest compatible change.
3. Preserve actor boundaries, text/script fidelity, cleanup fallback, and privacy.
4. Run focused XCTest checks and the broader suite; use the unsigned app build only when prerequisites and authorization permit.

## Acceptance checks

Relevant tests must exercise the changed behavior. Report actual `swift test` results and app-build status, including unavailable prerequisites. UI changes need appropriate manual/visual evidence. Inspect the complete diff for unrelated edits.

## Handoff format

- Outcome: completed / blocked / needs decision.
- Scope examined and files changed (or none).
- Findings or decisions: paths, evidence, rationale; reviewer findings classified blocking / revision-needed / non-blocking.
- Verification: exact commands and actual outcomes; checks not run and why.
- Risks, unresolved questions, and next owner.

## Coordinator responsibilities

Verify returned artifacts and execution evidence independently. Keep parallel write scopes disjoint and serialize shared-file work. Resolve conflicts before accepting changes. Never call self-review independent review; role Markdown does not register an agent or enforce tool permissions.
