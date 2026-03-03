package golden.sema

// Matched expect/actual pair
expect fun platform(): String
actual fun platform(): String = "ok"

// Unresolved expect (should emit KSWIFTK-MPP-UNRESOLVED)
expect fun unresolved(): Int
