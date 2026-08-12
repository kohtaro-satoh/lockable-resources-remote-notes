### B01: acquire-payload-boundaries

**Result: PASS** (26 checkpoints, 0 failed)

#### Sequence

- SEQ01 Expose one resource on B to aim the requests at
- SEQ02 Malformed and structurally wrong bodies
- SEQ03 Requests that contradict lock() semantics
- SEQ04 heartbeatIntervalSeconds, the one field with its own validation
- SEQ05 Targets this client may not have
- SEQ06 The body size cap (1048576 characters)
- SEQ07 Values the endpoint cannot interpret
- SEQ08 Loose but legitimate forms still work
- SEQ09 Check no rejected request left anything behind

#### Checkpoints

| ID | Step | API / Action | Expected | Actual | Result |
|---|---|---|---|---|---|
| CP01 | Body that is not JSON | HTTP status + errorCode | 400/INVALID_JSON | 400/INVALID_JSON | PASS |
| CP02 | Body missing lockRequest | HTTP status + errorCode | 400/MISSING_LOCK_REQUEST | 400/MISSING_LOCK_REQUEST | PASS |
| CP03 | lockRequest that is not an object | HTTP status + errorCode | 400/MISSING_LOCK_REQUEST | 400/MISSING_LOCK_REQUEST | PASS |
| CP04 | No target at all | HTTP status + errorCode | 400/INVALID_REQUEST | 400/INVALID_REQUEST | PASS |
| CP05 | resource and label together | HTTP status + errorCode | 400/INVALID_REQUEST | 400/INVALID_REQUEST | PASS |
| CP06 | Unknown resourceSelectStrategy | HTTP status + errorCode | 400/INVALID_REQUEST | 400/INVALID_REQUEST | PASS |
| CP07 | priority with inversePrecedence | HTTP status + errorCode | 400/INVALID_REQUEST | 400/INVALID_REQUEST | PASS |
| CP08 | extra entry naming neither resource nor label | HTTP status + errorCode | 400/INVALID_EXTRA | 400/INVALID_EXTRA | PASS |
| CP09 | heartbeatIntervalSeconds = 0 | HTTP status + errorCode | 400/INVALID_HEARTBEAT_INTERVAL | 400/INVALID_HEARTBEAT_INTERVAL | PASS |
| CP10 | heartbeatIntervalSeconds < 0 | HTTP status + errorCode | 400/INVALID_HEARTBEAT_INTERVAL | 400/INVALID_HEARTBEAT_INTERVAL | PASS |
| CP11 | heartbeatIntervalSeconds not a number | HTTP status + errorCode | 400/INVALID_HEARTBEAT_INTERVAL | 400/INVALID_HEARTBEAT_INTERVAL | PASS |
| CP12 | Resource that does not exist | HTTP status + errorCode | 404/UNKNOWN_RESOURCE | 404/UNKNOWN_RESOURCE | PASS |
| CP13 | Label that matches nothing | HTTP status + errorCode | 404/UNKNOWN_LABEL | 404/UNKNOWN_LABEL | PASS |
| CP14 | A body exactly at the cap is accepted | POST /acquire with 1048576 chars | 202 | 202 | PASS |
| CP15 | A body one character over is refused | HTTP status + errorCode | 413/PAYLOAD_TOO_LARGE | 413/PAYLOAD_TOO_LARGE | PASS |
| CP16 | quantity that is not a number | HTTP status + errorCode | 400/INVALID_FIELD_VALUE | 400/INVALID_FIELD_VALUE | PASS |
| CP17 | priority that is not a number | HTTP status + errorCode | 400/INVALID_FIELD_VALUE | 400/INVALID_FIELD_VALUE | PASS |
| CP18 | Allocate timeout that is not a number | HTTP status + errorCode | 400/INVALID_FIELD_VALUE | 400/INVALID_FIELD_VALUE | PASS |
| CP19 | timeoutUnit that is not a TimeUnit | HTTP status + errorCode | 400/INVALID_FIELD_VALUE | 400/INVALID_FIELD_VALUE | PASS |
| CP20 | quantity inside an extra entry | HTTP status + errorCode | 400/INVALID_FIELD_VALUE | 400/INVALID_FIELD_VALUE | PASS |
| CP21 | A numeric string is still a number | POST /acquire quantity:"1" | 202 | 202 | PASS |
| CP22 | An explicit null means not supplied | POST /acquire with null fields | 202 | 202 | PASS |
| CP23 | A lower-case unit is normalised, as local lock() does | POST /acquire timeoutUnit:"seconds" | 202 | 202 | PASS |
| CP24 | Negative values keep their local meaning | POST /acquire quantity:-1, timeout:-5 | 202 | 202 | PASS |
| CP25 | The target resource is free | Groovy resource state on b | free: not locked, no lease, not reserved | free | PASS |
| CP26 | No resource was created for the unknown name | Groovy fromName on B | false | false | PASS |

#### Summary

- max_body_chars: 1048576
- resource: b01-res-1786513932

