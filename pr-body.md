No tracking issue.

## Let the Trio-Complication Garmin app log carbs, deliver boluses and start presets

### Problem

The Garmin `Trio-Complication` app (`type="watch-app"`, `GarminWatchface.complication`) could only *receive* data. `BaseGarminManager.receivedMessage(_:from:)` accepted exactly one input, the bare string `"status"`, and turned it into a state refresh — every other message was dropped silently. Apple Watch users can log carbs, deliver a bolus, and start or stop override and temp-target presets from their wrist; on Garmin the same actions required picking up the phone, even though the watch is already paired, registered and receiving loop state.

Two structural reasons why this could not just be wired up:

1. There was no transport-neutral command path on the phone. The Apple Watch handlers are `private` inside `AppleWatchManager` and are bound to the WatchConnectivity session; the Garmin transport is Connect IQ. Nothing validated "a command that arrived over some watch link".
2. The only watch-bound send path is `broadcastWatchStateData`, which fans one payload out to *every* registered app (watchface + up to 4 datafields) and skips unchanged content via `lastSentDataHash` — set when a send is *initiated*, not when it succeeds. Acknowledgements and preset lists must reach exactly one app and must not touch that hash, so reusing the broadcast would have both leaked command UI data to unrelated apps and suppressed the next state update.

### Implementation

New `Trio/Sources/Services/WatchCommand/`:

- `WatchCommand.swift` — transport-neutral domain types: `WatchCommand` (bolus, carbs, mealBolus, activate/cancel override, activate/cancel temp target), `WatchCommandRequest` (request ID + originating app UUID + watch timestamp), `WatchCommandResult` (acknowledged / ackCode / message), `WatchPresetEntry` and the content-free error categories used for logging.
- `WatchCommandProcessor.swift` — `WatchCommandProcessor` / `BaseWatchCommandProcessor`: validation, gating, sequencing and results. Plus `WatchCommandAuthorization` (the revocation epoch) and `WatchCommandInsulinLane` (one insulin command at a time). Registered container-scoped in `ServiceAssembly`.
- `WatchCommandActions.swift` — pump / Core Data / preset side effects behind a protocol, so validation and sequencing are testable without a pump.
- `WatchCommandRequestCache.swift` — actor-owned dedup cache (256 request IDs, 15-minute lifetime): a reservation is taken *before* anything executes, duplicates in flight are refused, completed duplicates get the cached result back, a request ID reused for a different command is a conflict, and executing entries are never evicted.

`Trio/Sources/Services/WatchManager/`:

- `GarminCommandRouter.swift` — the v1 wire contract: strict envelope parsing (`v`, `req`, `requestId`, `date`, `command`, `payload`; exact key sets, no extra fields), per-command payload validation, and construction of the targeted replies.
- `GarminManager.swift` — transports only (plus a preset push when a command switch or Max Carbs changes, so the watch menu follows the phone within about a second): `GarminConnectIQClient` wraps the Connect IQ SDK (`register`/`appStatus`/`send`, injected for tests), `receivedMessage` routes one message and then (a) sends exactly one targeted reply to the requesting `IQApp`, (b) triggers the normal debounced state refresh when the result changed something, (c) pushes the targeted preset list to registered Complication apps when a preset was started or stopped. Preset storage changes (override/temp-target edits, activations and cancellations anywhere in the app) also push the preset list, debounced by 1 s. The broadcast path and its content hash stay untouched.

Wire contract v1 (what a watch sends / receives) — documented in the router, to be implemented by the CIQ app:

