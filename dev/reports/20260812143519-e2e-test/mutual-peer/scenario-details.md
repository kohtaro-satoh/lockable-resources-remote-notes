### S01: mutual-peer

**Result: PASS** (6 checkpoints, 0 failed)

#### Sequence

- SEQ01 Configure A and B as each other's remote server and client
- SEQ02 Trigger both relays and wait for them to finish

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Remote pair setup | Groovy /scriptText | A->B and B->A configured | A->B and B->A configured | PASS |
| CP02 | A build result | Build API | SUCCESS | SUCCESS | PASS |
| CP03 | B build result | Build API | SUCCESS | SUCCESS | PASS |
| CP04 | A entered the lock body | grep a-console.txt | contains 'A_ACQUIRED' | found | PASS |
| CP05 | B entered the lock body | grep b-console.txt | contains 'B_ACQUIRED' | found | PASS |
| CP06 | Relays ran in parallel | elapsed time | < 60s (one hold, not two) | 44s | PASS |

#### Summary

- a_build_url: http://127.0.0.1:8081/jenkins/job/s01-a-holder/1/
- a_result: SUCCESS
- b_build_url: http://127.0.0.1:8082/jenkins/job/s01-b-holder/1/
- b_result: SUCCESS
- duration_seconds: 44

#### Artifacts

- a-console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260812143519-e2e-test/mutual-peer/a-console.txt
- b-console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260812143519-e2e-test/mutual-peer/b-console.txt

