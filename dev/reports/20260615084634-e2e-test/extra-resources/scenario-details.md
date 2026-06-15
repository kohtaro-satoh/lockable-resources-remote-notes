### S10: extra-resources

#### Summary

- build result: SUCCESS
- S10RES (combined): s10-res1-1781481187,s10-res2-1781481187
- during-body lease (r1/r2): dbbe97d8-63b9-4552-bf03-e21c36e17511 / dbbe97d8-63b9-4552-bf03-e21c36e17511
- after state: R1_FREE=true;R2_FREE=true

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (build SUCCESS) |
| CP02 | PASS (both locked during body by same lease — atomic) |
| CP03 | PASS (S10RES=s10-res1-1781481187,s10-res2-1781481187, comma-separated) |
| CP04 | PASS (S10RES0/S10RES1 present) |
| CP05 | PASS (both released after completion) |
| CP06 | PASS (Remote lock acquired on found) |

#### Artifacts

- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260615084634-e2e-test/extra-resources/console.txt
- summary: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260615084634-e2e-test/extra-resources/summary.txt