```
watch → phone: { "v": 1, "req": "status" } | { "v": 1, "req": "presets" }   (no request id, no state change)
watch → phone: { "v": 1, "req": "command", "requestId": <RFC-4122 UUID string>,
                 "date": <unix epoch ms>, "command": "<name>", "payload": { … } }
  bolus              { "bolus": <units> }
  carbs              { "carbs": <int grams> }
  mealBolus          { "carbs": <int grams>, "bolus": <units> }
  activateOverride   { "name": "<exact preset name>" }
  cancelOverride     {}
  activateTempTarget { "name": "<exact preset name>" }
  cancelTempTarget   {}
phone → watch: { "v": 1, "req": "ack", "requestId": <echoed string>,
                 "acknowledged": true|false, "ackCode": "<code>", "message": "<short user text>" }
phone → watch: { "v": 1, "req": "presets", "overridePresets": [{ "name": …, "isEnabled": … }],
                 "tempTargetPresets": [ … ],
                 "isCommandControlEnabled": Bool, "isBolusCommandEnabled": Bool,
                 "maxBolus": <U>, "maxCarbs": <g>, "bolusIncrement": <U> }
```

Legacy bare-string `"status"` keeps working. Booleans arrive from Connect IQ as `NSNumber` and are rejected as numbers; bolus units are rounded to 0.001 U (a Monkey C `Float` 0.1 arrives as 0.10000000149); `date` is milliseconds, unlike the Apple Watch payload's seconds. Ack codes reuse `AcknowledgmentCode` (`success`, `failure`, `carbs_logged`, `override_started`, `override_stopped`, `temp_target_started`, `temp_target_stopped`) and add `partial_failure` and `in_progress` (a duplicate of a command that is still executing; the watch keeps waiting instead of reading localized message text).

The preset reply carries the two command switches and the limits the Apple Watch already receives (`maxBolus` from the pump settings, `maxCarbs`, `bolusIncrement` from the preferences), so the watch can hide Bolus, cap its amount entry and show “Commands off in Trio”. The phone still enforces every limit itself.

Idempotency: the watch retries a command once when no ack arrives within 5 s (same request ID and timestamp), so a duplicate delivery is a normal case. Every command carries a request ID that is echoed in the ack; a resend gets the cached terminal result verbatim and never executes twice. The cache is in memory only (see *Not included*).

### Safety (S1, Robert's decision of 2026-09-26)

Phase 1 is **S1 for all mutable commands**, which is deliberately stricter than the current Apple Watch path (S0 + watch-side UI limits):

- **Registered app only.** Commands are ignored unless they come from a watch app this phone registered (`watchApps` match on app UUID *and* device UUID). Public app UUIDs in the READMEs are not enough to be answered.
- **Feature gates.** Master switch `isCommandControlEnabled` gates every mutable command; `isBolusCommandEnabled` additionally gates insulin. Status and the preset list keep working with both off.
- **Amount and safety limits.** Carbs are capped by `maxCarbs`; boluses go through `BolusSafetyValidator` (max bolus, max IOB, IOB availability, recent-bolus window) with a lookback that covers every bolus since the watch sent the command and never less than the shared 6-minute window (with the 2-minute freshness window this is always the 6 minutes). Rejections return a user-safe message and no insulin is issued.
- **Freshness.** A command timestamp must be within `[now − 2 min, now + 1 min]`; the future allowance only tolerates watch clock skew. The watch talks to the phone directly over Bluetooth through the ConnectIQ SDK and a command arrives in about a second, so 2 minutes is ample; the Apple Watch path has no freshness check at all. For insulin the window is re-checked after the lane wait, after validation and at the pre-issuance boundary, so queuing cannot outlive it.
- **Revocation that cannot be evaded.** `BaseSettingsManager.settings` `willSet` advances a monotonic revocation epoch *synchronously on the queue that writes the settings*, before a master or bolus switch-off is stored. A command is only admitted with the epoch it started under, so switching a setting off and back on before the async settings notification lands still voids everything admitted under the old settings; the notification now only contributes the refresh trigger. Turning a setting *on* never revokes.
- **Authorization at the side-effect boundary, not just at admission.** The processor validates up front, and every side effect re-runs the same check in its last serialized hop: `CarbsStorage.insertCarbEntry` runs it inside the Core Data transaction before the row is inserted, `AdjustmentManager.commitOverride`/`commitTempTarget` run it inside their transaction before any row is read or written, and the bolus task runs it immediately before `APSManager.enactBolus` with nothing awaited in between. A rejection there throws before anything is saved and before anything reaches the pump.
- **One insulin command at a time.** `WatchCommandInsulinLane` serializes all watch insulin, so each validation sees the previous command's delivery. Phase-1 policy, stricter than the shared recent-bolus rule (refused when the pump boluses of the last 6 minutes, SMBs included, add up to 20 % of the new bolus): once a bolus was handed to `APSManager`, the next watch insulin command is refused for 6 minutes (`BolusSafetyEvaluator.recentBolusWindowMinutes`), even if the pump or status check refused it — a refusal can still mean partial delivery and pump history may not show it yet. Only a final-check rejection (which never reached `APSManager`) withdraws that record. A suspended pump also makes the command wait for the lane and then be re-validated.
- **Meal + bolus is never reported as a full success by accident.** The carbs are stored first (so a refused bolus still leaves the meal logged), and the ack is `partial_failure` with “Carbs logged. No bolus was delivered.” / “…Bolus failed, check pump history before repeating.” — the Apple Watch path's unconditional `combo_complete` is not reused.
- **Logs and acks stay quiet.** Amounts, preset payloads and raw errors never enter a log line or an ack; errors are mapped to stable content-free categories (`presetNotFound`, `nothingActive`, `adjustmentPersistence`, `coreData`, `cancelled`, `cocoa(<code>)`, `unexpected`), because Core Data and adjustment errors can carry treatment values, preset names or store paths.

