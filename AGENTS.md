# Repository Guidelines

## Project Structure & Module Organization
This repository is a SwiftPM package named `KSwiftK`.

- `Package.swift`: package definition and targets.
- `Sources/CompilerCore/`: core compiler logic, grouped by pipeline phase:
  - `Lexer/` — tokenization (`KotlinLexer*.swift`, `TokenModel.swift`, `TokenStream.swift`)
  - `Parser/` — CST construction (`KotlinParser*.swift`, `SyntaxArena.swift`)
  - `AST/` — AST from CST (`BuildASTPhase+*.swift`, `AST*Models.swift`, `ASTArena.swift`)
  - `Sema/` — semantic analysis (`TypeCheckSemaPass*.swift`, `DataFlowSemaPass*.swift`, `ConstraintSolver.swift`, `OverloadResolver.swift`, `TypeSystem*.swift`)
  - `KIR/` — Kotlin IR (`BuildKIRPass*.swift`, `KIRModels.swift`)
  - `Lowering/` — desugaring passes (`LoweringPhase.swift`, `*LoweringPass.swift`)
  - `Codegen/` — LLVM IR generation & linking (`LLVMCAPIBackend.swift`, `CodegenPass.swift`, `LinkPass.swift`, `NameMangler.swift`)
  - `Driver/` — pipeline orchestration & infrastructure (`Driver.swift`, `Diagnostics.swift`, `SourceManager.swift`, `Phases.swift`)
- `Sources/KSwiftKCLI/`: command-line entrypoint (`main.swift`) for `kswiftc`.
- `Sources/Runtime/`: runtime support types and APIs.
- `Tests/CompilerCoreTests/`: XCTest-based tests, grouped by phase:
  - `Lexer/`, `Parser/`, `AST/`, `Sema/`, `KIR/`, `Lowering/`, `Codegen/`, `Driver/` — phase-specific tests
  - `Integration/` — end-to-end tests (`SmokeTests`, `GoldenHarnessTests`, `TestSupport`)
  - `GoldenCases/` — golden fixture `.kt` files
- `Scripts/`: helper scripts for verification.
- `spec.md`, `TODO.md`: design notes and current work items.
- `.github/workflows`: CI workflow and gates.

## Build, Test, and Development Commands
Run from repository root.

```bash
swift build
swift build -c release
bash Scripts/swift_test.sh
bash Scripts/swift_test.sh --filter SmokeTests
SWIFT_TEST_WORKERS=4 bash Scripts/swift_test.sh
SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh
```

Run the compiler locally after build:
```bash
.build/debug/kswiftc path/to/file.kt -o out
```

Coverage and compatibility checks used by CI:
```bash
COVERAGE_THRESHOLD=95 Scripts/check_coverage.sh
Scripts/diff_kotlinc.sh [--kswiftc path] [--kotlinc path] path/to/tests
```

## Coding Style & Naming Conventions
- Swift 5.9.
- Indentation: 4 spaces.
- Types/enums/protocols: `UpperCamelCase`; functions/vars: `lowerCamelCase`; test methods: `testXxx...`.
- Keep modules focused (e.g., `CompilerCore`, `KSwiftKCLI`, `Runtime`).
- Preserve existing structure of diagnostic/error code prefixes like `KSWIFTK-*`.
- No repo-wide formatter/linter config is present; follow existing file style and use readable, minimal APIs.

## Testing Guidelines
- Framework: XCTest.
- Primary path: `bash Scripts/swift_test.sh`.
- `Scripts/swift_test.sh` runs tests in parallel by default; tune with `SWIFT_TEST_WORKERS`, or disable with `SWIFT_TEST_PARALLEL=0`.
- Test file names should end with `Tests.swift`, and test methods should describe expected behavior directly.
- For critical behavior changes, prefer adding/adjusting focused coverage tests in `Tests/CompilerCoreTests` and include them in PR notes.
- CI enforces targeted line coverage thresholds (95% by default) in `Scripts/check_coverage.sh`.

## Commit & Pull Request Guidelines
Recent history uses short, imperative-style commit messages (e.g., `Add ...`, `Rewrite ...`).

For PRs:
- Provide a concise summary of the change and motivation.
- Include test commands executed (including coverage/diff scripts when relevant).
- Mention spec or TODO item updates when behavior scope changed.
- Keep changes limited and explain any intentional exclusions.

## Security & Configuration Notes
- This project supports both macOS and Linux (`Package.swift` has no platform restriction; CI runs on both).
- Keep local tooling explicit when needed (`export KSWIFTC=...`, `export KOTLINC=...`, `export JAVA_BIN=...`).
