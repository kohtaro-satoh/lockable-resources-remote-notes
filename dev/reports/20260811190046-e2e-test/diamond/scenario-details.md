### D03: diamond

**Result: PASS** (9 checkpoints, 0 failed)

#### Sequence

- SEQ01 Wire the diamond: A->B, A->C, B->D, C->D
- SEQ02 Start B and C contending for D, then A taking B and C
- SEQ03 Check nothing was left held

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | d03-b on b finished | Build API | SUCCESS | SUCCESS | PASS |
| CP02 | d03-b on b entered its lock body | grep d03-b-console.txt | contains 'B_TO_D' | found | PASS |
| CP03 | d03-c on c finished | Build API | SUCCESS | SUCCESS | PASS |
| CP04 | d03-c on c entered its lock body | grep d03-c-console.txt | contains 'C_TO_D' | found | PASS |
| CP05 | d03-a on a finished | Build API | SUCCESS | SUCCESS | PASS |
| CP06 | d03-a on a entered its lock body | grep d03-a-console.txt | contains 'DIAMOND_ACQUIRED' | found | PASS |
| CP07 | B's resource released | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |
| CP08 | C's resource released | Groovy resource state on c | free: not locked, no lease, not reserved | free | PASS |
| CP09 | D's resource released | Groovy resource state on d | free: not locked, no lease, not reserved | free | PASS |

#### Summary

- d03-b_url: http://127.0.0.1:8082/jenkins/job/d03-b/1/
- d03-b_result: SUCCESS
- d03-c_url: http://127.0.0.1:8083/jenkins/job/d03-c/1/
- d03-c_result: SUCCESS
- d03-a_url: http://127.0.0.1:8081/jenkins/job/d03-a/1/
- d03-a_result: SUCCESS

#### Artifacts

- d03-b console (on b): /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260811190046-e2e-test/diamond/d03-b-console.txt
- d03-c console (on c): /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260811190046-e2e-test/diamond/d03-c-console.txt
- d03-a console (on a): /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260811190046-e2e-test/diamond/d03-a-console.txt

