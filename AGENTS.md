Nats.raku Agents Guide

Purpose
- This document standardizes how agentic coding tools (Cursor, Copilot, OpenCode, etc.) interact with this repository: how to build, lint, test, and how to write code consistent with the existing style.

Project Overview
- Language: Raku (Rakudo)
- Distribution name: `Nats` (META6.json), a client library for NATS.
- Library modules live under `lib/` (e.g., `lib/Nats.rakumod`, `lib/Nats/Message.rakumod`).
- Tests live in `t/*.rakutest` and use `Test` and `Test::Mock`.
- Examples live in `examples/`.
- Integration tests live in `integration-tests/1/` using Docker Compose.
- CI: `.github/workflows/test.yml` uses `JJ/raku-test-action@v2` with coverage.

Environment Variables
- `NATS_URL`: default server URL used by `Nats.default-url` if set; otherwise `nats://127.0.0.1:4222`.
- `NATS_DEBUG`: when truthy, enables debug logging via `note` in `Nats!debug`.
- `NATS_SERVERS`: comma-separated list of URLs for integration tests.

Build, Install, Lint, Test
- Dependencies
  - Install only dependencies: `zef install --depsonly .`
  - Install the distribution locally: `zef install .`
- Build
  - Raku modules are interpreted; there is no compile step beyond syntax checks.
  - Packaging metadata is in `META6.json`; release process uses `dist.ini` (ReadmeFromPod, UploadToZef, Badges).
- Lint / Syntax Check
  - Per-file syntax check: `raku -c lib/Nats.rakumod`
  - Batch syntax check (examples/tests): `raku -c examples/request.raku` and `raku -c t/nats.rakutest`
  - Optional formatter: if you use `rakufmt`, keep its output consistent with the style rules below; do not auto-format CI unless agreed.
- Run All Tests
  - Using prove6: `prove6 -Ilib -v t/*.rakutest`
  - Using zef: `zef test .`
- Run a Single Test File
  - With prove6: `prove6 -Ilib -v t/message.rakutest`
  - Directly with raku: `raku -Ilib t/message.rakutest`
- Coverage (CI)
  - CI runs `JJ/raku-test-action@v2` with `coverage: true`. Locally, prefer the same test commands; coverage tooling is provided by the action in CI.
- Integration Tests
  - From `integration-tests/1/`: `docker compose up --build`
  - Container `test` uses `ENTRYPOINT ["raku", "/test.raku"]` and requires `nats` service reachable with `NATS_SERVERS`.

Runtime and Concurrency Notes
- Starts use asynchronous sockets (`IO::Socket::Async`) and event supplies (`Supply`, `Supplier`).
- `Nats.start` returns a `Promise`; await it when chaining work that must start after connection.
- Messages are emitted on `Nats.supply`; tap the supply to process messages.
- JetStream helpers live in `lib/Nats/JetStream.rakumod` and use `request`/`reply` patterns.

Code Style Guidelines

Imports and Module Organization
- Place `use` statements at the top of the file, after the `unit class` or `unit grammar` line if present.
- Use fully qualified module names (e.g., `use Nats::Message;`, `use JSON::Fast;`).
- In tests, include library path explicitly: `use lib 'lib';` followed by `use Nats;`.
- Keep module boundaries clear: classes under `Nats::*` go in matching `lib/Nats/*.rakumod` paths and are declared with `unit class Nats::Name;`.

Formatting
- Indentation: 4 spaces; no tabs.
- Line length: target <= 100 chars; wrap thoughtfully without breaking readability.
- Braces: opening brace on the same line; closing brace aligned with the start of the block.
- Spacing: around operators and after commas; avoid trailing whitespace.
- Blank lines: use to separate logical sections (attributes, methods, private helpers).
- Comments: write concise, purposeful comments only when the intent is non-obvious (e.g., protocol framing or parsing assumptions).

Types and Signatures
- Prefer typed attributes and parameters: `has Str $.subject;`, `method publish(Str $subject, Str() $payload = "") { ... }`.
- Use type constraints for optional values: `Str() $payload?` and named parameters for flags and options.
- For numeric counters and IDs, use `UInt` where appropriate (e.g., SIDs, counts).
- Enforce interface capabilities with `where` when needed (e.g., `has $.nats where { .^can('publish') }`).
- Use multi methods when overloading by type or arity makes intent clearer (see `unsubscribe` multis in `lib/Nats.rakumod`).

