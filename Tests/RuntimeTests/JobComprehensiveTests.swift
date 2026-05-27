import Dispatch
@testable import Runtime
import XCTest

final class JobComprehensiveTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }
    
    // MARK: - Job State Transitions Tests
    
    func testJobStateTransitionsCompleteLifecycle() {
        let job = RuntimeJobHandle()
        
        // Initial state: New
        XCTAssertFalse(job.isActiveSnapshot())
        XCTAssertFalse(job.completedSnapshot())
        XCTAssertFalse(job.cancellationSnapshot())
        
        // Start job
        job.markStarted()
        XCTAssertTrue(job.isActiveSnapshot())
        XCTAssertFalse(job.completedSnapshot())
        XCTAssertFalse(job.cancellationSnapshot())
        
        // Complete normally
        XCTAssertTrue(job.complete(with: 42))
        XCTAssertFalse(job.isActiveSnapshot())
        XCTAssertTrue(job.completedSnapshot())
        XCTAssertFalse(job.cancellationSnapshot())
        XCTAssertEqual(job.join(), 42)
    }
    
    func testJobStateTransitionsCancellationLifecycle() {
        let job = RuntimeJobHandle()
        
        // Start job
        job.markStarted()
        XCTAssertTrue(job.isActiveSnapshot())
        
        // Cancel job
        XCTAssertTrue(job.cancel())
        XCTAssertFalse(job.isActiveSnapshot())
        XCTAssertTrue(job.cancellationSnapshot())
        
        // Complete cancellation
        XCTAssertTrue(job.completeCancellationIfNeeded())
        XCTAssertTrue(job.completedSnapshot())
        XCTAssertTrue(job.cancellationSnapshot())
    }
    
    func testJobStateTransitionsExceptionalFailure() {
        let job = RuntimeJobHandle()
        job.markStarted()
        
        let exception = runtimeAllocateThrowable(message: "test error")
        XCTAssertTrue(job.completeExceptionally(with: exception))
        
        XCTAssertFalse(job.isActiveSnapshot())
        XCTAssertTrue(job.completedSnapshot())
        XCTAssertTrue(job.isFailedSnapshot())
        XCTAssertFalse(job.cancellationSnapshot())
        XCTAssertEqual(job.join(), exception)
    }
    
    // MARK: - Job Hierarchy Tests
    
    func testJobParentChildRelationship() {
        let parent = RuntimeJobHandle()
        let child = RuntimeJobHandle()
        
        parent.markStarted()
        child.markStarted()
        
        // Establish parent-child relationship
        child.setParent(parent)
        let childHandle = Int(bitPattern: Unmanaged.passUnretained(child).toOpaque())
        parent.registerChild(childHandle)
        
        // Cancel parent should propagate to child
        XCTAssertTrue(parent.cancel())
        XCTAssertTrue(parent.cancellationSnapshot())
        XCTAssertTrue(child.cancellationSnapshot())
    }
    
    func testJobChildRegistrationAfterParentCancelled() {
        let parent = RuntimeJobHandle()
        let child = RuntimeJobHandle()
        
        parent.markStarted()
        child.markStarted()
        
        // Cancel parent first
        XCTAssertTrue(parent.cancel())
        
        // Then register child - should be cancelled immediately
        child.setParent(parent)
        let childHandle = Int(bitPattern: Unmanaged.passUnretained(child).toOpaque())
        parent.registerChild(childHandle)
        
        XCTAssertTrue(child.cancellationSnapshot())
    }
    
    // MARK: - Job Cancellation Tests
    
    func testJobCancelWithCause() {
        let job = RuntimeJobHandle()
        job.markStarted()
        
        let cause = runtimeAllocateThrowable(message: "cancellation cause")
        XCTAssertTrue(job.cancel(cause: cause))
        
        XCTAssertTrue(job.cancellationSnapshot())
        XCTAssertTrue(job.completeCancellationIfNeeded())
        XCTAssertEqual(job.join(), cause)
    }
    
    func testJobCancelIdempotent() {
        let job = RuntimeJobHandle()
        job.markStarted()
        
        // First cancel should succeed
        XCTAssertTrue(job.cancel())
        
        // Subsequent cancels should return false
        XCTAssertFalse(job.cancel())
        
        let cause = runtimeAllocateThrowable(message: "test")
        XCTAssertFalse(job.cancel(cause: cause))
    }
    
    func testJobCancelAfterComplete() {
        let job = RuntimeJobHandle()
        job.markStarted()
        
        // Complete first
        XCTAssertTrue(job.complete(with: 42))
        XCTAssertTrue(job.completedSnapshot())
        
        // Then cancel should fail
        XCTAssertFalse(job.cancel())
    }
    
    // MARK: - Job Completion Tests
    
    func testJobCompleteIdempotent() {
        let job = RuntimeJobHandle()
        job.markStarted()
        
        // First complete should succeed
        XCTAssertTrue(job.complete(with: 42))
        
        // Subsequent completes should fail
        XCTAssertFalse(job.complete(with: 100))
        XCTAssertFalse(job.completeExceptionally(with: runtimeAllocateThrowable(message: "error")))
    }
    
    func testJobCompleteExceptionallyIdempotent() {
        let job = RuntimeJobHandle()
        job.markStarted()
        
        let exception = runtimeAllocateThrowable(message: "test error")
        XCTAssertTrue(job.completeExceptionally(with: exception))
        
        // Subsequent completions should fail
        XCTAssertFalse(job.complete(with: 42))
        XCTAssertFalse(job.completeExceptionally(with: runtimeAllocateThrowable(message: "another error")))
    }
    
    // MARK: - Job Join Tests
    
    func testJobJoinReturnsCorrectValue() {
        let job = RuntimeJobHandle()
        job.markStarted()
        
        // Normal completion
        XCTAssertTrue(job.complete(with: 123))
        XCTAssertEqual(job.join(), 123)
        
        // Exceptional completion
        let job2 = RuntimeJobHandle()
        job2.markStarted()
        let exception = runtimeAllocateThrowable(message: "error")
        XCTAssertTrue(job2.completeExceptionally(with: exception))
        XCTAssertEqual(job2.join(), exception)
        
        // Cancellation
        let job3 = RuntimeJobHandle()
        job3.markStarted()
        let cause = runtimeAllocateThrowable(message: "cancelled")
        XCTAssertTrue(job3.cancel(cause: cause))
        XCTAssertTrue(job3.completeCancellationIfNeeded())
        XCTAssertEqual(job3.join(), cause)
    }
    
    func testJobAwaitCompletionSameAsJoin() {
        let job = RuntimeJobHandle()
        job.markStarted()
        
        XCTAssertTrue(job.complete(with: 456))
        XCTAssertEqual(job.awaitCompletion(), 456)
        XCTAssertEqual(job.join(), 456)
    }
    
    // MARK: - ABI Function Tests
    
    func testABIJobStateQueries() {
        let job = RuntimeJobHandle()
        let jobHandle = Int(bitPattern: Unmanaged.passRetained(job).toOpaque())
        
        // Initial state
        XCTAssertEqual(kk_job_is_active(jobHandle), 0)
        XCTAssertEqual(kk_job_is_completed(jobHandle), 0)
        XCTAssertEqual(kk_job_is_cancelled(jobHandle), 0)
        XCTAssertEqual(kk_job_is_failed(jobHandle), 0)
        
        // Start job
        job.markStarted()
        XCTAssertEqual(kk_job_is_active(jobHandle), 1)
        XCTAssertEqual(kk_job_is_completed(jobHandle), 0)
        XCTAssertEqual(kk_job_is_cancelled(jobHandle), 0)
        XCTAssertEqual(kk_job_is_failed(jobHandle), 0)
        
        // Complete job
        XCTAssertTrue(job.complete(with: 789))
        XCTAssertEqual(kk_job_is_active(jobHandle), 0)
        XCTAssertEqual(kk_job_is_completed(jobHandle), 1)
        XCTAssertEqual(kk_job_is_cancelled(jobHandle), 0)
        XCTAssertEqual(kk_job_is_failed(jobHandle), 0)
        
        // Clean up
        Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(bitPattern: jobHandle)!).release()
    }
    
    func testABIJobFailedState() {
        let job = RuntimeJobHandle()
        let jobHandle = Int(bitPattern: Unmanaged.passRetained(job).toOpaque())
        
        job.markStarted()
        
        // Complete with exception
        let exception = runtimeAllocateThrowable(message: "test error")
        XCTAssertTrue(job.completeExceptionally(with: exception))
        
        XCTAssertEqual(kk_job_is_active(jobHandle), 0)
        XCTAssertEqual(kk_job_is_completed(jobHandle), 1)
        XCTAssertEqual(kk_job_is_cancelled(jobHandle), 0)
        XCTAssertEqual(kk_job_is_failed(jobHandle), 1)
        
        // Clean up
        Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(bitPattern: jobHandle)!).release()
    }
    
    func testABICancelFunctions() {
        let job = RuntimeJobHandle()
        let jobHandle = Int(bitPattern: Unmanaged.passRetained(job).toOpaque())
        
        job.markStarted()
        
        // Normal cancel
        XCTAssertEqual(kk_job_cancel(jobHandle), 0)
        XCTAssertTrue(job.cancellationSnapshot())
        
        // Clean up
        Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(bitPattern: jobHandle)!).release()
    }
    
    func testABICompleteFunctions() {
        let job = RuntimeJobHandle()
        let jobHandle = Int(bitPattern: Unmanaged.passRetained(job).toOpaque())
        
        job.markStarted()
        
        // Normal complete
        XCTAssertEqual(kk_job_complete(jobHandle, 999), 1)
        XCTAssertTrue(job.completedSnapshot())
        
        // Exceptional complete (new job)
        let job2 = RuntimeJobHandle()
        let job2Handle = Int(bitPattern: Unmanaged.passRetained(job2).toOpaque())
        job2.markStarted()
        
        let exception = runtimeAllocateThrowable(message: "test")
        XCTAssertEqual(kk_job_complete_exceptionally(job2Handle, exception), 1)
        XCTAssertTrue(job2.isFailedSnapshot())
        
        // Clean up
        Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(bitPattern: jobHandle)!).release()
        Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(bitPattern: job2Handle)!).release()
    }
    
    // MARK: - AsyncTask Job Compatibility Tests
    
    func testAsyncTaskJobInterfaceCompatibility() {
        let task = RuntimeAsyncTask()
        let taskHandle = Int(bitPattern: Unmanaged.passRetained(task).toOpaque())
        
        // Initial state
        XCTAssertEqual(kk_job_is_active(taskHandle), 0)
        XCTAssertEqual(kk_job_is_completed(taskHandle), 0)
        XCTAssertEqual(kk_job_is_cancelled(taskHandle), 0)
        
        // Complete task
        task.complete(with: 555)
        XCTAssertEqual(kk_job_is_active(taskHandle), 0)
        XCTAssertEqual(kk_job_is_completed(taskHandle), 1)
        XCTAssertEqual(kk_job_is_cancelled(taskHandle), 0)
        
        // Clean up
        Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(bitPattern: taskHandle)!).release()
    }
    
    // MARK: - Edge Cases Tests
    
    func testJobInvalidHandleHandling() {
        // Invalid handles should not crash
        XCTAssertEqual(kk_job_is_active(0), 0)
        XCTAssertEqual(kk_job_is_completed(0), 1) // Invalid treated as completed
        XCTAssertEqual(kk_job_is_cancelled(0), 1) // Invalid treated as cancelled
        XCTAssertEqual(kk_job_join(0), 0)
        XCTAssertEqual(kk_job_await_completion(0), 0)
    }
    
    func testJobConcurrentAccess() {
        let job = RuntimeJobHandle()
        job.markStarted()
        let jobHandle = Int(bitPattern: Unmanaged.passRetained(job).toOpaque())
        
        let expectation = XCTestExpectation(description: "Concurrent access")
        expectation.expectedFulfillmentCount = 10
        
        // Concurrent state queries
        for _ in 0..<10 {
            DispatchQueue.global().async {
                let active = kk_job_is_active(jobHandle)
                let completed = kk_job_is_completed(jobHandle)
                let cancelled = kk_job_is_cancelled(jobHandle)
                
                // Should not crash and return valid boolean values
                XCTAssertTrue(active == 0 || active == 1)
                XCTAssertTrue(completed == 0 || completed == 1)
                XCTAssertTrue(cancelled == 0 || cancelled == 1)
                
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        // Clean up
        Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(bitPattern: jobHandle)!).release()
    }
}
