### S05: skip-if-locked

**Result: PASS** (5 checkpoints, 0 failed)

#### Sequence

- SEQ01 Expose the resource on B and link A to it
- SEQ02 Hold the resource locally on B, then ask from A with skipIfLocked

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Holder result | Build API | SUCCESS | SUCCESS | PASS |
| CP02 | Skipping build result | Build API | SUCCESS | SUCCESS | PASS |
| CP03 | Body was skipped, not executed | grep skip-test-console.txt | does not contain 'SKIP_BODY_EXECUTED' | absent | PASS |
| CP04 | Build carried on past the lock step | grep skip-test-console.txt | contains 'SKIP_FLOW_DONE' | found | PASS |
| CP05 | Skip returned instead of queueing | elapsed seconds | < 30 | 11 | PASS |

#### Summary

- holder_build_url: http://127.0.0.1:8082/jenkins/job/s05-local-holder/1/
- holder_result: SUCCESS
- skip_build_url: http://127.0.0.1:8081/jenkins/job/s05-skip-test/1/
- skip_result: SUCCESS
- skip_duration_seconds: 11

#### Artifacts

- holder-console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260811190046-e2e-test/skip-if-locked/local-holder-console.txt
- skip-console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260811190046-e2e-test/skip-if-locked/skip-test-console.txt