Naming Conventions
- Modules and classes: `Nats` and `Nats::*` (PascalCase after the top-level namespace).
- Attributes and methods: lower-case with hyphens only when idiomatic to Raku (e.g., `reply-json`), otherwise lower-case with dashes avoided in general-purpose names.
- Constants: UPPERCASE with hyphens or underscores as in `JS-API`, `STREAM-CREATE`; keep consistency with existing JetStream constants.
- Private helpers: prefix with `!` (e.g., `method !print`, `method !debug`); do not expose them in public APIs.
- Test names: human-readable strings in `pass/is/ok` messages that state behavior succinctly.

Error Handling
- Use `Nats::Error is Exception` for domain-specific exceptions when throwing from library code; construct with `:message`.
- In protocol handlers, map NATS `-ERR` messages to exceptions (current code uses `die $cmd.data`). Prefer explicit `die Nats::Error.new(:message($cmd.data))` when enhancing error semantics.
- Do not swallow exceptions silently; emit them or fail the promise/supply appropriately.
- For recoverable states (e.g., `PING`/`PONG` flow), keep logic non-throwing and side-effectful as implemented.

Logging and Debugging
- Use `self!debug(*@msg)` for structured debug output; it checks `NATS_DEBUG` and writes with `note`.
- Do not leave `say/diag` calls in library code unless behind debug flags; tests can use `diag`.

Protocol and Parsing
- Grammar: define parsing in `unit grammar` (`lib/Nats/Grammar.rakumod`); keep tokens small and purposeful.
- Actions: construct domain objects in `Nats::Actions` with `make` and typed values (e.g., `:+$<sid>` to `UInt`).
- Keep message framing rules explicit: size-limited payload, CRLF boundaries, and optional `reply-to` subjects.

Concurrency and Supplies
- Subscribe flow: create `Nats::Subscription`, attach a filtered `Supply` using `messages-from-supply`, tap and dispatch to user blocks.
- Unsubscribe by signaling via `UNSUB` with optional `:max-messages` and deleting SID from registry.
- When writing new reactive flows, prefer `react/whenever` or `Supply.tap` consistent with existing patterns.

JSON Handling
- Use `JSON::Fast` exclusively for JSON encode/decode; prefer `to-json` for emitting and `from-json` for parsing.
- Keep JSON payloads as `Str` in `Nats::Message`; expose `.json` to parse lazily and throw on invalid JSON.

JetStream Helpers
- Use `sprintf` formatting for subject templates (`method subject`) to avoid manual string assembly.
- Stream and Consumer configuration should return maps convertible with `to-json` and keep defaults aligned with NATS expectations.

Testing Practices
- Tests live under `t/` and use `use lib 'lib';` at the top.
- Mock IO and dependencies with `Test::Mock` as in current tests (`mocked IO::Socket::Async`, `mocked Nats`).
- Prefer `use-ok`, `can-ok`, `isa-ok`, `lives-ok`, `dies-ok`, `check-mock` idioms already present.
- Keep tests deterministic; use `Supplier` to emit messages and verify behaviors.
- For a quick ad-hoc run of a test file: `raku -Ilib t/nats.rakutest`.

Examples and Demos
- Examples under `examples/` demonstrate basic usage with `react`/`whenever` and subscription DSL.
- Run an example: `raku -Ilib examples/request.raku` (ensure NATS server running and `NATS_URL` set if needed).

Repository Conventions
- Do not introduce non-ASCII unless necessary (e.g., literal protocol examples); keep source ASCII by default.
- Keep public API surface stable; add new features under `Nats::*` modules with clear responsibilities.
- Avoid global mutable state except the per-process `@*SUBSCRIPTIONS` in the subscription DSL; reset it in `subscriptions(&block)` as implemented.

CI and Automation
- CI uses `.github/workflows/test.yml`:
  - `JJ/raku-test-action@v2` with `coverage: true`.
  - Ensure tests pass locally before pushing.
- Badges and metadata defined via `dist.ini`; leave publishing steps to maintainers.

Cursor / Copilot Rules
- No Cursor rules found in `.cursor/rules/` or `.cursorrules`.
- No Copilot instructions found in `.github/copilot-instructions.md`.
- Agents should follow this AGENTS.md for guidance in the absence of tool-specific rule files.

Common Command Cheat Sheet

```sh
# Install dependencies only
zef install --depsonly .

# Install locally
zef install .

# Syntax-check core modules
raku -c lib/Nats.rakumod
raku -c lib/Nats/Message.rakumod

# Run all tests with verbose output
prove6 -Ilib -v t/*.rakutest

# Run a single test file
prove6 -Ilib -v t/message.rakutest
# or
raku -Ilib t/message.rakutest

# Run an example (requires NATS server)

# Integration test (docker compose)
cd integration-tests/1
docker compose up --build
```

When In Doubt
- Mirror existing patterns; do not invent new frameworks or paradigms.
- Prefer explicit types, small methods, and clear protocol boundaries.
- Keep behavior changes minimal; add tests for new features.
