### S07: fail-closed

#### Sequence

- SEQ01 Configure Controller B as authenticated remote server and create exposed resource s07-fail-board-1781502006
- SEQ02 Issue API token for Controller B admin and create valid username/password credential on Controller A
- SEQ03 Configure Controller A as remote client with credentials (serverId=b)
- SEQ04 Case remote-down: stop Controller B to simulate remote API unavailability
- SEQ05 Run case=remote-down and verify it fails closed without executing lock body
- SEQ06 Case timeout: point Controller A remote URL to unroutable IP to trigger timeout
- SEQ07 Run case=timeout and verify it fails closed without executing lock body
- SEQ08 Case auth-error: use invalid API token credential and expect 401/403
- SEQ09 Run case=auth-error and verify it fails closed without executing lock body
- SEQ10 Case missing-credentials-id: configure unknown credentialsId and expect fail-fast
- SEQ11 Run case=missing-credentials-id and verify it fails closed without executing lock body
- SEQ12 Case credentials-type-mismatch: configure secret-text credential id and expect fail-fast
- SEQ13 Run case=credentials-type-mismatch and verify it fails closed without executing lock body

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Controller B remote server configuration | Groovy /scriptText (set auth mode, remoteApiEnabled, exposeLabel, resource) | authenticatedMode=true, remoteApiEnabled=true and resourceExposed=true | verify_controller_b_remote_server_config(authenticated) passed | PASS |
| CP02 | Controller A credentials upsert | Groovy /scriptText (ApiTokenProperty issue + SystemCredentialsProvider upsert) | credential id=s07-valid-creds exists on A and password field contains B-side API token | issue_user_api_token + upsert_username_password_credential completed | PASS |
| CP03 | Controller A remote client configuration | Groovy /scriptText (set remotes=[b->8082], credentialsId) | Controller A remotes point to B with credentialsId=s07-valid-creds | configure_remote_client + verify_remote_client_config completed | PASS |
| CP04 | remote-down: pipeline job upsert | Groovy /scriptText (WorkflowJob upsert) | s07-fail-remote-down is updated | upsert_pipeline_job completed | PASS |
| CP05 | remote-down: build result | POST /acquire/ or GET /acquire/{lockId}/ fails due to connection issue | FAILURE (fail-closed) | FAILURE | PASS |
| CP06 | remote-down: expected error evidence | POST /acquire/ or GET /acquire/{lockId}/ fails due to connection issue | Console contains expected error hint | Matched /Remote API communication failure|Connection refused|ConnectException|No route to host/ | PASS |
| CP07 | remote-down: lock body guard | Pipeline lock body | UNEXPECTED_BODY_EXECUTION is absent | Marker not found | PASS |
| CP08 | timeout: pipeline job upsert | Groovy /scriptText (WorkflowJob upsert) | s07-fail-timeout is updated | upsert_pipeline_job completed | PASS |
| CP09 | timeout: build result | POST /acquire/ times out | FAILURE (fail-closed) | FAILURE | PASS |
| CP10 | timeout: expected error evidence | POST /acquire/ times out | Console contains expected error hint | Matched /timed out|HttpTimeoutException|timeout/ | PASS |
| CP11 | timeout: lock body guard | Pipeline lock body | UNEXPECTED_BODY_EXECUTION is absent | Marker not found | PASS |
| CP12 | auth-error: pipeline job upsert | Groovy /scriptText (WorkflowJob upsert) | s07-fail-auth is updated | upsert_pipeline_job completed | PASS |
| CP13 | auth-error: build result | POST /acquire/ returns HTTP 401/403 due to invalid Authorization | FAILURE (fail-closed) | FAILURE | PASS |
| CP14 | auth-error: expected error evidence | POST /acquire/ returns HTTP 401/403 due to invalid Authorization | Console contains expected error hint | Matched /HTTP 401|HTTP 403|returned HTTP 401|returned HTTP 403|Sign in to access/ | PASS |
| CP15 | auth-error: lock body guard | Pipeline lock body | UNEXPECTED_BODY_EXECUTION is absent | Marker not found | PASS |
| CP16 | missing-credentials-id: pipeline job upsert | Groovy /scriptText (WorkflowJob upsert) | s07-fail-missing-credentials is updated | upsert_pipeline_job completed | PASS |
| CP17 | missing-credentials-id: build result | LockStepExecution.resolveAuthorizationHeader() cannot resolve credentialsId | FAILURE (fail-closed) | FAILURE | PASS |
| CP18 | missing-credentials-id: expected error evidence | LockStepExecution.resolveAuthorizationHeader() cannot resolve credentialsId | Console contains expected error hint | Matched /Remote credentials not found for serverId=b, credentialsId=s07-missing-creds/ | PASS |
| CP19 | missing-credentials-id: lock body guard | Pipeline lock body | UNEXPECTED_BODY_EXECUTION is absent | Marker not found | PASS |
| CP20 | credentials-type-mismatch: pipeline job upsert | Groovy /scriptText (WorkflowJob upsert) | s07-fail-credentials-type-mismatch is updated | upsert_pipeline_job completed | PASS |
| CP21 | credentials-type-mismatch: build result | LockStepExecution.resolveAuthorizationHeader() rejects non-username/password credential | FAILURE (fail-closed) | FAILURE | PASS |
| CP22 | credentials-type-mismatch: expected error evidence | LockStepExecution.resolveAuthorizationHeader() rejects non-username/password credential | Console contains expected error hint | Matched /Remote credentials not found for serverId=b, credentialsId=s07-type-mismatch-creds/ | PASS |
| CP23 | credentials-type-mismatch: lock body guard | Pipeline lock body | UNEXPECTED_BODY_EXECUTION is absent | Marker not found | PASS |

#### Artifacts

- scenario dir: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260615143511-e2e-test/fail-closed
- remote-down console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260615143511-e2e-test/fail-closed/remote-down/console.txt
- timeout console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260615143511-e2e-test/fail-closed/timeout/console.txt
- auth-error console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260615143511-e2e-test/fail-closed/auth-error/console.txt
- missing-credentials-id console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260615143511-e2e-test/fail-closed/missing-credentials-id/console.txt
- credentials-type-mismatch console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260615143511-e2e-test/fail-closed/credentials-type-mismatch/console.txt