#### Why these limits

| Limit | Value | Reason |
|---|---|---|
| Freshness | 2 min old … 1 min ahead | The watch talks to the phone directly over Bluetooth (ConnectIQ SDK; the Garmin Connect app is only used to pick the device). A command arrives in about 1 s, and the watch's single retry after 5 s reuses the original timestamp, so a legitimate command is never close to 2 min old. The window only bounds how long a late or replayed command stays executable. That matters most for carbs, which have no recent-entry check: a watch command arriving after the user already logged the meal on the phone would log it twice and the loop would dose for food that wasn't eaten. Remote control uses 10 min (`TrioRemoteControl.timeWindow = 600`) for its own, slower channel; that value was the first draft here and was cut once the direct Bluetooth transport was confirmed. |
| Future allowance | 1 min | The phone compares the watch's timestamp with its own clock; a watch clock running slightly ahead must not get a fresh command refused. Not symmetric with the past window, because a future timestamp has no legitimate delay behind it. |
| Watch bolus after watch bolus | refused for 6 min | Pump history may not show the previous watch bolus yet, and a pump refusal can still mean partial delivery, so the shared 20 % rule could see "nothing recent" and allow a second full bolus. 6 min is `BolusSafetyEvaluator.recentBolusWindowMinutes`, the window remote control and the Shortcuts bolus already use, so all remote bolus paths share one interval. |
| Recent boluses | refused at ≥ 20 % of the new bolus within 6 min, SMBs included | The shared `BolusSafetyEvaluator` rule (`recentBolusThreshold = 0.2`) used by remote control and Shortcuts, reused unchanged so the watch is not looser than those paths. It counts every pump bolus event, because an SMB just delivered is insulin the new bolus would stack on. |
| Max Bolus / Max IOB / Max Carbs | the user's settings | The same limits the phone enforces everywhere; the watch only receives them to cap its entry, and the phone re-checks them. |
| Dedup cache | 256 request IDs, 15 min | 15 min outlives the 2-min freshness window plus both retries, so any request ID that could still be accepted is remembered. 256 entries is far above what a watch can send in 15 min. |
| Apple Watch comparison | — | The Apple Watch path has none of the phone-side checks above: `handleBolusRequest` calls `enactBolus` directly and only the watch UI caps the amount. It relies on WatchConnectivity live messages, which arrive immediately or fail. |

