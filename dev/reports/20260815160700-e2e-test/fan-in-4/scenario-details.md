### D01: fan-in-4

**Result: PASS** (8 checkpoints, 0 failed)

#### Sequence

- SEQ01 Expose one resource on D and point A, B and C at it
- SEQ02 Start all three contenders
- SEQ03 Check the resource was released

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | d01-a on a finished | Build API | SUCCESS | SUCCESS | PASS |
| CP02 | d01-a on a entered its lock body | grep d01-a-console.txt | contains 'A_ACQUIRED' | found | PASS |
| CP03 | d01-b on b finished | Build API | SUCCESS | SUCCESS | PASS |
| CP04 | d01-b on b entered its lock body | grep d01-b-console.txt | contains 'B_ACQUIRED' | found | PASS |
| CP05 | d01-c on c finished | Build API | SUCCESS | SUCCESS | PASS |
| CP06 | d01-c on c entered its lock body | grep d01-c-console.txt | contains 'C_ACQUIRED' | found | PASS |
| CP07 | Contenders were serialised by the lock | elapsed seconds (sum of holds) | >= 30 | 47 | PASS |
| CP08 | Shared resource released on D | Groovy resource state on d | free: not locked, no lease, not reserved | free | PASS |

#### Summary

- d01-a_url: http://127.0.0.1:8081/jenkins/job/d01-a/1/
- d01-a_result: SUCCESS
- d01-b_url: http://127.0.0.1:8082/jenkins/job/d01-b/1/
- d01-b_result: SUCCESS
- d01-c_url: http://127.0.0.1:8083/jenkins/job/d01-c/1/
- d01-c_result: SUCCESS
- duration_seconds: 47
- resource: d01-shared-d-1786779071

#### Artifacts

- d01-a console (on a): /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260815160700-e2e-test/fan-in-4/d01-a-console.txt
- d01-b console (on b): /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260815160700-e2e-test/fan-in-4/d01-b-console.txt
- d01-c console (on c): /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260815160700-e2e-test/fan-in-4/d01-c-console.txt

