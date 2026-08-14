### S09: delegated-mode

**Result: PASS** (9 checkpoints, 0 failed)

#### Sequence

- SEQ01 Expose a resource on B, add a local one on A, and link A to B
- SEQ02 Set forcedServerId=b on A and run a lock() that names no serverId
- SEQ03 Clear forcedServerId and run a lock() on a local resource

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Delegated build result | Build API | SUCCESS | SUCCESS | PASS |
| CP02 | Body ran | grep delegated-console.txt | contains 'DELEGATED_ACQUIRED' | found | PASS |
| CP03 | Went over the remote path | grep delegated-console.txt | contains 'Remote lock acquired on' | found | PASS |
| CP04 | Delegated to the configured server | grep delegated-console.txt | contains 'serverId=b' | found | PASS |
| CP05 | Fallback build result | Build API | SUCCESS | SUCCESS | PASS |
| CP06 | Local body ran | grep fallback-console.txt | contains 'LOCAL_ACQUIRED' | found | PASS |
| CP07 | Delegation stopped with the setting | grep fallback-console.txt | does not contain 'Remote lock acquired on' | absent | PASS |
| CP08 | Delegated resource released on B | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |
| CP09 | Local resource released on A | Groovy resource state on a | free: not locked, no lease, not reserved | free | PASS |

#### Summary

- delegated_build_url: http://127.0.0.1:8081/jenkins/job/s09-delegated/1/
- delegated_result: SUCCESS
- fallback_build_url: http://127.0.0.1:8081/jenkins/job/s09-local-fallback/1/
- fallback_result: SUCCESS

#### Artifacts

- delegated console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260813204301-e2e-test/delegated-mode/delegated-console.txt
- fallback console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260813204301-e2e-test/delegated-mode/fallback-console.txt

