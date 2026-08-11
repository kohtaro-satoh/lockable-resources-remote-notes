### S18: remote-acquire-timeout

**Result: PASS** (9 checkpoints, 0 failed)

#### Sequence

- SEQ01 Expose the resource on B and link A to it
- SEQ02 Hold the resource locally on B for 184s
- SEQ03 Ask remotely with a 124s allocate timeout (past the 120s terminal TTL)

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Holder kept the resource throughout | Build API | SUCCESS | SUCCESS | PASS |
| CP02 | Waiter failed closed | Build API | FAILURE | FAILURE | PASS |
| CP03 | Failure is reported as a clean timeout | grep remote-waiter-console.txt | contains 'LOCK_WAIT_TIMEOUT' | found | PASS |
| CP04 | Not misreported as a lost record | grep remote-waiter-console.txt | does not contain 'server may have restarted' | absent | PASS |
| CP05 | Not misreported as a communication failure | grep remote-waiter-console.txt | does not contain 'Remote API communication failure' | absent | PASS |
| CP06 | Body never ran | grep remote-waiter-console.txt | does not contain 'SHOULD_NOT_RUN' | absent | PASS |
| CP07 | Waiter genuinely waited out its allocate window | elapsed seconds | >= 120 | 135 | PASS |
| CP08 | Timeout fired on its own deadline, not on the holder's release | seconds late against its 124s deadline (holder held 184s) | < 21 | 11 | PASS |
| CP09 | Resource free once the holder finished | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |

#### Summary

- timeout_lateness_seconds: 11
- local_result: SUCCESS
- remote_result: FAILURE
- waiter_allocate_timeout_seconds: 124
- terminal_ttl_seconds: 120
- waiter_wait_seconds: 135

#### Artifacts

- local holder console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260811190046-e2e-test/remote-acquire-timeout/local-holder-console.txt
- remote waiter console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260811190046-e2e-test/remote-acquire-timeout/remote-waiter-console.txt

