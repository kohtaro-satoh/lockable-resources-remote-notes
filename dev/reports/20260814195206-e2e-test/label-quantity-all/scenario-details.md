### S15: label-quantity-all

**Result: PASS** (13 checkpoints, 0 failed)

#### Sequence

- SEQ01 Expose a pool of 3 resources sharing one label on B, and link A
- SEQ02 Lock by label with no quantity
- SEQ03 Check every resource in the pool is held under one lease
- SEQ04 Check the whole pool was released

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Pool member s15-pool1-1786705325 is under the same lease | Groovy getRemoteLockedBy on B | 4a483da9-4d33-4363-a726-983fef417b37 | 4a483da9-4d33-4363-a726-983fef417b37 | PASS |
| CP02 | Pool member s15-pool2-1786705325 is under the same lease | Groovy getRemoteLockedBy on B | 4a483da9-4d33-4363-a726-983fef417b37 | 4a483da9-4d33-4363-a726-983fef417b37 | PASS |
| CP03 | Pool member s15-pool3-1786705325 is under the same lease | Groovy getRemoteLockedBy on B | 4a483da9-4d33-4363-a726-983fef417b37 | 4a483da9-4d33-4363-a726-983fef417b37 | PASS |
| CP04 | The pool is actually held | Groovy resource state on b | held by a remote lease | lease=4a483da9-4d33-4363-a726-983fef417b37 | PASS |
| CP05 | Build result | Build API | SUCCESS | SUCCESS | PASS |
| CP06 | Combined variable names s15-pool1-1786705325 | grep console.txt | contains 's15-pool1-1786705325' | found | PASS |
| CP07 | Combined variable names s15-pool2-1786705325 | grep console.txt | contains 's15-pool2-1786705325' | found | PASS |
| CP08 | Combined variable names s15-pool3-1786705325 | grep console.txt | contains 's15-pool3-1786705325' | found | PASS |
| CP09 | Combined variable is comma separated | lockEnvVars S15RES | contains , | contains , | PASS |
| CP10 | s15-pool1-1786705325 released | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |
| CP11 | s15-pool2-1786705325 released | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |
| CP12 | s15-pool3-1786705325 released | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |
| CP13 | Went over the remote path | grep console.txt | contains 'Remote lock acquired on' | found | PASS |

#### Summary

- build_url: http://127.0.0.1:8081/jenkins/job/s15-label-all/1/
- result: SUCCESS
- pool_size: 3
- S15RES: s15-pool1-1786705325,s15-pool2-1786705325,s15-pool3-1786705325
- lease: 4a483da9-4d33-4363-a726-983fef417b37

#### Artifacts

- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260814195206-e2e-test/label-quantity-all/console.txt

