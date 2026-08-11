### S07: fail-closed

**Result: PASS** (17 checkpoints, 0 failed)

#### Sequence

- SEQ01 Expose the resource on B and link A to it with a working credential
- SEQ02 Case remote-down: stop the server outright
- SEQ03 Case timeout: point the client at an unroutable address
- SEQ04 Case auth-error: a credential holding a token the server will not accept
- SEQ05 Case missing-credentials-id: a credentials id that resolves to nothing
- SEQ06 Case credentials-type-mismatch: a secret-text credential where a username/password is required
- SEQ07 Check no fault left the resource held on B

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Baseline setup | Groovy /scriptText | A->B configured and verified | A->B configured and verified | PASS |
| CP02 | remote-down: build failed closed | POST /acquire cannot connect | FAILURE | FAILURE | PASS |
| CP03 | remote-down: body never ran | grep console.txt | does not contain 'UNEXPECTED_BODY_EXECUTION' | absent | PASS |
| CP04 | remote-down: failed for the engineered reason | console evidence | matches /Remote API communication failure\|Connection refused\|ConnectException\|No route to host/ | true | PASS |
| CP05 | timeout: build failed closed | POST /acquire times out | FAILURE | FAILURE | PASS |
| CP06 | timeout: body never ran | grep console.txt | does not contain 'UNEXPECTED_BODY_EXECUTION' | absent | PASS |
| CP07 | timeout: failed for the engineered reason | console evidence | matches /timed out\|HttpTimeoutException\|timeout/ | true | PASS |
| CP08 | auth-error: build failed closed | POST /acquire is rejected with 401/403 | FAILURE | FAILURE | PASS |
| CP09 | auth-error: body never ran | grep console.txt | does not contain 'UNEXPECTED_BODY_EXECUTION' | absent | PASS |
| CP10 | auth-error: failed for the engineered reason | console evidence | matches /HTTP 401\|HTTP 403\|returned HTTP 401\|returned HTTP 403\|Sign in to access/ | true | PASS |
| CP11 | missing-credentials-id: build failed closed | the client cannot resolve credentialsId, and must not fall back to anonymous | FAILURE | FAILURE | PASS |
| CP12 | missing-credentials-id: body never ran | grep console.txt | does not contain 'UNEXPECTED_BODY_EXECUTION' | absent | PASS |
| CP13 | missing-credentials-id: failed for the engineered reason | console evidence | matches /Remote credentials not found for serverId=b, credentialsId=s07-missing-creds/ | true | PASS |
| CP14 | credentials-type-mismatch: build failed closed | the client rejects a credential of the wrong type rather than coercing it | FAILURE | FAILURE | PASS |
| CP15 | credentials-type-mismatch: body never ran | grep console.txt | does not contain 'UNEXPECTED_BODY_EXECUTION' | absent | PASS |
| CP16 | credentials-type-mismatch: failed for the engineered reason | console evidence | matches /Remote credentials not found for serverId=b, credentialsId=s07-type-mismatch-creds/ | true | PASS |
| CP17 | Resource free after all five faults | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |

#### Summary

- remote-down_result: FAILURE
- remote-down_build_url: http://127.0.0.1:8081/jenkins/job/s07-fail-remote-down/1/
- timeout_result: FAILURE
- timeout_build_url: http://127.0.0.1:8081/jenkins/job/s07-fail-timeout/1/
- auth-error_result: FAILURE
- auth-error_build_url: http://127.0.0.1:8081/jenkins/job/s07-fail-auth/1/
- missing-credentials-id_result: FAILURE
- missing-credentials-id_build_url: http://127.0.0.1:8081/jenkins/job/s07-fail-missing-credentials/1/
- credentials-type-mismatch_result: FAILURE
- credentials-type-mismatch_build_url: http://127.0.0.1:8081/jenkins/job/s07-fail-credentials-type-mismatch/1/

#### Artifacts

- remote-down console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260811101418-e2e-test/fail-closed/remote-down/console.txt
- timeout console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260811101418-e2e-test/fail-closed/timeout/console.txt
- auth-error console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260811101418-e2e-test/fail-closed/auth-error/console.txt
- missing-credentials-id console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260811101418-e2e-test/fail-closed/missing-credentials-id/console.txt
- credentials-type-mismatch console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260811101418-e2e-test/fail-closed/credentials-type-mismatch/console.txt

