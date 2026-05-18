#### Sequence

- S01 Configure Controller B as remote server and create exposed resource step8-fail-board-1779146061
- S02 Configure Controller A as remote client (serverId=b)
- S03 Case remote-down: stop Controller B to simulate remote API unavailability
- S04 Run case=remote-down and verify it fails closed without executing lock body
- S05 Case timeout: point Controller A remote URL to unroutable IP to trigger timeout
- S06 Run case=timeout and verify it fails closed without executing lock body
- S07 Case auth-error: enforce authentication on Controller B and expect 403/auth failure
- S08 Run case=auth-error and verify it fails closed without executing lock body

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Controller B remote server configuration | Groovy /scriptText (set remoteApiEnabled, exposeLabel, resource) | remoteApiEnabled=true and resourceExposed=true | verify_controller_b_remote_server_config passed | PASS |
| CP02 | Controller A remote client configuration | Groovy /scriptText (set remotes=[b->8082]) | Controller A can reference Controller B remote API | configure_remote_client completed | PASS |
| CP03 | remote-down: pipeline job upsert | Groovy /scriptText (WorkflowJob upsert) | step8-fail-remote-down is updated | upsert_pipeline_job completed | PASS |
| CP04 | remote-down: build result | POST /acquire/ or GET /acquire/{lockId}/ fails due to connection issue | FAILURE (fail-closed) | FAILURE | PASS |
| CP05 | remote-down: expected error evidence | POST /acquire/ or GET /acquire/{lockId}/ fails due to connection issue | Console contains expected error hint | Matched /Remote API communication failure|Connection refused|ConnectException|No route to host/ | PASS |
| CP06 | remote-down: lock body guard | Pipeline lock body | UNEXPECTED_BODY_EXECUTION is absent | Marker not found | PASS |
| CP07 | timeout: pipeline job upsert | Groovy /scriptText (WorkflowJob upsert) | step8-fail-timeout is updated | upsert_pipeline_job completed | PASS |
| CP08 | timeout: build result | POST /acquire/ times out | FAILURE (fail-closed) | FAILURE | PASS |
| CP09 | timeout: expected error evidence | POST /acquire/ times out | Console contains expected error hint | Matched /timed out|HttpTimeoutException|timeout/ | PASS |
| CP10 | timeout: lock body guard | Pipeline lock body | UNEXPECTED_BODY_EXECUTION is absent | Marker not found | PASS |
| CP11 | auth-error: pipeline job upsert | Groovy /scriptText (WorkflowJob upsert) | step8-fail-auth is updated | upsert_pipeline_job completed | PASS |
| CP12 | auth-error: build result | POST /acquire/ returns HTTP 403 or auth error | FAILURE (fail-closed) | FAILURE | PASS |
| CP13 | auth-error: expected error evidence | POST /acquire/ returns HTTP 403 or auth error | Console contains expected error hint | Matched /HTTP 403|returned HTTP 403|Sign in to access/ | PASS |
| CP14 | auth-error: lock body guard | Pipeline lock body | UNEXPECTED_BODY_EXECUTION is absent | Marker not found | PASS |

#### Artifacts

- scenario dir: /home/ksato/projects/jenkins/remote-lr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260519081315-e2e-test/fail-closed
- remote-down console: /home/ksato/projects/jenkins/remote-lr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260519081315-e2e-test/fail-closed/remote-down/console.txt
- timeout console: /home/ksato/projects/jenkins/remote-lr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260519081315-e2e-test/fail-closed/timeout/console.txt
- auth-error console: /home/ksato/projects/jenkins/remote-lr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260519081315-e2e-test/fail-closed/auth-error/console.txt
