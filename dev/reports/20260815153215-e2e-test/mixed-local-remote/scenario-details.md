### S04: mixed-local-remote

**Result: PASS** (4 checkpoints, 0 failed)

#### Sequence

- SEQ01 Create a local resource on A and an exposed one on B
- SEQ02 Run the nested local + remote lock
- SEQ03 Check both resources were released

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Build result | Build API | SUCCESS | SUCCESS | PASS |
| CP02 | Innermost body ran with both locks held | grep console.txt | contains 'BOTH_ACQUIRED' | found | PASS |
| CP03 | Local resource released on A | Groovy resource state on a | free: not locked, no lease, not reserved | free | PASS |
| CP04 | Remote resource released on B | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |

#### Summary

- build_url: http://127.0.0.1:8081/jenkins/job/s04-mixed-lock/1/
- result: SUCCESS
- local_resource: s04-local-a-1786775713
- remote_resource: s04-remote-b-1786775713

#### Artifacts

- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260815153215-e2e-test/mixed-local-remote/console.txt

