### S03: server-self-use

**Result: PASS** (4 checkpoints, 0 failed)

#### Sequence

- SEQ01 Expose the resource on B and link A to it
- SEQ02 Take the resource locally on B, then ask for it remotely from A

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Local holder result | Build API | SUCCESS | SUCCESS | PASS |
| CP02 | Remote waiter result | Build API | SUCCESS | SUCCESS | PASS |
| CP03 | Remote waiter excluded by the local hold | elapsed seconds | >= 20 | 35 | PASS |
| CP04 | Remote waiter entered the body | grep remote-waiter-console.txt | contains 'REMOTE_WAITER_ACQUIRED' | found | PASS |

#### Summary

- local_build_url: http://127.0.0.1:8082/jenkins/job/s03-local-holder/1/
- local_result: SUCCESS
- remote_build_url: http://127.0.0.1:8081/jenkins/job/s03-remote-waiter/1/
- remote_result: SUCCESS
- remote_wait_seconds: 35

#### Artifacts

- local-holder-console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260814195206-e2e-test/server-self-use/local-holder-console.txt
- remote-waiter-console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260814195206-e2e-test/server-self-use/remote-waiter-console.txt

