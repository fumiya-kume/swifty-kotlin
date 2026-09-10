/*
 * Copyright 2010-2023 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license
 * that can be found in the LICENSE file.
 *
 * Derived from kotlin-native/runtime/src/main/kotlin/kotlin/native/concurrent/WorkerBoundReference.kt.
 */

package kotlin.native.concurrent

// KSP-1252: Keep the top-level constructor source-backed. The value and worker
// properties remain in the separate KSP-1253 receiver slice.
@ObsoleteWorkersApi
@Deprecated("Support for the legacy memory manager has been completely removed. Use the referenced value directly.")
@DeprecatedSinceKotlin(errorSince = "2.1")
public class WorkerBoundReference<out T : Any>(value: T)
