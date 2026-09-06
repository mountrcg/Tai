# Trio upstream synchronization baseline

Audit completed: 2026-09-06

This file is the permanent traceability record for the one-time ancestry
reconciliation and content audit between public `Tai/dev` and official
`nightscout/Trio` `dev`.

## Attestation

**Complete through official Trio commit
`8e07b510606b8eb38111d3e475d3d647a71737c9`.**

All 172 non-version-bump first-parent changes made to official `Trio/dev`
after the previous common ancestor on 2026-02-13 have been accounted for.
Applicable behavior is present in Tai exactly, present in an adapted or later
form, or was added by this sync. The remaining differences are recorded Tai
fork decisions: intentionally excluded behavior, fork-owned repository policy,
and Tai-specific additions or replacements.

This attestation is bounded by the commit above. A later official Trio commit
requires a new normal merge and a new sync record; it does not invalidate this
baseline.

## Recorded commits

| Role | Commit |
| --- | --- |
| Tai tree preserved by the ancestry baseline | `51aa320940beb8556cedfd0a014a0977a0f0365e` |
| Official Trio ancestry baseline | `efc0bc1b585b9c000ff8294f3c50288d6b9c110a` |
| Previous common ancestor (2026-02-13) | `d1bee890e9d53cb8e17cbd33991b4a13a626bd12` |
| One-time ancestry merge | `653559ab7fbf8dee3633969f4b2f34694258326b` |
| Official Trio content head audited and merged | `8e07b510606b8eb38111d3e475d3d647a71737c9` |
| Normal incremental content merge | `856df9dd94` |
| Missing applicable corrections carried forward | `b5484600ed` |
| Test fixture repair | `7b9f88581` |

The normal incremental merge makes the attested official Trio head an actual
ancestor of this sync branch. Future comparisons can therefore use ordinary
Git ancestry and do not need to rediscover the old overlapping history.

## Why the one-time baseline preserved the Tai tree

A trial content merge of the old official baseline into the original Tai tree
produced 144 unresolved paths: 84 below `Trio`, 41 below `TrioTests`, project
and package files, localization data, three submodules, and many add/add
conflicts where both projects had independently integrated the same work.

Mechanically resolving those conflicts would have overwritten newer Tai
adaptations with older upstream shapes. Commit `653559ab7f` therefore used
Git's `ours` strategy once to join the histories while preserving the Tai tree.
Its tree ID exactly matches the pre-baseline Tai tree:

```text
Tai tree before baseline: c07c2686390a6ec01c24b54145e13fc74f46759c
Tree after baseline:      c07c2686390a6ec01c24b54145e13fc74f46759c
```

That merge recorded ancestry only. The audit and the later normal merge are
what support the content attestation.

## Audit method and result

The range `d1bee890..8e07b510` contains 341 first-parent commits:

- 169 automated `APP_DEV_VERSION` bumps, which are Tai-owned release metadata;
- 125 functional merges with matching import subjects in the original Tai
  history; and
- 47 functional merges requiring individual classification because their
  subjects were not present in the original Tai history.

For the 125 subject-matched merges, aggregate patch IDs were also compared.
Forty-three are patch-identical. The other 82 were imported through Tai's own
merge/conflict resolution and then modified further; their matching import
commits and resulting current-tree behavior account for them without claiming
byte-for-byte identity.

The 47 individually inspected merges have the following complete disposition:

| Disposition | Count | Trio PRs |
| --- | ---: | --- |
| Already present, exact reverse-patch proof | 9 | #1043, #1053, #1164, #1190, #1280, #1305, #1313, #1412, #1444 |
| Present in adapted, reorganized, or later form | 24 | #975, #984, #1021, #1040, #1047, #1093, #1127, #1141, #1149, #1165, #1166, #1174, #1222, #1233, #1269, #1273, #1325, #1336, #1357, #1369, #1373, #1376, #1390, #1406 |
| Net-neutral upstream change/revert pair | 2 | #1251, #1436 |
| Intentionally excluded FPU behavior | 3 | #951, #1019, #1022 |
| Fork-owned repository policy | 6 | #1026, #1102, #1103, #1136, #1258, #1279 |
| Missing correction added by this sync | 2 | #1044, #1046 |
| New upstream feature imported by the normal merge | 1 | #1375 |
| **Total** | **47** | |

### Notable adapted implementations

Source inspection confirmed, among other areas:

