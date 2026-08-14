### S17: remote-unknown-rejected

**Result: PASS** (10 checkpoints, 0 failed)

#### Sequence

- SEQ01 Expose one resource on B, add one that is deliberately not exposed, and link A
- SEQ02 Ask for a resource that does not exist on the server
- SEQ03 Ask for a resource that exists but is not exposed
- SEQ04 Check the server created nothing for either name

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | unknown: build failed | Build API | FAILURE | FAILURE | PASS |
| CP02 | unknown: refused as 404 / UNKNOWN_RESOURCE | grep -E unknown-console.txt | matches /HTTP 404\|UNKNOWN_RESOURCE/ | matched | PASS |
| CP03 | unknown: body never ran | grep unknown-console.txt | does not contain 'S17_BODY_SHOULD_NOT_RUN' | absent | PASS |
| CP04 | unknown: refused immediately, not queued | elapsed seconds | < 60 | 7 | PASS |
| CP05 | unexposed: build failed | Build API | FAILURE | FAILURE | PASS |
| CP06 | unexposed: refused as 404 / UNKNOWN_RESOURCE | grep -E unexposed-console.txt | matches /HTTP 404\|UNKNOWN_RESOURCE/ | matched | PASS |
| CP07 | unexposed: body never ran | grep unexposed-console.txt | does not contain 'S17_BODY_SHOULD_NOT_RUN' | absent | PASS |
| CP08 | unexposed: refused immediately, not queued | elapsed seconds | < 60 | 9 | PASS |
| CP09 | No ephemeral resource created for the unknown name | Groovy fromName on B | false | false | PASS |
| CP10 | The unexposed resource was left alone | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |

#### Summary

- unknown_result: FAILURE
- unknown_seconds: 7
- unexposed_result: FAILURE
- unexposed_seconds: 9
- unknown_resource: s17-unknown-1786705356
- unexposed_resource: s17-hidden-1786705356

#### Artifacts

- unknown console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260814195206-e2e-test/remote-unknown-rejected/unknown-console.txt
- unexposed console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260814195206-e2e-test/remote-unknown-rejected/unexposed-console.txt

