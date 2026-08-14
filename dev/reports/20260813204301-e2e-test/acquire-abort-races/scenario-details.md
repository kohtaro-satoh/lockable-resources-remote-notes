### B05: acquire-abort-races

**Result: PASS** (10 checkpoints, 0 failed)

#### Sequence

- SEQ01 Expose the resource on B and link A to it
- SEQ02 Case 1: abort a build that is still queued for the resource
- SEQ03 Let the holder finish and check the abandoned request did not take the resource
- SEQ04 Case 2: abort a build that is holding the lease

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | The queued build ends as ABORTED | Build API | ABORTED | ABORTED | PASS |
| CP02 | It never entered the lock body | grep waiter-console.txt | does not contain 'B05_WAITER_IN' | absent | PASS |
| CP03 | Holder finished normally | Build API | SUCCESS | SUCCESS | PASS |
| CP04 | The resource is free, not handed to the aborted build | Groovy resource state on B, after the holder released | free | free | PASS |
| CP05 | The lease is live before the abort | Groovy resource state on b | held by a remote lease | lease=6fe084de-46a6-4933-88b1-dad61359c1b8 | PASS |
| CP06 | The holding build ends as ABORTED | Build API | ABORTED | ABORTED | PASS |
| CP07 | Aborting released the lease | Groovy resource state on B, within 30s of the abort | released | released | PASS |
| CP08 | Time from abort to the resource being free | polled resource state | (observed) | 2s | INFO |
| CP09 | Released well inside the STALE threshold | seconds (STALE would need an administrator) | < 60 | 2 | PASS |
| CP10 | Nothing is left held at the end | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |

#### Summary

- waiter_was_queued_before_abort: false
- waiter_result: ABORTED
- aborted_holder_result: ABORTED
- release_after_abort_seconds: 2
- stale_threshold_seconds: 60

#### Artifacts

- aborted waiter console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260813204301-e2e-test/acquire-abort-races/waiter-console.txt
- holder console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260813204301-e2e-test/acquire-abort-races/holder-console.txt
- aborted holder console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260813204301-e2e-test/acquire-abort-races/aborted-holder-console.txt