- Tidepool settings upload (#975);
- bolus/SMB labeling thresholds (#984);
- safe settings decoding and defaults (#1021);
- mmol/L ISF chart behavior (#1047);
- `@MainActor` app-version checking (#1093);
- the history refactor (#1127);
- Swift oref and its expanded tests (#1141);
- telemetry in Tai's deliberately modified endpoint configuration (#1149);
- settings search (#1165);
- the Omnipod manager migration, extended through Tai's device catalog (#1174);
- adjusted-ISF reporting (#1222);
- profile-before-autosens cold-start ordering (#1233);
- inactive-preset chart filtering and tests (#1325);
- quick-pick treatments (#1336);
- current-target refresh with profiles (#1357);
- Garmin complications (#1369);
- the later Tai Home refactor (#1373);
- Eversense and Accu-Chek CGM help entries (#1376);
- current-time snooze countdown behavior (#1390); and
- corrected smoothing help text (#1406).

PR #1375, including device alarm sounds/AlarmKit support, entered Tai through
the normal merge. Conflict resolution kept Tai's entitlements and release
metadata while adding the upstream sound resources to the Xcode project.

### Corrections added during the audit

Commit `b5484600ed` carries forward the only two applicable corrections found
absent from the Tai result:

- #1044: corrected Health permission text in the plist and string catalog; and
- #1046: Medtrum patch lifespan dates now use the grace-period date.

## Deliberate Tai differences

### FPU carb-equivalent scheduling remains excluded

Tai deliberately does not adopt Trio PR #951 or its dependent follow-ups
#1019 and #1022. Official Trio splits FPU entries into capped carb equivalents
and raises the minimum interval from 10 to 30 minutes. Tai retains its existing
duration-based implementation and 10-minute minimum.

This is a product decision, not a missing sync item. A future sync must keep
this divergence unless a separate Tai change explicitly reverses the decision.

### Fork-owned repository policy

Funding, README/contribution policy, signing, release configuration, branding,
CI version numbers, and submodule pins are owned by Tai. Consequently, official
Trio PRs #1026, #1102, #1103, #1136, #1258, and #1279 are accounted for but do
not overwrite Tai's policy. The normal merge likewise retained Tai's
`APP_DEV_VERSION`, release-notes repository, and copyright configuration.

## Verification performed

- `upstream/dev` at `8e07b51060` is an ancestor of the sync branch.
- `plutil` validated the merged Xcode project and plist.
- `jq` validated the edited string catalog.
- Xcode resolved the pinned package graph successfully.
- The complete Tai app and its watch target build successfully for the iPhone
  16 Pro iOS 26.0 simulator with Xcode's Swift 6.2 toolchain.
- The algorithm package compiles and runs 289 tests after repairing the stale
  `Determination.tick` test fixture. All tests outside the golden-parity suite
  pass, including the Round Basal suite.
- Twenty-one existing golden-parity assertions still report Tai-vs-golden data
  drift on this sync branch. The failures concern pre-existing profile fields
  and dosing rounding; they are not merge conflicts or evidence of an
  unaccounted Trio change.
- The private `Tai-dev/alpha` branch at `49250fe509` was checked independently:
  all 28 golden-parity scenarios pass there. Its parity/rounding work is not
  part of this Trio sync. It must be promoted after this sync through a
  separate, sanitized `fix/...` branch and PR so unrelated private alpha work
  cannot enter public `Tai/dev` accidentally.

The audit therefore attests upstream coverage, not byte identity. At this
bounded Trio head, the remaining functional delta is the traceable Tai fork:
Tai additions, Tai adaptations, or the deliberate exclusions recorded above.

## Routine Trio synchronization after this baseline

The `ours` strategy must never be used again for normal upstream syncs. Create
a temporary sync branch from current `Tai/dev`, merge official `Trio/dev`,
resolve only the current delta, test, and merge the reviewed PR into Tai:

```bash
git fetch --prune origin
git fetch --prune upstream
git switch dev
git pull --ff-only origin dev
git switch -c sync/trio-YYYY-MM-DD
git merge --no-ff upstream/dev \
  -m "sync(trio): merge upstream/dev at <upstream-sha>"
```

Each sync PR must record the upstream SHA, conflict decisions, deliberate
exclusions, verification results, and the resulting Tai merge commit. That
keeps every future change in `dev` attributable to Trio, Tai, or an explicit
fork-policy decision.
