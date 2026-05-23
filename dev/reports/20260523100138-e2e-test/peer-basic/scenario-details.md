#### Sequence

- S01 Configure Controller B as authenticated remote server and create exposed resource step8-board-1779498133
- S02 Issue API token for Controller B admin and upsert username/password credentials on Controllers A/C
- S03 Configure Controllers A and C as remote clients with credentials (serverId=b)
- S04 Create or update holder/waiter pipeline jobs
- S05 Trigger holder build and wait for lock acquisition signal
- S06 Trigger waiter build and validate it waits until holder releases

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Controller B remote server configuration | Groovy /scriptText (set auth mode, remoteApiEnabled, exposeLabel, resource) | authenticatedMode=true, remoteApiEnabled=true and resourceExposed=true | verify_controller_b_remote_server_config(authenticated) passed | PASS |
| CP02 | Controller A/C credentials upsert | Groovy /scriptText (ApiTokenProperty issue + SystemCredentialsProvider upsert) | credential id=step8-peer-basic-auth exists on A/C and password field contains B-side API token | issue_user_api_token + upsert_username_password_credential completed for A and C | PASS |
| CP03 | Controller A/C remote client configuration | Groovy /scriptText (set remotes=[b->8082], credentialsId) | A/C remotes point to B with credentialsId=step8-peer-basic-auth | configure_remote_client + verify_remote_client_config completed for A and C | PASS |
| CP04 | Pipeline job upsert | Groovy /scriptText (WorkflowJob upsert) | step8-peer-holder and step8-peer-waiter are updated | upsert_pipeline_job completed | PASS |
| CP05 | Holder lock acquisition | POST /lockable-resources/remote/v1/acquire/ -> 202, GET /acquire/{lockId}/ -> ACQUIRED | HOLDER_ACQUIRED appears within 120 seconds | HOLDER_ACQUIRED observed | PASS |
| CP06 | Holder build result | Jenkins Build API | SUCCESS | SUCCESS | PASS |
| CP07 | Waiter build result | Jenkins Build API | SUCCESS | SUCCESS | PASS |
| CP08 | Waiter wait duration | Elapsed time between waiter trigger and completion | >= 15s (lock wait should happen) | 29s | PASS |
| CP09 | Waiter console marker | Waiter console log | WAITER_ACQUIRED is present | WAITER_ACQUIRED found | PASS |
| CP10 | Remote API lifecycle evidence | POST /acquire/ -> GET /acquire/{lockId}/ -> POST /lease/{lockId}/release | enqueue/acquired/released markers exist in holder console | All lifecycle markers found in holder-console | PASS |

#### Artifacts

- holder build: http://127.0.0.1:8081/jenkins/job/step8-peer-holder/1/
- waiter build: http://127.0.0.1:8083/jenkins/job/step8-peer-waiter/1/
- holder console: /home/ksato/projects/jenkins/remote-lr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260523100138-e2e-test/peer-basic/holder-console.txt
- waiter console: /home/ksato/projects/jenkins/remote-lr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260523100138-e2e-test/peer-basic/waiter-console.txt
- summary: /home/ksato/projects/jenkins/remote-lr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260523100138-e2e-test/peer-basic/summary.txt