### User-visible settings

Watch Config → Garmin app → **Commands** section (`WatchConfigGarminAppConfigView`), both with a “?” help sheet:

- **Enable Watch Commands** — default **off**. Lets the Garmin app log carbs and start/stop override and temp-target presets. Status and the preset list stay available while off.
- **Allow Bolus Commands** — default **off**, disabled until the master switch is on, and switched off automatically when the master switch is turned off (so re-enabling commands never silently re-arms insulin). Explains that every bolus is checked against max bolus / max IOB / recent bolus, that those checks cannot tell who pressed the button on the watch, and to only enable it if the watch is kept locked and under the user's control.

`TrioSettings` stores the two flags; `GarminWatchSettings` decodes them with a hand-written `init(from:)`, so settings written by older versions keep commands **off** (`GarminCommandSettingsMigrationTests`). Both labels were added to the Settings search index.

### Testing

**End-to-end on a real watch (2026-09-27):** Garmin Enduro 3 with the `Trio-Complication` branch build, against this branch on an iPhone (build `cef2131`, beta complication UUID, which `c4fd2c1a6` switches back to live). Passed: switches off/on and the preset push that follows, carbs, bolus, meal + bolus (including 0 U = carbs only), limits, the recent-bolus refusal, override and temp-target start/stop, cancel with both running, no-answer with Bluetooth off and the late ack afterwards, double send executed once.

**Build and suites.** Verified by the independent review on the phase-1 tree (`8335f721e`; logs kept). The later commits add tests for the preset capabilities and the `in_progress` code; CI on the pushed branch covers the final tree.

- `CI=true xcodebuild build -workspace Trio.xcworkspace -scheme Trio -destination 'platform=iOS Simulator,id=66ACB141-5FFF-47ED-9701-2957699F7522' -derivedDataPath /tmp/t_0d334896/DerivedData` → **BUILD SUCCEEDED** (`/tmp/t_0d334896/build-arm64.log`).
- `CI=true xcodebuild test -workspace Trio.xcworkspace -scheme 'Trio Tests' -destination 'platform=iOS Simulator,id=66ACB141-5FFF-47ED-9701-2957699F7522' -resultBundlePath /tmp/t_0d334896/Result.xcresult -only-testing:TrioTests/{WatchCommandProcessorTests,WatchCommandCarbPersistenceTests,GarminManagerCommandIntegrationTests,GarminCommandRouterTests,GarminCommandSettingsMigrationTests,WatchCommandRequestCacheTests,WatchCommandRevocationIntegrationTests,BolusSafetyValidatorTests,CarbsStorageTests,CarbsNativeConversionTests,AdjustmentManagerTests}` → **TEST SUCCEEDED, 125 tests / 11 suites, 0 failures, 0 skipped** (`/tmp/t_0d334896/tests.log`, `/tmp/t_0d334896/Result.xcresult`).
- `AdjustmentManagerTests` is in the list because the adjustment entry points were refactored to shared `runOverride`/`runTempTarget` helpers — no behavior change for existing callers (`authorize: nil`, wait-for-upload preserved). 0 new warnings in the touched sources; 566 pre-existing project-wide `Sendable` warnings are unrelated.
- `git diff --check` clean.

What the suites cover: envelope parsing (exact key sets, missing/extra/wrong-typed fields, non-RFC-4122 and non-UUID request IDs, boolean-vs-number, ms timestamps, legacy `"status"`), router targeting (ack to the requesting app only, no broadcast), each command's payload validation and ack codes, freshness boundaries (stale / future / re-checked after the lane wait), feature gates and per-setting revocation (including the off-then-on sequence, asserted through the production settings path and through a synchronous epoch advance), the final-check boundaries (carb save, override/temp-target commit, pre-issuance for insulin, lane record restored only when nothing reached the pump), preset activation/cancellation semantics (exact unique name, inactive presets are still activatable, inactive-state cancellation is idempotent success, missing/ambiguous name rejected), dedup cache (in-flight, completed, conflict, full, generation-owned completion, eviction never touches executing entries), carb persistence failure propagation through a real `CarbsStorage`, and manager integration through a Connect IQ send spy (status, preset request, ack, preset push, retry).

