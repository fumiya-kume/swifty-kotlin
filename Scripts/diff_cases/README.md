# diff_kotlinc regression cases

Run all cases:

```bash
bash Scripts/diff_kotlinc.sh Scripts/diff_cases
```

Cases:

- `hello.kt`: minimal executable smoke case
- `control_when.kt`: `when` with value subject (`Int`)
- `boolean_when.kt`: `when` with `Boolean` subject
- `if_expr.kt`: expression-body `if` function
- `named_default.kt`: named argument + default parameter補完
- `extension_receiver.kt`: extension receiver 呼び出しと `this` 束縛
- `local_var.kt`: block 内 local `val` 宣言と参照
- `local_assign.kt`: block 内 local `var` 再代入
- `loop_basic.kt`: `while` / `do-while` の制御フローと `break` の基本実行
- `array_index.kt`: `IntArray` の index read/write と算術
- `overload.kt`: overload resolution by parameter type
- `string_concat.kt`: string `+` lowering via runtime concat helper
- `val_reassign_error.kt`: local `val` 再代入の compile-error parity
- `zero_null_print.kt`: `println(0)` と `println(null)` の表示分離
- `type_error.kt`: compile-error parity case
- `invoke_operator.kt`: `operator fun invoke` による `obj(args)` 呼び出し（top-level property / object / 式結果）
- `char_escape.kt`: Char escape / Unicode escape の runtime parity（`'\n'`, `'\t'`, `'\\'`, `'\u0041'`）
- `nothing_return_throw.kt`: `Nothing` 分岐の parity（`if` 内 `throw` / `return` による分岐合流）
- `intersection_definitely_non_null.kt`: `T & Any`（definitely non-null）での通常呼び出しと safe-call の parity
- `star_projection.kt`: use-site star projection（`Box<*>`）の型解決 parity
- `generic_typealias.kt`: 循環 typealias（`A = B`, `B = A`）の compile-error parity
- `try_expression.kt`: `try` 式 + `finally` 実行順の parity

The set intentionally includes both successful programs and one compile-error case.
