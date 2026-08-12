### S11: heartbeat-resilience

**Result: PASS** (4 checkpoints, 0 failed)

#### Sequence

- SEQ01 Expose the resource on B and link A to it
- SEQ02 Start a job holding the lock for 40s
- SEQ03 Break heartbeats for 25s (inside the 60s STALE threshold)

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Build result | Build API | SUCCESS | SUCCESS | PASS |
| CP02 | Body ran to completion | grep console.txt | contains 'S11_BODY_END' | found | PASS |
| CP03 | Heartbeats really did fail | docker logs on lrr-jenkins-a | >= 1 | 2 | PASS |
| CP04 | Resource released after the job | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |

#### Summary

- build_url: http://127.0.0.1:8081/jenkins/job/s11-heartbeat/1/
- result: SUCCESS
- outage_seconds: 25
- stale_threshold_seconds: 60
- heartbeat_warning_count: 2

#### Artifacts

- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260812143519-e2e-test/heartbeat-resilience/console.txt
- heartbeat warnings: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260812143519-e2e-test/heartbeat-resilience/heartbeat-warnings.txt

