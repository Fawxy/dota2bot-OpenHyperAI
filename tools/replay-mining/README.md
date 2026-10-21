# replay-mining

Offline tooling for lane-management data. Pipeline: `fetch_replays.js` -> `go run ./parser <dem> > out/<id>.ndjson` -> `mine.js` -> `gen_camps.js`; `parse_condebug.js` summarises in-game `[H:lane]` log lines. Tests: `node test/run.js` (part of `tests/humaniser` `npm run check`; Go is not needed).

## Limitation: half pulls need divert data the parser does not produce
Combat-log unit names are shared by many entities, so lane-creep attackers cannot be tied to a unique entity. The parser therefore emits no `srcEnt` and no `creep` samples. `detect.js` still computes divert when a stream supplies them (the tests do), but on parser output every pull has `divert === undefined` and `half === false`: `halfAggroSec`/`halfMeetPoint` are never generated, and half and full pulls are pooled in `pullAggroSec`. Stack mining is unaffected. `parser/main.go` is uncompiled; verify its entity resolution against a real replay.
