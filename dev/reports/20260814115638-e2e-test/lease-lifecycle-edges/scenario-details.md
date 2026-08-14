### B02: lease-lifecycle-edges

**Result: PASS** (19 checkpoints, 0 failed)

#### Sequence

- SEQ01 Expose two resources on B
- SEQ02 Calls against a lease id that never existed
- SEQ03 Acquire a lease, then act on it after it has ended
- SEQ04 A released record stays readable inside the 120s terminal TTL
- SEQ05 Heartbeat on a lease that is queued rather than held
- SEQ06 Past the TTL the record is gone (waiting out 120s)

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Heartbeat on an unknown lease | HTTP status + errorCode | 410/LOCK_NOT_FOUND | 410/LOCK_NOT_FOUND | PASS |
| CP02 | Poll of an unknown lease | HTTP status + errorCode | 404/LOCK_NOT_FOUND | 404/LOCK_NOT_FOUND | PASS |
| CP03 | Release of an unknown lease is a no-op | POST /lease/{id}/release | 204 | 204 | PASS |
| CP04 | Lease acquired | POST /acquire | 202/ACQUIRED | 202/ACQUIRED | PASS |
| CP05 | Heartbeat on a live lease | POST /lease/{id}/heartbeat | 204 | 204 | PASS |
| CP06 | Release of a live lease | POST /lease/{id}/release | 204 | 204 | PASS |
| CP07 | The resource is free again | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |
| CP08 | Releasing twice is still a no-op | POST /lease/{id}/release (repeat) | 204 | 204 | PASS |
| CP09 | Heartbeat after release is refused | HTTP status + errorCode | 410/LOCK_NOT_FOUND | 410/LOCK_NOT_FOUND | PASS |
| CP10 | A just-released lease still answers | GET /acquire/{id} | 200 | 200 | PASS |
| CP11 | It reports how it ended, not that it vanished | GET /acquire/{id} state/errorCode | FAILED/RELEASED | FAILED/RELEASED | PASS |
| CP12 | Holder lease taken | POST /acquire | 202/ACQUIRED | 202/ACQUIRED | PASS |
| CP13 | A second request for a held resource queues | POST /acquire | 202/QUEUED | 202/QUEUED | PASS |
| CP14 | Heartbeat on a queued request is refused | HTTP status + errorCode | 410/LOCK_NOT_FOUND | 410/LOCK_NOT_FOUND | PASS |
| CP15 | A queued request can be withdrawn | POST /lease/{id}/release | 204 | 204 | PASS |
| CP16 | The withdrawn request did not take the resource | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |
| CP17 | The withdrawn request stays withdrawn | RemoteLockManager.find state | FAILED | FAILED | PASS |
| CP18 | The expired record is no longer readable | HTTP status + errorCode | 404/LOCK_NOT_FOUND | 404/LOCK_NOT_FOUND | PASS |
| CP19 | The record is gone from the manager | RemoteLockManager.find | GONE | GONE | PASS |

#### Summary

- terminal_ttl_seconds: 120
- released_lock_id: 17f796a5-e9d0-4e0c-9b30-a150c6ee22c2
- withdrawn_lock_id: 4a7e5704-0ff7-40dd-ad7a-6b938479d3da

