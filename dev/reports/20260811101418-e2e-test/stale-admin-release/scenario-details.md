### S13: stale-admin-release

**Result: PASS** (8 checkpoints, 0 failed)

#### Sequence

- SEQ01 Expose the resource on B
- SEQ02 Acquire directly over REST as a client that will never heartbeat
- SEQ03 Queue a local waiter behind the ghost lease
- SEQ04 Wait for the lease to be marked STALE (threshold 60s)
- SEQ05 Check the resource is still held while STALE (fail-closed, no auto-release)
- SEQ06 Force-release as an administrator, the same call the UI button makes
- SEQ07 Check the waiter woke up

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Ghost lease acquired | POST /acquire | 202/ACQUIRED | 202/ACQUIRED | PASS |
| CP02 | Lease reached STALE without heartbeats | RemoteLockManager.find after 50s | STALE | STALE | PASS |
| CP03 | STALE arrived on time | seconds waited | < 90 | 50 | PASS |
| CP04 | Resource still held while STALE | Groovy resource state on b | held by a remote lease | lease=3b03b9ad-b866-4f3b-8351-163c794357a1 | PASS |
| CP05 | Administrator force release | POST /lockable-resources/releaseRemoteLock | ok | ok | PASS |
| CP06 | Waiter result | Build API | SUCCESS | SUCCESS | PASS |
| CP07 | Waiter entered its body | grep waiter-console.txt | contains 'S13_WAITER_ACQUIRED' | found | PASS |
| CP08 | Resource free at the end | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |

#### Summary

- lock_id: 3b03b9ad-b866-4f3b-8351-163c794357a1
- stale_after_seconds: 50
- stale_threshold_seconds: 60
- waiter_result: SUCCESS

#### Artifacts

- acquire response: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260811101418-e2e-test/stale-admin-release/acquire-response.json
- waiter console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260811101418-e2e-test/stale-admin-release/waiter-console.txt

