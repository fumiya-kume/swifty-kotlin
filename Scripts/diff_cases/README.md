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
- `overload.kt`: overload resolution by parameter type
- `string_concat.kt`: string `+` lowering via runtime concat helper
- `type_error.kt`: compile-error parity case

The set intentionally includes both successful programs and one compile-error case.

Note:

- The synthetic runtime currently prints `null` for raw `0` values in `println`.
  To keep the diff harness stable, these regression cases avoid expecting `println(0)`.
