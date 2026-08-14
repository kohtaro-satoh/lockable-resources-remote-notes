### S19: remote-resources-endpoint

**Result: PASS** (11 checkpoints, 0 failed)

#### Sequence

- SEQ01 Expose one resource on B, and add one that is deliberately not exposed
- SEQ02 Reserve the exposed resource, with a note and a reserver name that must not leak
- SEQ03 Fetch the catalogue
- SEQ04 Pause acquires and check the same snapshot says so

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Endpoint answers | GET /resources | 200 | 200 | PASS |
| CP02 | The exposed resource is listed | grep resources.json | contains 's19-exposed-1786705572' | found | PASS |
| CP03 | exposeLabel is the visibility boundary | grep resources.json | does not contain 's19-hidden-1786705572' | absent | PASS |
| CP04 | Entries carry live state | grep resources.json | contains '"state"' | found | PASS |
| CP05 | A reserved resource reports RESERVED | grep resources.json | contains '"RESERVED"' | found | PASS |
| CP06 | The note stays on the server | grep resources.json | does not contain 'S19_SECRET_NOTE' | absent | PASS |
| CP07 | The reserver's name stays on the server | grep resources.json | does not contain 's19-operator' | absent | PASS |
| CP08 | The kind of holder is still reported | grep resources.json | contains '"heldByKind"' | found | PASS |
| CP09 | Serving: acceptNewAcquires is true | grep resources.json | contains '"acceptNewAcquires":true' | found | PASS |
| CP10 | Paused: acceptNewAcquires is false | grep resources-paused.json | contains '"acceptNewAcquires":false' | found | PASS |
| CP11 | Resource state is unchanged by pausing | grep resources-paused.json | contains '"RESERVED"' | found | PASS |

#### Summary

- http_code: 200
- exposed_resource: s19-exposed-1786705572
- hidden_resource: s19-hidden-1786705572

#### Artifacts

- response: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260814195206-e2e-test/remote-resources-endpoint/resources.json
- response while paused: /home/ksato/projects/jenkins/rlr/lockable-resources-remote-notes/dev/jenkins-env/../reports/20260814195206-e2e-test/remote-resources-endpoint/resources-paused.json

