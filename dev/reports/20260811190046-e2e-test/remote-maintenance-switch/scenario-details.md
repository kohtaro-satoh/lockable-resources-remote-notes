### S22: remote-maintenance-switch

**Result: PASS** (9 checkpoints, 0 failed)

#### Sequence

- SEQ01 B serves two resources and A is its client
- SEQ02 A takes a lease that must survive the pause
- SEQ03 Pause new acquires on B
- SEQ04 A client that meets the pause waits rather than failing
- SEQ05 Check the live lease is untouched
- SEQ06 Resume, and let both builds finish

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | A new acquire is refused while paused | HTTP status + errorCode | 503/ACQUIRES_PAUSED | 503/ACQUIRES_PAUSED | PASS |
| CP02 | The waiter did not get in while paused | grep waiter-while-paused.txt | does not contain 'S22_WAITER_IN' | absent | PASS |
| CP03 | The lease taken before the pause is still held | Groovy resource state on b | held by a remote lease | lease=b2f0a6af-ecbe-4ee8-9aa0-9c6dc99a72fd | PASS |
| CP04 | Waiter result after resuming | Build API | SUCCESS | SUCCESS | PASS |
| CP05 | Waiter finally entered the body | grep waiter-final.txt | contains 'S22_WAITER_IN' | found | PASS |
| CP06 | Holder finished cleanly through the pause | Build API | SUCCESS | SUCCESS | PASS |
| CP07 | Holder released normally | grep holder.txt | contains 'S22_HOLDER_RELEASED' | found | PASS |
| CP08 | Held resource released | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |
| CP09 | Wanted resource released | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |

#### Summary

- holder_result: SUCCESS
- waiter_result: SUCCESS
- paused_acquire_status: 503

#### Artifacts

- refused acquire response: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260811190046-e2e-test/remote-maintenance-switch/acquire-paused.json
- waiter console while paused: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260811190046-e2e-test/remote-maintenance-switch/waiter-while-paused.txt
- waiter console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260811190046-e2e-test/remote-maintenance-switch/waiter-final.txt
- holder console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260811190046-e2e-test/remote-maintenance-switch/holder.txt

