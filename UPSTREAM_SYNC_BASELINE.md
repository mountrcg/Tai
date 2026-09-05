# Trio upstream synchronization baseline

Date: 2026-09-05

This file records the one-time ancestry reconciliation between the public
`Tai/dev` branch and the official `nightscout/Trio` `dev` branch.

## Attestation status

**Pending — do not merge the baseline PR yet.**

The ancestry baseline is technically valid, but it must not be interpreted as
confirmation that all applicable Trio behavior has been adopted until every
remaining adapted area below has been classified. Deliberately rejected Trio
changes count as accounted-for fork differences, not as missing changes, when
the decision and scope are recorded here.

## Baseline

| Role | Commit |
| --- | --- |
| Tai tree preserved by the baseline | `51aa320940beb8556cedfd0a014a0977a0f0365e` |
| Official Trio baseline | `efc0bc1b585b9c000ff8294f3c50288d6b9c110a` |
| Previous common ancestor | `d1bee890e9d53cb8e17cbd33991b4a13a626bd12` |
| Baseline merge | `653559ab7fbf8dee3633969f4b2f34694258326b` |

The previous common ancestor was dated 2026-02-13. Since then, Tai and Trio
had repeatedly integrated overlapping work through different merge and
cherry-pick paths. The code histories therefore diverged even where the
resulting behavior was the same or Tai contained a further-developed version.

## Why this was not a normal content merge

A trial merge of official `Trio/dev` into `Tai/dev` produced 144 unresolved
paths. The conflicts included:

- 84 paths below `Trio`;
- 41 paths below `TrioTests`;
- project files, package resolutions, configuration, and localization data;
- the `CGMBLEKit`, `DanaKit`, and `MedtrumKit` submodules; and
- many add/add conflicts where both repositories had independently imported
  the same feature.

Resolving those conflicts mechanically would have risked replacing newer Tai
adaptations with older upstream shapes and would not have represented the real
history. The baseline therefore uses Git's `ours` merge strategy: it records
the official Trio commit as an ancestor while deliberately preserving the
existing Tai tree exactly.

This is an ancestry baseline, not a claim that the Tai and Trio trees are
identical. Their differences are the maintained Tai fork delta.

## Audit of recent apparently missing upstream merges

Comparing first-parent merge subjects is conservative because independently
merged or cherry-picked work has different commit IDs. The following checks
were therefore also performed against the resulting Tai tree.

### Upstream changes already present exactly

The reverse upstream patch applied cleanly to the Tai tree, demonstrating that
the upstream result was already present:

- Trio PR #1444 — DanaKit fix;
- Trio PR #1412 — DanaKit update;
- Trio PR #1280 — Omnipod 5 support;
- Trio PR #1313 — MedtrumKit update; and
- Trio PR #1305 — fix for Trio issue #1301.

### Behavior already present in Tai's adapted structure

Direct source inspection confirmed the relevant behavior in Tai, although
surrounding files or paths had diverged:

- Trio PR #1406 — corrected smoothing help text;
- Trio PR #1390 — snooze countdown calculated against the current time;
- Trio PR #1376 — Eversense and Accu-Chek entries in CGM help;
- Trio PR #1357 — current glucose target refreshed with target profiles; and
- Trio PR #1325 — inactive presets excluded from the main chart, including
  regression tests.

### Net-neutral upstream sequence

Trio PR #1251 changed the loop indicator and Trio PR #1436 later reverted that
change. The pair has no net upstream feature to import as part of this
baseline.

### Tai-owned adaptations

These upstream areas exist in Tai but have subsequently been reorganized or
extended. Tai's current implementations remain authoritative during the
baseline:

- quick-pick treatments (Trio PR #1336);
- the Home refactor (Trio PR #1373);
- Garmin complications (Trio PR #1369);
- Swift oref becoming the default (Trio PR #1273); and
- the alerting rework (Trio PR #1269).

Repository signing, release configuration, branding, CI, and submodule pins
are fork-owned policy. They are not overwritten by upstream release or signing
merges such as Trio PRs #1279 and #1258.

### Intentionally excluded: FPU carb-equivalent scheduling

Trio PR #951 (`6f6c2534bb`) is not present in Tai and its aggregate patch applies
cleanly to the current Tai tree. Official Trio still contains the changed
implementation, while Tai retains the older duration-based implementation:

- Trio uses `splitIntoCarbEquivalents`, caps the scheduled total at 99 g,
  limits entries to 33 g, and adds regression tests;
- Tai still uses `calculateComputedDuration` and has no corresponding cap and
  split regression tests; and
- Trio raises the minimum FPU interval from 10 to 30 minutes, while Tai still
  permits 10 minutes.

**Decision (2026-09-05): Tai deliberately retains its existing FPU behavior.**
The Trio implementation is not wanted in Tai and must not be imported by a
future upstream synchronization merely because its patch is absent. This is
an intentional product difference and is therefore accounted for by the
attestation rather than classified as a missing change.

Dependent FPU follow-ups, including Trio PRs #1019 and #1022, are excluded
with PR #951 to the extent that they depend on its scheduling model. They may
only be adopted later through a separately reviewed Tai change that explicitly
revisits this decision.

## Outstanding attestation items

### Repository metadata

Trio PR #1026 adds `.github/FUNDING.yml` and is cleanly applicable. Tai has
deliberately not inherited upstream funding metadata; this is repository
policy rather than missing application behavior.

### Remaining adapted areas

Older upstream changes whose patches do not apply exactly because Tai later
modified the same files must still be recorded as one of: present in adapted
form, superseded, intentionally excluded, or missing. No unresolved item may
remain before the attestation status is changed to complete.

## Verification

The baseline merge has two parents: the preserved Tai commit and the official
Trio commit. Its tree ID is identical to the pre-baseline Tai tree:

```text
Tai tree before baseline: c07c2686390a6ec01c24b54145e13fc74f46759c
Tree after baseline:      c07c2686390a6ec01c24b54145e13fc74f46759c
```

After the baseline is accepted into `Tai/dev`, normal future synchronization
must use a real content merge on a temporary branch:

```bash
git fetch --prune origin
git fetch --prune upstream
git switch dev
git pull --ff-only origin dev
git switch -c sync/trio-YYYY-MM-DD
git merge --no-ff upstream/dev \
  -m "sync(trio): merge upstream/dev at <upstream-sha>"
```

The `ours` strategy is only for this documented one-time ancestry baseline. It
must not be used for routine future Trio synchronization.
