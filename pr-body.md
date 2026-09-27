## Garmin watch commands: carbs, bolus, meal + bolus, override / temp-target presets

The Trio-Complication Garmin app can now log carbs, deliver a bolus and start or stop override and temp-target presets, as the Apple Watch can. Until now `GarminManager.receivedMessage` accepted only the string `"status"` and dropped everything else.

### Changes

`Trio/Sources/Services/WatchCommand/` (new, transport-neutral)
- `WatchCommand.swift`: commands, request (ID, app UUID, watch timestamp), result, preset entry.
- `WatchCommandProcessor.swift`: validation, gates, sequencing, results; `WatchCommandAuthorization` (revocation epoch), `WatchCommandInsulinLane` (one insulin command at a time).
- `WatchCommandActions.swift`: pump, Core Data and preset side effects behind a protocol.
- `WatchCommandRequestCache.swift`: request-ID dedup, 256 entries, 15 min.

`Trio/Sources/Services/WatchManager/`
- `GarminCommandRouter.swift`: v1 envelope parsing and replies.
- `GarminManager.swift`: routes a message, sends one targeted reply to the requesting app, refreshes state when something changed, pushes the preset list to Complication apps on preset or command-setting changes. The state broadcast and its content hash are untouched.

Settings: Watch Config → Garmin app → **Commands**: *Enable Watch Commands* and *Allow Bolus Commands*, both off by default, with help sheets. Turning the master switch off also turns bolus off. Settings from older versions decode with both off.

### Wire contract v1

```
watch → phone  { v:1, req:"status" } | { v:1, req:"presets" }
watch → phone  { v:1, req:"command", requestId:<UUID>, date:<epoch ms>, command, payload }
               bolus {bolus} · carbs {carbs} · mealBolus {carbs, bolus}
               activateOverride {name} · cancelOverride {} · activateTempTarget {name} · cancelTempTarget {}
phone → watch  { v:1, req:"ack", requestId, acknowledged, ackCode, message }
phone → watch  { v:1, req:"presets", overridePresets:[{name,isEnabled}], tempTargetPresets:[…],
                 isCommandControlEnabled, isBolusCommandEnabled, maxBolus, maxCarbs, bolusIncrement }
```

The bare string `"status"` still works. Ack codes reuse `AcknowledgmentCode` and add `partial_failure` and `in_progress`. Bolus units are rounded to 0.001 U; `date` is in milliseconds.

### Safety and limits

| Check | Value | Reason |
|---|---|---|
| Registered app | app UUID + device UUID | Only apps this phone registered are answered. |
| Switches | master; bolus additionally | Status and preset list work with both off. Switching off revokes commands already admitted, also if switched back on before they run. |
| Freshness | 2 min old … 1 min ahead | Direct Bluetooth link (ConnectIQ SDK); a command arrives in about 1 s and the watch's one retry keeps the original timestamp. The window limits how long a late or replayed command can run; above all a carbs entry already made on the phone must not be logged twice. 1 min ahead tolerates a watch clock running fast. |
| Watch bolus after watch bolus | refused for 6 min | Pump history may not show the previous bolus yet, and a refused pump request can still mean partial delivery. 6 min = `BolusSafetyEvaluator.recentBolusWindowMinutes`, as for remote control and Shortcuts. |
| Recent boluses | refused at ≥ 20 % of the new bolus within 6 min, SMBs included | Shared `BolusSafetyEvaluator` rule, unchanged. |
| Max Bolus, Max IOB, Max Carbs | user settings | Checked on the phone; the watch only uses them to cap its entry. |
| Duplicates | request ID, 15 min | A resend gets the cached result and never runs twice. |

Every side effect re-checks authorization in its last step: inside the carbs and override / temp-target transactions, and directly before `enactBolus`. Meal + bolus stores the carbs first and answers `partial_failure` if the bolus is refused. Logs and acks contain no amounts, preset names or raw errors.

The Apple Watch path has none of these phone-side checks.

### Testing

- Enduro 3 with the Trio-Complication branch against this branch: switches, preset push, carbs, bolus, meal + bolus (0 U = carbs only), limits, bolus interval, override and temp-target start / stop, cancel with both running, no answer with Bluetooth off, double send executed once.
- Unit and integration suites for router, processor, cache, revocation, carbs persistence and manager: 125 tests passed at `8335f721e`. The later commits add tests for the preset capabilities, `in_progress` and the 2-minute window; CI covers the final tree.

### Not included

- Message authentication (HMAC) and phone confirmation before insulin.
- Durable request journal: after a phone app restart the freshness window and bolus checks prevent a replay.
- `requestBolusRecommendation`.
- Moving `AppleWatchManager` onto the processor.

### Screenshots

<img src="https://raw.githubusercontent.com/mountrcg/Tai/84f41dd18cf19519bf65b60baae1f18bef29b240/garmin-watch-commands/commands-settings.png" width="260">

Help sheets follow with a build of `0db293f71` (their text changed there).
