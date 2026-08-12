### D02: chain-4

**Result: PASS** (10 checkpoints, 0 failed)

#### Sequence

- SEQ01 Wire the chain: A->B, B->C, C->D
- SEQ02 Run all three legs at once
- SEQ03 Check the chain left nothing held

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | d02-a on a finished | Build API | SUCCESS | SUCCESS | PASS |
| CP02 | d02-a on a entered its lock body | grep d02-a-console.txt | contains 'A_ACQUIRED' | found | PASS |
| CP03 | d02-b on b finished | Build API | SUCCESS | SUCCESS | PASS |
| CP04 | d02-b on b entered its lock body | grep d02-b-console.txt | contains 'B_ACQUIRED' | found | PASS |
| CP05 | d02-c on c finished | Build API | SUCCESS | SUCCESS | PASS |
| CP06 | d02-c on c entered its lock body | grep d02-c-console.txt | contains 'C_ACQUIRED' | found | PASS |
| CP07 | B's resource released | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |
| CP08 | C's resource released | Groovy resource state on c | free: not locked, no lease, not reserved | free | PASS |
| CP09 | D's resource released | Groovy resource state on d | free: not locked, no lease, not reserved | free | PASS |
| CP10 | Legs are independent | elapsed time | < 45s (one hold, not three) | 41s | PASS |

#### Summary

- d02-a_url: http://127.0.0.1:8081/jenkins/job/d02-a/1/
- d02-a_result: SUCCESS
- d02-b_url: http://127.0.0.1:8082/jenkins/job/d02-b/1/
- d02-b_result: SUCCESS
- d02-c_url: http://127.0.0.1:8083/jenkins/job/d02-c/1/
- d02-c_result: SUCCESS
- duration_seconds: 41

#### Artifacts

- d02-a console (on a): /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260812143519-e2e-test/chain-4/d02-a-console.txt
- d02-b console (on b): /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260812143519-e2e-test/chain-4/d02-b-console.txt
- d02-c console (on c): /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260812143519-e2e-test/chain-4/d02-c-console.txt

