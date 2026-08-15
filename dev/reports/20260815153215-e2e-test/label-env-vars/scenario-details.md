### S08: label-env-vars

**Result: PASS** (6 checkpoints, 0 failed)

#### Sequence

- SEQ01 Expose a labelled resource on B and link A to it
- SEQ02 Acquire by label with variable: 'HW_LOCK'

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Build result | Build API | SUCCESS | SUCCESS | PASS |
| CP02 | Combined variable names the matched resource | lockEnvVars HW_LOCK | s08-hw-board-1786775887 | s08-hw-board-1786775887 | PASS |
| CP03 | Indexed variable is set | lockEnvVars HW_LOCK0 | s08-hw-board-1786775887 | s08-hw-board-1786775887 | PASS |
| CP04 | One match means V equals V0 | local lock() equivalence | s08-hw-board-1786775887 | s08-hw-board-1786775887 | PASS |
| CP05 | Went over the remote path | grep console.txt | contains 'Remote lock acquired on' | found | PASS |
| CP06 | Resource released on B | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |

#### Summary

- build_url: http://127.0.0.1:8081/jenkins/job/s08-label-env/1/
- result: SUCCESS
- HW_LOCK: s08-hw-board-1786775887
- HW_LOCK0: s08-hw-board-1786775887

#### Artifacts

- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260815153215-e2e-test/label-env-vars/console.txt

