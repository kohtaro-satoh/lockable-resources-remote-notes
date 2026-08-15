### S14: extra-label-resources

**Result: PASS** (12 checkpoints, 0 failed)

#### Sequence

- SEQ01 Expose a main resource and a labelled one on B, and link A
- SEQ02 Lock the main resource with a label-selected extra
- SEQ03 Check both resources were released

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Main resource held remotely | Groovy resource state on b | held by a remote lease | lease=3f439bde-2624-4b1b-ad7b-51ebfaeb4afb | PASS |
| CP02 | Label-selected extra was honoured, not dropped | Groovy resource state on b | held by a remote lease | lease=3f439bde-2624-4b1b-ad7b-51ebfaeb4afb | PASS |
| CP03 | Extra joined the same lease (atomic) | Groovy getRemoteLockedBy on B | 3f439bde-2624-4b1b-ad7b-51ebfaeb4afb | 3f439bde-2624-4b1b-ad7b-51ebfaeb4afb | PASS |
| CP04 | Build result | Build API | SUCCESS | SUCCESS | PASS |
| CP05 | Combined variable names the main resource | grep console.txt | contains 's14-res1-1786776109' | found | PASS |
| CP06 | Combined variable names the label-resolved extra | grep console.txt | contains 's14-gpu-1786776109' | found | PASS |
| CP07 | Combined variable is comma separated | lockEnvVars S14RES | contains , | contains , | PASS |
| CP08 | Indexed variable 0 is set | grep -E console.txt | matches /^S14RES0=s14-/ | matched | PASS |
| CP09 | Indexed variable 1 is set | grep -E console.txt | matches /^S14RES1=s14-/ | matched | PASS |
| CP10 | Main resource released | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |
| CP11 | Label-selected extra released | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |
| CP12 | Went over the remote path | grep console.txt | contains 'Remote lock acquired on' | found | PASS |

#### Summary

- build_url: http://127.0.0.1:8081/jenkins/job/s14-extra-label/1/
- result: SUCCESS
- S14RES: s14-res1-1786776109,s14-gpu-1786776109
- lease_main: 3f439bde-2624-4b1b-ad7b-51ebfaeb4afb
- lease_extra: 3f439bde-2624-4b1b-ad7b-51ebfaeb4afb

#### Artifacts

- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260815153215-e2e-test/extra-label-resources/console.txt

