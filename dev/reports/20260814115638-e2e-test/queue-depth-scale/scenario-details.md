### B07: queue-depth-scale

**Result: PASS** (19 checkpoints, 0 failed)

#### Sequence

- SEQ01 Expose one resource on B - every waiter will want this same one
- SEQ02 Queue depth 1
- SEQ03 Queue depth 10
- SEQ04 Queue depth 50
- SEQ05 Compare promotion latency across depths

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | depth 1: holder took the resource | POST /acquire | ACQUIRED | ACQUIRED | PASS |
| CP02 | depth 1: every waiter was accepted | POST /acquire x1 | 1 | 1 | PASS |
| CP03 | depth 1: every waiter was eventually served | each waiter watched its own lease | 1 | 1 | PASS |
| CP04 | depth 1: promotion latency | holder release -> first waiter served | (observed) | 46ms | INFO |
| CP05 | depth 1: drain time (includes client notice latency) | holder release -> last waiter served | (observed) | 46ms | INFO |
| CP06 | depth 1: resource free afterwards | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |
| CP07 | depth 10: holder took the resource | POST /acquire | ACQUIRED | ACQUIRED | PASS |
| CP08 | depth 10: every waiter was accepted | POST /acquire x10 | 10 | 10 | PASS |
| CP09 | depth 10: every waiter was eventually served | each waiter watched its own lease | 10 | 10 | PASS |
| CP10 | depth 10: promotion latency | holder release -> first waiter served | (observed) | 104ms | INFO |
| CP11 | depth 10: drain time (includes client notice latency) | holder release -> last waiter served | (observed) | 4506ms | INFO |
| CP12 | depth 10: resource free afterwards | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |
| CP13 | depth 50: holder took the resource | POST /acquire | ACQUIRED | ACQUIRED | PASS |
| CP14 | depth 50: every waiter was accepted | POST /acquire x50 | 50 | 50 | PASS |
| CP15 | depth 50: every waiter was eventually served | each waiter watched its own lease | 50 | 50 | PASS |
| CP16 | depth 50: promotion latency | holder release -> first waiter served | (observed) | 313ms | INFO |
| CP17 | depth 50: drain time (includes client notice latency) | holder release -> last waiter served | (observed) | 18260ms | INFO |
| CP18 | depth 50: resource free afterwards | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |
| CP19 | Promotion latency, shallowest vs deepest queue | depth 1 vs depth 50 | (observed) | 46ms vs 313ms | INFO |

#### Summary

- depth_1_served: 1
- depth_1_first_ms: 46
- depth_1_drain_ms: 46
- depth_10_served: 10
- depth_10_first_ms: 104
- depth_10_drain_ms: 4506
- depth_50_served: 50
- depth_50_first_ms: 313
- depth_50_drain_ms: 18260
- depths: 1 10 50
- promotion_ms_shallow: 46
- promotion_ms_deep: 313

#### Artifacts

- scaling measurements: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260814115638-e2e-test/queue-depth-scale/queue-scaling.txt

