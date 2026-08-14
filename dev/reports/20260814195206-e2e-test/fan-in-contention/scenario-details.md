### S02: fan-in-contention

**Result: PASS** (5 checkpoints, 0 failed)

#### Sequence

- SEQ01 Expose the resource on B and link A and C to it
- SEQ02 Start the holder, then the waiter while the holder still has it

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Remote setup | Groovy /scriptText | B exposed, A and C linked | B exposed, A and C linked | PASS |
| CP02 | Holder result | Build API | SUCCESS | SUCCESS | PASS |
| CP03 | Waiter result | Build API | SUCCESS | SUCCESS | PASS |
| CP04 | Waiter queued behind the holder | elapsed seconds | >= 15 | 32 | PASS |
| CP05 | Waiter entered the body after the wait | grep waiter-console.txt | contains 'WAITER_ACQUIRED' | found | PASS |

#### Summary

- holder_build_url: http://127.0.0.1:8081/jenkins/job/s02-holder/1/
- holder_result: SUCCESS
- waiter_build_url: http://127.0.0.1:8083/jenkins/job/s02-waiter/1/
- waiter_result: SUCCESS
- waiter_duration_seconds: 32

#### Artifacts

- holder-console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260814195206-e2e-test/fan-in-contention/holder-console.txt
- waiter-console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260814195206-e2e-test/fan-in-contention/waiter-console.txt

