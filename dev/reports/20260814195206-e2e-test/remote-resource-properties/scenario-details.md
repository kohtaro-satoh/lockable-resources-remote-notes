### S16: remote-resource-properties

**Result: PASS** (6 checkpoints, 0 failed)

#### Sequence

- SEQ01 Expose a resource on B carrying property S16_IP=10.9.8.45, and link A
- SEQ02 Lock it remotely and read the property back inside the body

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Build result | Build API | SUCCESS | SUCCESS | PASS |
| CP02 | Combined variable names the resource | lockEnvVars S16RES | s16-board-1786705345 | s16-board-1786705345 | PASS |
| CP03 | Indexed variable names the resource | lockEnvVars S16RES0 | s16-board-1786705345 | s16-board-1786705345 | PASS |
| CP04 | Property arrived with its value intact | lockEnvVars S16RES0_S16_IP | 10.9.8.45 | 10.9.8.45 | PASS |
| CP05 | Went over the remote path | grep console.txt | contains 'Remote lock acquired on' | found | PASS |
| CP06 | Resource released on B | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |

#### Summary

- build_url: http://127.0.0.1:8081/jenkins/job/s16-props/1/
- result: SUCCESS
- property_value_on_server: 10.9.8.45
- property_value_in_body: 10.9.8.45

#### Artifacts

- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260814195206-e2e-test/remote-resource-properties/console.txt