### Not included (deferred by design, phase 1 scope)

- **S2 — HMAC-SHA256 message authentication and secret pairing.** Not implemented; the command channel still trusts the paired device plus the registered app UUID.
- **S3 — phone confirmation (Face ID / unlocked phone) before insulin.** Not implemented.
- **Durable request journaling.** The dedup cache is in memory only, so a phone app restart can forget a request ID. After a restart the 2-minute freshness window and the bolus safety checks are what stop a replay; restart-proof exactly-once for insulin would be a follow-up.
- **`requestBolusRecommendation`.** Not exposed to Garmin watches; a read-only v2 command on the same envelope.
- **Apple Watch migration.** `AppleWatchManager` keeps its own handlers; the only change there is the shared `AcknowledgmentCode.partialFailure` case. Migrating it onto the processor is a separate, separately reviewed cleanup.
- Other Garmin apps (Trio watchface, datafields, GarminAppTrioPerso) do not send commands; only the Complication app does.

### What to test

Settings and gates:

1. Watch Config → Garmin app: with fresh settings (or an upgrade from an older build), both switches are off; the preset list and status still work on the watch with commands off.
2. Try to enable “Allow Bolus Commands” while the master switch is off — it stays disabled; turn the master off after enabling bolus — bolus turns off with it.
3. Log carbs from the watch with the master switch off → ack says watch commands are disabled; nothing is stored in Treatments.
4. Start/cancel override and temp-target presets from the watch with commands on; verify the active preset on the phone and on the watch matches.
5. Try to start an override by name that does not exist (or exists twice) → rejected, nothing changes; cancel an already inactive override/temp target → reported as success.
6. Log carbs above the Max Carbs setting → rejected, nothing stored.
7. Bolus with the bolus switch off → rejected, no pump request. With it on: bolus above Max Bolus, a bolus that would exceed Max IOB, and a second bolus within the recent-bolus window → each rejected with the matching message and no insulin.
8. Meal + bolus where carbs are above Max Carbs → rejected before anything is stored.
9. Insulin lane: send two boluses back to back from the watch → the second is refused as “A bolus was given in the last 6 minutes.”, not issued.
10. Freshness: send a command with a stale (>2 min) and a far-future timestamp → rejected; a duplicate delivery of an already-executed request ID → the cached answer, executed once (check Treatments / pump history for a single entry).
11. Revocation mid-flight: start a bolus, then immediately turn the master switch (or bolus switch) off and back on before the app has processed it → the command is refused, no insulin issued.
12. During a pump suspend, send a bolus from the watch → it waits for the pump and is re-validated (delivered once the pump is available, or refused — never issued twice).
13. UI: the two new toggles and their help sheets render correctly in light and dark mode.

### Screenshots

Watch Config → Garmin app → Commands section and the two help sheets (iPhone, dark mode):

| Commands section | Enable Watch Commands help | Allow Bolus Commands help |
|---|---|---|
| <img src="https://raw.githubusercontent.com/mountrcg/Tai/84f41dd18cf19519bf65b60baae1f18bef29b240/garmin-watch-commands/commands-settings.png" width="260"> | <img src="https://raw.githubusercontent.com/mountrcg/Tai/84f41dd18cf19519bf65b60baae1f18bef29b240/garmin-watch-commands/help-enable-watch-commands.png" width="260"> | <img src="https://raw.githubusercontent.com/mountrcg/Tai/84f41dd18cf19519bf65b60baae1f18bef29b240/garmin-watch-commands/help-allow-bolus-commands.png" width="260"> |
