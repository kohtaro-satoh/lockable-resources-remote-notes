### S06: three-way-mesh

**Result: PASS** (10 checkpoints, 0 failed)

#### Sequence

- SEQ01 Wire the ring: A->B, B->C, C->A
- SEQ02 Run all three legs at once
- SEQ03 Check the ring left nothing held

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | s06-a-to-b on a finished | Build API | SUCCESS | SUCCESS | PASS |
| CP02 | s06-a-to-b on a entered its lock body | grep s06-a-to-b-console.txt | contains 'A_ACQUIRED' | found | PASS |
| CP03 | s06-b-to-c on b finished | Build API | SUCCESS | SUCCESS | PASS |
| CP04 | s06-b-to-c on b entered its lock body | grep s06-b-to-c-console.txt | contains 'B_ACQUIRED' | found | PASS |
| CP05 | s06-c-to-a on c finished | Build API | SUCCESS | SUCCESS | PASS |
| CP06 | s06-c-to-a on c entered its lock body | grep s06-c-to-a-console.txt | contains 'C_ACQUIRED' | found | PASS |
| CP07 | A's resource released | Groovy resource state on a | free: not locked, no lease, not reserved | free | PASS |
| CP08 | B's resource released | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |
| CP09 | C's resource released | Groovy resource state on c | free: not locked, no lease, not reserved | free | PASS |
| CP10 | Legs ran in parallel | elapsed time | < 45s (one hold, not three) | 46s | WARN |

#### Summary

- s06-a-to-b_url: http://127.0.0.1:8081/jenkins/job/s06-a-to-b/1/
- s06-a-to-b_result: SUCCESS
- s06-b-to-c_url: http://127.0.0.1:8082/jenkins/job/s06-b-to-c/1/
- s06-b-to-c_result: SUCCESS
- s06-c-to-a_url: http://127.0.0.1:8083/jenkins/job/s06-c-to-a/1/
- s06-c-to-a_result: SUCCESS
- duration_seconds: 46

#### Artifacts

- s06-a-to-b console (on a): /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260815153215-e2e-test/three-way-mesh/s06-a-to-b-console.txt
- s06-b-to-c console (on b): /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260815153215-e2e-test/three-way-mesh/s06-b-to-c-console.txt
- s06-c-to-a console (on c): /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260815153215-e2e-test/three-way-mesh/s06-c-to-a-console.txt

