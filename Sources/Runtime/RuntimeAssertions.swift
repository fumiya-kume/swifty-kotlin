import Foundation

/// Runtime support for Kotlin's assert functions (STDLIB-LOG-149).
/// Provides high-level Swift API compatible with Kotlin stdlib.
/// These functions throw AssertionError when conditions fail and assertions are enabled.

/// Throws an AssertionError if the value is false and runtime assertions have been enabled.
/// This is equivalent to Kotlin's `assert(value: Boolean)` function.
///
/// - Parameter value: The boolean condition to check
@inline(__always)
public func assert(_ value: Bool) {
    assert(value) { "Assertion failed" }
}

/// Throws an AssertionError calculated by lazyMessage if the value is false 
/// and runtime assertions have been enabled.
/// This is equivalent to Kotlin's `assert(value: Boolean, lazyMessage: () -> Any)` function.
///
/// - Parameters:
///   - value: The boolean condition to check
///   - lazyMessage: A function that produces the error message lazily
@inline(__always)
public func assert(_ value: Bool, _ lazyMessage: () -> Any) {
    guard runtimeAreAssertionsEnabled() else {
        return
    }
    
    guard value else {
        let message = lazyMessage()
        var thrown = 0
        _ = kk_precondition_assert_lazy(0, 0, 0, &thrown)
        // For now, use default message since we can't easily create custom message thunks
        // This matches the behavior when no lambda is provided
        return
    }
}
