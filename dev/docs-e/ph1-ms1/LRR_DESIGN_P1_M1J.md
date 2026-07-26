# M1J Design (Remote lock - Phase 1 / M1J: remote config help links return 404)

> Origin: PR #1055 review (a reviewer reported it with a screenshot of the remote config screen)
> Branch: `feature/1025-remote-lr-p1-m1` (M1J commit `e83534b`, stacked on PR head `7fd218b`, which the reviewer
> had rebased onto `upstream/master` `4dbbfc1`)
> Position: a minor UI-help display fix after M1H/M1I and the PR #1055 submission. No behaviour change and no
> logic change (only the help URL string in the jelly forms).

## 1. Goal

Clicking the (?) help icon on any field of the **Remote Lockable Resources (Server / Client)** sections under
`Manage Jenkins > System` must render the help text. Before the fix, all 8 fields showed
**"ERROR: Failed to load help file: Not Found" (HTTP 404)**.

## 2. Root cause

- The explicit `help=` attribute on `f:entry` used the **`help-<field>` (hyphen) form**, e.g.
  `help="/descriptor/org.jenkins.plugins.lockableresources.LockableResourcesManager/help-remoteApiEnabled"`.
- The help URL that Jenkins core (`hudson.model.Descriptor#getHelpFile`) actually generates — and that Stapler
  can resolve — is **`/descriptor/<FQCN>/help/<field>` (slash form)**. `getHelpFile` builds
  `page = "/descriptor/"+id+"/help"` then appends `page += '/' + fieldName` (confirmed in the `jenkins-core`
  source).
- The help HTML **file names** on disk follow the `help-<field>.html` convention (e.g. `help-exposeLabel.html`),
  but the **served URL path uses a slash** (`help/<field>`). The bug was carrying the filename's `-` straight
  into the URL.
- The hyphen URL is a nonexistent path, so it 404s; the (?) popup then fails to fetch its body and shows
  "Failed to load help file: Not Found".
- **Latent bug**: present since the first #1025 commit (`4f3577f`, where `config.jelly` and the `help-*.html`
  files were added together) and never fixed. Unrelated to locking / API behaviour — help display only.

## 3. Design (minimal fix)

- Replace the explicit `help=` in the 2 `config.jelly` files, all 8 occurrences, `help-<field>` ->
  **`help/<field>`**. No change to logic, file names, or wording.

| File | help attributes fixed |
|---|---|
| `LockableResourcesManager/config.jelly` | `remoteApiEnabled` / `exposeLabel` / `clientId` / `forcedServerId` / `remotes` (5) |
| `RemoteConnection/config.jelly` | `serverId` / `url` / `credentialsId` (3) |

> Note: dropping the explicit `help=` and keeping only `f:entry field="..."` would let core derive the URL via
> `getHelpFile(field)` (so there is no place to write a hyphen at all). This fix instead keeps the existing
> explicit-help style and just aligns it to the slash form, to minimize the diff and keep review easy.

## 4. Test plan

- **Live check (authoritative)**: hit all 8 help URLs directly against a running container — 404 before,
  **200 + correct body** after.
  - e.g. `GET /jenkins/descriptor/org.jenkins.plugins.lockableresources.LockableResourcesManager/help/remoteApiEnabled`
    -> 200 `Enables or disables the remote lock REST API ...`
  - 8/8 return 200. The old hyphen form still 404s (correctly, as a nonexistent path).
- **Regression gates**: `run-mvn-verify.sh` (`mvn clean verify`) + full `run-e2e.sh` + `run-load.sh --preset
  stress`. A jelly-only change cannot affect compile/tests, but we confirm all gates stay green on top of the
  reviewer's rebase (`7fd218b`).
- **Deploy caveat**: if a stale `.jpi` remains in a jhX volume, the ref/plugins seed is not overwritten and the
  old plugin keeps running. To exercise an uncommitted working-tree fix in E2E, use `start.sh --clean
  --in-place-build` (`--clean` alone builds the committed HEAD, so the fix would not be included).

## 5. Out of scope (not M1J)

| Item | Note |
|---|---|
| Editing the help bodies (`help-*.html`) | This cycle fixes URL resolution only; wording unchanged |
| Removing the explicit help attribute (unify on field-derived help) | Deferred to keep the diff minimal; a possible follow-up |
| Client UI / read-only mirror | Phase 2 (issue #1025) |

## 6. Verification

Following the dev cycle (`作業手順一覧.md`), `run-mvn-verify.sh` + `run-e2e.sh` + `run-load.sh` are the
authoritative checks. Confirmed on plugin `e83534b` (on top of the rebased `7fd218b`); reports are bundled under
`dev/reports/`.

- `mvn verify`: **BUILD SUCCESS**, tests **386 / Failures 0 / Errors 0 / Skipped 1** (the known permanent
  JENKINS-40787 skip), all static gates (spotless/spotbugs/checkstyle/pmd) ok.
- E2E: **21 / 21 PASS** (fail 0 / skip 0).
- Load (`--preset stress`, 4×50 = 200 concurrent jobs): **182 SUCCESS / 18 FAILURE (all 18 a clean
  `LOCK_WAIT_TIMEOUT`)**, **0 mutual-exclusion violations / 0 HUNG**. Re-confirms the M1I property (a starvation
  timeout surfaces as a clean `LOCK_WAIT_TIMEOUT`) still holds after the rebase.

## Changed files (plugin, commit `e83534b`)

| File | Change |
|---|---|
| `LockableResourcesManager/config.jelly` | 5 explicit help attrs, `help-<field>` -> `help/<field>` |
| `RemoteConnection/config.jelly` | 3 explicit help attrs, `help-<field>` -> `help/<field>` |

Total 2 files / +8 -8 (string replacement only).

## Change log

- 2026-07-19: First version. Defines the minimal fix for the remote config help-link 404 reported in PR #1055
  review (latent since `4f3577f`) as the M1J dev cycle. Aligned 8 help URLs to the slash form, verified 8/8=200
  live, all green on the rebase (`7fd218b`): mvn verify 386/0/1skip, E2E 21/21, load stress 200 all green.
