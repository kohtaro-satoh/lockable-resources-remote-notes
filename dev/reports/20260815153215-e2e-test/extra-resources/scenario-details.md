### S10: extra-resources

**Result: PASS** (11 checkpoints, 0 failed)

#### Sequence

- SEQ01 Expose two resources on B and link A to them
- SEQ02 Lock main + extra and inspect the leases while the body runs
- SEQ03 Check both resources were released

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Main resource held remotely during the body | Groovy resource state on b | held by a remote lease | lease=83e40c03-f4cd-4225-95b5-d7c2083c116f | PASS |
| CP02 | Extra joined the same lease (atomic) | Groovy getRemoteLockedBy on B | 83e40c03-f4cd-4225-95b5-d7c2083c116f | 83e40c03-f4cd-4225-95b5-d7c2083c116f | PASS |
| CP03 | Build result | Build API | SUCCESS | SUCCESS | PASS |
| CP04 | Combined variable names the main resource | grep console.txt | contains 's10-res1-1786775920' | found | PASS |
| CP05 | Combined variable names the extra resource | grep console.txt | contains 's10-res2-1786775920' | found | PASS |
| CP06 | Combined variable is comma separated, as local lock() does it | lockEnvVars S10RES | contains , | contains , | PASS |
| CP07 | Indexed variable 0 is set | grep -E console.txt | matches /^S10RES0=s10-res/ | matched | PASS |
| CP08 | Indexed variable 1 is set | grep -E console.txt | matches /^S10RES1=s10-res/ | matched | PASS |
| CP09 | Main resource released | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |
| CP10 | Extra resource released | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |
| CP11 | Went over the remote path | grep console.txt | contains 'Remote lock acquired on' | found | PASS |

#### Summary

- build_url: http://127.0.0.1:8081/jenkins/job/s10-extra/1/
- result: SUCCESS
- S10RES: s10-res1-1786775920,s10-res2-1786775920
- S10RES0: s10-res1-1786775920
- S10RES1: s10-res2-1786775920
- lease_main: 83e40c03-f4cd-4225-95b5-d7c2083c116f
- lease_extra: 83e40c03-f4cd-4225-95b5-d7c2083c116f

#### Artifacts

- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260815153215-e2e-test/extra-resources/console.txt

