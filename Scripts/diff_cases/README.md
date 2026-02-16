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
- `overload.kt`: overload resolution by parameter type
- `string_concat.kt`: string `+` lowering via runtime concat helper
- `val_reassign_error.kt`: local `val` 再代入の compile-error parity
- `zero_null_print.kt`: `println(0)` と `println(null)` の表示分離
- `type_error.kt`: compile-error parity case

The set intentionally includes both successful programs and one compile-error case.
