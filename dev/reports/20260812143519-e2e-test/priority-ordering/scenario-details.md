### S12: priority-ordering

**Result: PASS** (7 checkpoints, 0 failed)

#### Sequence

- SEQ01 Expose the resource on B and link A to it
- SEQ02 Hold the resource locally on B
- SEQ03 Enqueue the local waiter (priority 0) first, then the remote one (priority 10)
- SEQ04 Release the holder and watch which waiter is promoted

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Holder result | Build API | SUCCESS | SUCCESS | PASS |
| CP02 | Higher priority won over arrival order | Groovy resource state on B, sampled after release | remote | remote | PASS |
| CP03 | Remote waiter result | Build API | SUCCESS | SUCCESS | PASS |
| CP04 | Local waiter result | Build API | SUCCESS | SUCCESS | PASS |
| CP05 | Remote waiter entered its body | grep remote-high-console.txt | contains 'S12_REMOTE_ACQUIRED' | found | PASS |
| CP06 | Local waiter still got its turn | grep local-waiter-console.txt | contains 'S12_LOCAL_ACQUIRED' | found | PASS |
| CP07 | Resource free at the end | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |

#### Summary

- holder_result: SUCCESS
- local_result: SUCCESS
- remote_result: SUCCESS
- first_promoted: remote

#### Artifacts

- holder console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260812143519-e2e-test/priority-ordering/holder-console.txt
- local waiter console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260812143519-e2e-test/priority-ordering/local-waiter-console.txt
- remote waiter console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260812143519-e2e-test/priority-ordering/remote-high-console.txt

