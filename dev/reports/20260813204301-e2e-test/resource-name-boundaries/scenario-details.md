### B03: resource-name-boundaries

**Result: PASS** (15 checkpoints, 0 failed)

#### Sequence

- SEQ01 Create the awkwardly named resources on B and link A
- SEQ02 A name containing a space
- SEQ03 A name in a non-Latin script
- SEQ04 A 255-character name
- SEQ05 A name containing the separator the combined variable uses
- SEQ06 Check the awkward names did not disturb the catalogue

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | spaced: build result | Build API | SUCCESS | SUCCESS | PASS |
| CP02 | spaced: the name survives the round trip | lockEnvVars B03RES0 | b03 spaced 1786622543 | b03 spaced 1786622543 | PASS |
| CP03 | spaced: released | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |
| CP04 | multibyte: build result | Build API | SUCCESS | SUCCESS | PASS |
| CP05 | multibyte: the name survives the round trip | lockEnvVars B03RES0 | b03-日本語-リソース-1786622543 | b03-日本語-リソース-1786622543 | PASS |
| CP06 | multibyte: released | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |
| CP07 | long: build result | Build API | SUCCESS | SUCCESS | PASS |
| CP08 | long: the name is not truncated | lockEnvVars B03RES0 | b03-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx-1786622543 | b03-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx-1786622543 | PASS |
| CP09 | long: released | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |
| CP10 | comma: build result | Build API | SUCCESS | SUCCESS | PASS |
| CP11 | comma: the indexed variable is exact | lockEnvVars B03RES0 | b03-comma,inside-1786622543 | b03-comma,inside-1786622543 | PASS |
| CP12 | comma: splitting the combined variable | B03RES split on ',' | (observed) | 2 parts from 1 locked resource (V=b03-comma,inside-1786622543) | INFO |
| CP13 | comma: released | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |
| CP14 | The catalogue still serves | GET /resources | 200 | 200 | PASS |
| CP15 | and lists the multibyte name | grep resources.json | contains 'b03-日本語-リソース-1786622543' | found | PASS |

#### Summary

- spaced_name: b03 spaced 1786622543
- multibyte_name: b03-日本語-リソース-1786622543
- comma_name: b03-comma,inside-1786622543
- comma_combined_variable: b03-comma,inside-1786622543
- long_name_length: 255

#### Artifacts

- spaced console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260813204301-e2e-test/resource-name-boundaries/spaced-console.txt
- multibyte console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260813204301-e2e-test/resource-name-boundaries/multibyte-console.txt
- long console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260813204301-e2e-test/resource-name-boundaries/long-console.txt
- comma console: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260813204301-e2e-test/resource-name-boundaries/comma-console.txt
- catalogue: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260813204301-e2e-test/resource-name-boundaries/resources.json

