### S14: extra-label-resources

#### Summary

- build result: SUCCESS
- S14RES (combined): s14-res1-1786166363,s14-gpu-1786166363
- during-body lease (r1/gpu): c9989dcc-871a-48a6-947c-03c78372f6ef / c9989dcc-871a-48a6-947c-03c78372f6ef
- after state: R1_FREE=true;GPU_FREE=true

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (build SUCCESS) |
| CP02 | PASS (main + label-based extra locked during body by same lease — atomic, C-1) |
| CP03 | PASS (S14RES=s14-res1-1786166363,s14-gpu-1786166363, comma-separated) |
| CP04 | PASS (S14RES0/S14RES1 present) |
| CP05 | PASS (both released after completion) |
| CP06 | PASS (Remote lock acquired on found) |

#### Artifacts

- console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260808140951-e2e-test/extra-label-resources/console.txt
- summary: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260808140951-e2e-test/extra-label-resources/summary.txt
