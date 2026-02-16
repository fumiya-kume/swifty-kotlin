# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

KSwiftK is a Kotlin compiler written in Swift, targeting Kotlin 2.3.10 stable features. It compiles Kotlin source code to native executables via LLVM on macOS. The executable is `kswiftc`.

## Build & Test Commands

```bash
swift build                              # Debug build
swift build -c release                   # Release build
swift test                               # Run all tests
swift test --filter SmokeTests           # Quick smoke tests
swift test --filter GoldenHarnessTests   # Golden (snapshot) tests
swift test --filter CompilerCoreTests.BackendPipelineCoverageTests  # Single test class
.build/debug/kswiftc path/to/file.kt -o out  # Run the compiler
```

### Golden Test Update Workflow

```bash
UPDATE_GOLDEN=1 swift test --filter GoldenHarnessTests  # Update golden fixtures
git diff -- Tests/CompilerCoreTests/GoldenCases          # Review changes
```

### kotlinc Regression Diff

```bash
bash Scripts/diff_kotlinc.sh Scripts/diff_cases/hello.kt  # Single case
bash Scripts/diff_kotlinc.sh Scripts/diff_cases             # All cases
```

### Coverage

```bash
COVERAGE_THRESHOLD=95 Scripts/check_coverage.sh  # CI enforces 95% line coverage
```

## Architecture

The compiler follows a sequential multi-phase pipeline defined in `Sources/CompilerCore/Driver.swift`:

```
LoadSources → Lex → Parse → BuildAST → SemaPasses → BuildKIR → Lowering → Codegen → Link
```

### Key Modules

- **CompilerCore** (`Sources/CompilerCore/`): All compiler logic — the bulk of the codebase
- **KSwiftKCLI** (`Sources/KSwiftKCLI/`): CLI entrypoint (`main.swift`)
- **Runtime** (`Sources/Runtime/`): GC, coroutine continuations, async tasks, boxing helpers
- **CLLVM** (`Sources/CLLVM/`): System module bridging LLVM C API

### Compiler Pipeline Details

| Phase | Key Files | Purpose |
|-------|-----------|---------|
| Lexer | `KotlinLexer*.swift`, `TokenModel.swift` | Tokenization |
| Parser | `KotlinParser.swift`, `SyntaxArena.swift` | CST construction |
| AST | `BuildASTPhase+*.swift`, `ASTModels.swift` | AST from CST |
| Sema | `TypeCheckSemaPass*.swift`, `DataFlowSemaPass*.swift`, `OverloadResolver.swift`, `ConstraintSolver.swift` | Type checking, data flow, overload resolution |
| KIR | `BuildKIRPass.swift`, `KIRModels.swift` | Typed intermediate representation |
| Lowering | `LoweringPass+*.swift` | Desugaring (for, when, property, inline, coroutine, ABI, etc.) |
| Codegen | `LLVMCAPIBackend.swift`, `CodegenPass.swift` | LLVM IR generation |
| Link | `LinkPass.swift` | Final executable linking |

### Cross-cutting Infrastructure

- **Diagnostics** (`Diagnostics.swift`): Error/warning reporting with `KSWIFTK-*` codes and source ranges
- **SourceManager** (`SourceManager.swift`): Source file management, line/column tracking
- **StringInterner** (in `CompilationContext.swift`): All identifiers/names use interned integer IDs
- **TypeSystem** (`TypeSystem.swift`): Nullability, generics with variance, type inference
- **NameMangler** (`NameMangler.swift`): ABI-stable mangled names including type signatures

### Design Principles

- **ID-based**: All symbol/type references use integer IDs (interned), not string comparisons
- **Deterministic**: Bit-identical output for the same input and options
- **Error resilient**: Never crash on invalid input; always emit diagnostics
- All errors carry diagnostic codes prefixed `KSWIFTK-*`

## Test Structure

- **XCTest** framework, test files in `Tests/CompilerCoreTests/` and `Tests/RuntimeTests/`
- **Golden tests**: `.kt` input files in `Tests/CompilerCoreTests/GoldenCases/{Lexer,Parser,Sema}/`
- **kotlinc regression tests**: Kotlin files in `Scripts/diff_cases/` compared against official `kotlinc` output
- Test helper utilities are in `TestSupport.swift`; the driver exposes `runForTesting()` for diagnostic inspection

## Coding Conventions

- Swift 5.9, macOS 12+, 4-space indentation
- Types/enums/protocols: `UpperCamelCase`; functions/vars: `lowerCamelCase`
- No formatter/linter configured — follow existing file style
- Commit messages: short, imperative style (e.g., "Add ...", "Fix ...")

## Key Reference Documents

- `spec.md`: Detailed implementation specification (Japanese) covering each compiler phase
- `TODO.md`: Task tracking with priority levels P0–P5 (Japanese)
