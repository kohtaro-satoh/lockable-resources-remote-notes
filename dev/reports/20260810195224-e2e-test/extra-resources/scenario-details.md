### S10: extra-resources

#### Summary

- build result: SUCCESS
- S10RES (combined): s10-res1-1786359534,s10-res2-1786359534
- during-body lease (r1/r2): a4a8b4f5-bcbb-4ca0-a0dd-1627e15ed93e / a4a8b4f5-bcbb-4ca0-a0dd-1627e15ed93e
- after state: R1_FREE=true;R2_FREE=true

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (build SUCCESS) |
| CP02 | PASS (both locked during body by same lease — atomic) |
| CP03 | PASS (S10RES=s10-res1-1786359534,s10-res2-1786359534, comma-separated) |
| CP04 | PASS (S10RES0/S10RES1 present) |
| CP05 | PASS (both released after completion) |
| CP06 | PASS (Remote lock acquired on found) |

#### Artifacts

- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260810195224-e2e-test/extra-resources/console.txt
- summary: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260810195224-e2e-test/extra-resources/summary.txt
