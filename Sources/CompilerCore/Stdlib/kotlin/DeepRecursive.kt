package kotlin

import kotlin.internal.KsSymbolName

// KSP-612: kotlin.DeepRecursiveFunction / kotlin.DeepRecursiveScope migrated to
// bundled Kotlin source. Both types are opaque runtime handles: the recursion
// trampoline (re-entering the block through a runtime-owned scope) is the whole
// reason the bridges exist, so all four entry points stay in the runtime as
// demoted __kk_* bridges (Sources/Runtime/RuntimeDeepRecursive.swift).
//
// The block is modelled as the suspend receiver lambda
// `suspend DeepRecursiveScope<T, R>.(T) -> R` required by Kotlin's public API.
// The runtime calls it with the scope handle as its receiver argument, so
// `callRecursive` is an ordinary member call on that handle rather than a
// compiler special case.

public class DeepRecursiveScope<T, R> private constructor() {
    @KsSymbolName("__kk_deep_recursive_scope_callRecursive")
    public external fun callRecursive(value: T): R

    @KsSymbolName("__kk_deep_recursive_function_callRecursive")
    public external suspend fun <U, S> DeepRecursiveFunction<U, S>.callRecursive(value: U): S

    @Deprecated(
        "Calling invoke directly from a DeepRecursiveScope is prohibited. Use callRecursive instead.",
        ReplaceWith("this.callRecursive(value)"),
        level = DeprecationLevel.ERROR
    )
    public operator fun DeepRecursiveFunction<*, *>.invoke(value: Any?): Nothing =
        throw UnsupportedOperationException("Should not be called from DeepRecursiveScope")
}

public class DeepRecursiveFunction<T, R> {
    @KsSymbolName("__kk_deep_recursive_function_new")
    public constructor(block: suspend DeepRecursiveScope<T, R>.(T) -> R)

    @KsSymbolName("__kk_deep_recursive_function_invoke")
    public external operator fun invoke(value: T): R

    @KsSymbolName("__kk_deep_recursive_function_callRecursive")
    public external fun callRecursive(value: T): R
}
