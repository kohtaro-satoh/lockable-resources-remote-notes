### S10: extra-resources

#### Summary

- build result: SUCCESS
- S10RES (combined): s10-res1-1782003773,s10-res2-1782003773
- during-body lease (r1/r2): 049253fd-1875-4b1c-afcc-739ac4df9b5e / 049253fd-1875-4b1c-afcc-739ac4df9b5e
- after state: R1_FREE=true;R2_FREE=true

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (build SUCCESS) |
| CP02 | PASS (both locked during body by same lease — atomic) |
| CP03 | PASS (S10RES=s10-res1-1782003773,s10-res2-1782003773, comma-separated) |
| CP04 | PASS (S10RES0/S10RES1 present) |
| CP05 | PASS (both released after completion) |
| CP06 | PASS (Remote lock acquired on found) |

#### Artifacts

- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260621095609-e2e-test/extra-resources/console.txt
- summary: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260621095609-e2e-test/extra-resources/summary.txt
