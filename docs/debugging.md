# Debugging with DWARF Debug Info

This document describes how to use the DWARF debug information emitted by the
`kswiftc` compiler to debug compiled Kotlin programs with `lldb`.

## Prerequisites

- `kswiftc` built from source (`swift build -c release`)
- LLVM C API backend available (dynamically loaded `libLLVM`)
- `lldb` installed (ships with Xcode Command Line Tools on macOS)

## Building with Debug Info

Pass the `-g` flag to enable DWARF debug information in the output object file:

```bash
kswiftc -g -o hello hello.kt
```

This produces an executable with embedded DWARF `.debug_info`, `.debug_line`,
`.debug_abbrev`, and related sections.

### Verifying DWARF Sections

Use `dwarfdump` (macOS) or `llvm-dwarfdump` to inspect the debug info:

```bash
# macOS
dwarfdump hello

# or with llvm-dwarfdump
llvm-dwarfdump --debug-info hello
```

You should see output containing `DW_TAG_compile_unit`, `DW_TAG_subprogram`,
and `DW_TAG_variable` entries.

## Minimal E2E lldb Session

### 1. Create a test program

```kotlin
// hello.kt
fun add(a: Int, b: Int): Int {
    val result = a + b
    return result
}

fun main() {
    val x = add(40, 2)
    println(x)
}
```

### 2. Compile with debug info

```bash
kswiftc -g -o hello hello.kt
```

### 3. Start lldb

```bash
lldb ./hello
```

### 4. Set breakpoints and run

```
(lldb) breakpoint set --file hello.kt --line 3
Breakpoint 1: where = hello`add + XX
(lldb) run
Process XXXXX stopped
* thread #1, stop reason = breakpoint 1.1
    frame #0: hello`add at hello.kt:3
   1    fun add(a: Int, b: Int): Int {
   2        val result = a + b
-> 3        return result
   4    }
```

### 5. Inspect variables and step

```
(lldb) frame variable
(Int) a = 40
(Int) b = 2
(Int) result = 42

(lldb) step
(lldb) continue
```

## What Debug Info is Emitted

The compiler emits the following DWARF metadata when `-g` is enabled:

| DWARF Entity       | Description                                     |
|--------------------|-------------------------------------------------|
| `DICompileUnit`    | One per source file; contains producer and lang  |
| `DIFile`           | Source file path metadata                        |
| `DISubprogram`     | One per function; name, line, scope              |
| `DILocalVariable`  | Parameters and local `val`/`var` declarations    |
| `DILocation`       | Per-instruction source line/column               |

### Source Location Propagation

Source locations flow through the compiler pipeline as follows:

1. **Parser** records `SourceRange` (file, start offset, end offset) for each
   AST expression node.
2. **KIR Lowering** (`ExprLowerer+Part2.swift`) extracts the `SourceRange` from
   each `Expr` and records it in `KIRLoweringEmitContext.instructionLocations`
   as a parallel array alongside the emitted instructions.
3. **KIRFunction** stores both `body` (instructions) and
   `instructionLocations` (per-instruction source ranges).
4. **NativeEmitter** (`NativeEmitter+FunctionEmission.swift`) reads
   `instructionLocations[i]` for each instruction and calls
   `LLVMSetCurrentDebugLocation2` to attach the corresponding `DILocation`.
5. **Fallback**: If per-instruction location is unavailable (e.g., after a
   lowering pass rewrites the body), the emitter falls back to the
   function-level `sourceRange`.

### Local Variable Debug Info

For local variable bindings (detected as `constValue` with `symbolRef` values),
the emitter generates:
- A `DIAutoVariable` via `LLVMDIBuilderCreateAutoVariable`
- An `alloca` + `store` to materialize the value
- A `llvm.dbg.declare` intrinsic via `LLVMDIBuilderInsertDeclareAtEnd`

This allows `lldb` to display local variable names and values in `frame variable`.

## Troubleshooting

### No debug info in output

- Ensure `-g` flag is passed to `kswiftc`
- Verify LLVM C API backend is selected (check for `backend=llvm-c-api` in IR flags)
- Check that `libLLVM` is available and the debug info symbols are loaded

### Breakpoints not resolving

- Use `image lookup -v -n <function_name>` in lldb to check if debug info is present
- Verify with `dwarfdump --debug-line` that line tables are emitted
- Check that the source file path in DWARF matches the file on disk

### Variables showing as optimized out

- Build with `-O0` (default) to disable optimizations
- Some variables may not have debug info if they were eliminated during lowering
