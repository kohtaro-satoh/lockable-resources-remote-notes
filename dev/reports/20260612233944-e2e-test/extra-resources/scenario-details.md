### S10: extra-resources

#### Summary

- build result: SUCCESS
- S10RES (combined): s10-res1-1781275583,s10-res2-1781275583
- during-body lease (r1/r2): 9c82a4d6-efb7-4656-bea7-affdad7bddaa / 9c82a4d6-efb7-4656-bea7-affdad7bddaa
- after state: R1_FREE=true;R2_FREE=true

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (build SUCCESS) |
| CP02 | PASS (both locked during body by same lease — atomic) |
| CP03 | PASS (S10RES=s10-res1-1781275583,s10-res2-1781275583, comma-separated) |
| CP04 | PASS (S10RES0/S10RES1 present) |
| CP05 | PASS (both released after completion) |
| CP06 | PASS (Remote lock acquired on found) |

#### Artifacts

- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260612233944-e2e-test/extra-resources/console.txt
- summary: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260612233944-e2e-test/extra-resources/summary.txt
