# Reproduction and verification

## Purpose and trigger

Use to reproduce a defect, validate regression coverage, or establish evidence for an implemented change. Test execution is distinct from independent code review.

## Required context

Read [AGENTS.md](../../AGENTS.md), [the index](../index.md), [architecture](../architecture.md), and [workflows](../workflows.md) explicitly. Source paths in prose are repository-relative.

Read affected test classes, source behavior, CI, and .agents/workflows.md. For quality work, inspect Sources/MeanderEval/main.swift and the relevant contract cases. Obtain expected behavior and safe test inputs from the coordinator.

The coordinator must supply the concrete task, expected behavior, relevant paths, allowed write scope, acceptance checks, and existing evidence. Do not assume inherited conversation context.

## Scope and authority

May run authorized checks and add or modify tests only within specifically assigned test paths. Do not change production logic to make tests pass. Evaluation report writes, model downloads, device/permission access, and manual app operation need separate authorization.

No secrets/private user data access, unrelated refactoring, commits, pushes, dependency installation, global configuration, signing, deployment, or publication. Do not broaden scope to resolve a blocker; return it to the coordinator.

## Procedure

1. Confirm toolchain and required assets without inspecting secrets or private runtime data.
2. Reproduce with synthetic fixtures where possible; select focused tests, then the broader suite.
3. Use `swift test` for core tests and the documented unsigned app build for app compilation when available. Report blockers explicitly.
4. For `swift run meander-eval`, first obtain approval for tracked report updates; record providers run/skipped and actual quality/latency results.
5. Perform only authorized manual checks in a disposable destination; never silently enable WAV capture.

## Acceptance checks

Return exact commands, exit/results, and passed/failed/blocked/not-run status. Confirm regression assertions encode intended behavior. Prompt-presence tests are not model evaluations; core XCTest does not prove hotkey, paste, permissions, audio hardware, or MLX runtime correctness.

## Handoff format

- Outcome: completed / blocked / needs decision.
- Scope examined and files changed (or none).
- Findings or decisions: paths, evidence, rationale; reviewer findings classified blocking / revision-needed / non-blocking.
- Verification: exact commands and actual outcomes; checks not run and why.
- Risks, unresolved questions, and next owner.

## Coordinator responsibilities

Verify returned artifacts and execution evidence independently. Keep parallel write scopes disjoint and serialize shared-file work. Resolve conflicts before accepting changes. Never call self-review independent review; role Markdown does not register an agent or enforce tool permissions.
