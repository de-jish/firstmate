# Decision hold lifecycle mechanism

The normative policy is owned by `.agents/skills/decision-hold-lifecycle/SKILL.md` and is not restated here.
This document records the deterministic mechanism, structured surfaces, and privacy-safe regression evidence.

## Mechanism

`bin/fm-decision-hold.sh` is the only lifecycle command for an investigation or visual review's unresolved captain decisions.
The command runs tasks-axi in the active `FM_HOME`, so the existing backlog remains the only durable work database and a secondmate-owned decision stays in the secondmate home.
It never reads report bodies, review artifacts, terminal output, or chat.

The `hold` subcommand maps an originating work id and stable decision key to `<origin-id>-decision-<decision-key>`.
It creates a kind `captain` backlog item when absent and invokes `tasks-axi hold <id> --reason <reason> --kind captain` on every retry.
It rejects an identity collision, a changed title, and attempts to reopen an already resolved identity.
"Already resolved" is the signal `verify` reads, not the closed state alone.
Reading the state alone once let `hold` report a decision closed outside the script as already durably resolved while `verify` called the same identity neither actively held nor durably resolved, and that contradiction is what let a wrong close look finished.
Both refusals stand unchanged; only the diagnosis a wrong close receives is now true, and it names the command that clears it.

The `complete` subcommand unions the reviewed keys into `decision_keys=` and appends `decisions_reviewed=1` while originating task metadata is live.
A post-teardown visual review can complete against the surviving report and durable holds without recreating volatile task metadata.
It accepts `--none` as an explicit semantic inventory result, not as inferred absence.
It verifies every listed identity against tasks-axi before recording completion.
For an open keyed status decision, it appends a `captain-held [key=<key>]: ...` transfer event only after the matching backlog hold is durable.
`bin/fm-classify-lib.sh` recognizes that transfer as closing the live status copy without claiming that the captain has answered it.

Scout teardown calls the script's read-only `verify` subcommand after checking for the report and before removing any source state.
The `--force` path remains the explicit captain-approved discard escape hatch.

The `audit` subcommand is that gate's fleet-wide read-only counterpart, and `bin/fm-bootstrap.sh` prints each of its findings as a session-start `DECISION_HOLD:` line.
It exists because `verify` only ever runs at one origin's own teardown: a home that never tore that origin down held a broken decision ledger and had no way to learn it.
The audit reports every captain decision identity that is neither actively held nor durably resolved, reading the same fields `verify` reads, so a session-start finding and a teardown refusal can never disagree about one identity.
It is a detector and not a gate: it always exits 0, and stays silent when tasks-axi cannot be read at all, because bootstrap already reports that on its own line.
A finding names a remediation only where one command is correct for every state that finding fires on, and a printed remedy is only kept where a regression walks it.
The open-state finding fires on every open state a decision hold can reach, so it names no command and points at the recovery section below, which is the one place that can be exhaustive about them.
It judges exactly what `data/backlog.md` still holds, and it says nothing at all about an identity retention has already archived out of it.
That identity is not unresolved, it is unreadable: the archive is not addressable through the owner tool, so a decision the captain answered correctly and retention then archived would otherwise be reported as a defect at every session start forever, and the remediation would tell the agent to re-raise a decision that is already answered.
That is the coverage bound, and it is worth stating as plainly as it deserves rather than as a footnote: a hold closed outside its owner AND archived out of `data/backlog.md` before any session start in this home produces no audit line, ever.
That is the third failure of the original incident, and this detector does not catch it once retention has run.
Two things narrow the bound without closing it, and neither is offered in place of the admission above.
The audit runs at every session start, so the window is every wrong close that happens between one session and the further `done_keep` closes that evict it, rather than a window someone has to remember to open.
And `verify` still refuses an absent identity at that origin's own teardown, which is where an agent is present to act on it.
The home's recorded `decision_keys=` inventories do not extend the scan past the backlog either; they say which of the identities the backlog still holds this home owns as reviewed decisions, which is what admits one whose creation body a later write replaced.
An identity is in scope when the home recorded it in a `decision_keys=` inventory or its own record still carries the creation body `hold` writes, and never on `hold_kind` alone, which `AGENTS.md` section 10 puts on every captain-gated thread.
The report's remediation rewrites the body of whatever it names, so a wrong subject would not merely cry wolf: it would manufacture a resolution record on an ordinary captain thread whose id merely spells the decision separator.
Both in-scope sources also carry the identity's own origin id and decision key, because `<origin-id>-decision-<decision-key>` cannot be split back apart when the origin id spells the separator too, and a re-split id would make `audit`, `hold`, and `repair` disagree about one identity.

Because it runs at every session start, the audit's price may not rise with the number of decisions a home carries; a control that gets slower the more it protects is a control someone turns off.
One `tasks-axi list --fields held,hold_kind,body` call carries the fields a healthy verdict reads, and every identity that listing proves properly held or durably resolved leaves the scan without a further call, so a healthy home costs one backlog read rather than one per decision.
That listing is also the whole candidate set, which is what keeps an archived identity out of the scan for free rather than at the price of a lookup that could only ever come back empty.
The listing decides only what to SKIP.
Nothing is reported on listing evidence: whatever it does not prove healthy is re-read from its own record before a line is printed, so a quoted title, an escaped body, or a body the listing truncated can cost a confirmation call and can never manufacture a finding.
That bound is a property of the construction rather than something measured at run time, and the regression pins the count.
The sweep carries no elapsed-time record and cannot from where it runs: `bin/fm-timing-lib.sh` records only while `FM_TIMING_LOG` names a file, the deferred network stage is the only thing that allocates one, and it does so while invoking `bin/fm-bootstrap.sh` with `FM_BOOTSTRAP_NETWORK=only`, which is the one phase that skips the local detection this sweep belongs to.
A bracket there would never fire on a run a home actually makes, and an instrument that cannot fire is worse than none, because the next reader takes it for coverage and stops looking.

The `resolve`, `answer`, and `decline` subcommands close active holds, while `repair` attests a hold already closed outside the script.
All four require a non-empty captain decision file and record the same resolution block in the hold body with the decision digest, routed identities, and a `Resolution mode:` naming the path.
An exact retry is idempotent, while a changed decision or, for `resolve`, a changed routed-task set is rejected.

The `resolve` subcommand is the routed path and additionally requires at least one existing dependent task whose structured `blocked-by` edge points to the hold.
It clears each dependency edge through tasks-axi and marks the hold Done only after those writes succeed.
An exact retry can finish a partial routing operation, and a failed intermediate step leaves the hold open.

The `answer` and `decline` subcommands share one unrouted close implementation and differ only in the `Resolution mode:` they record and the outcome word they print, so neither can drift into a weaker close than the other.
Both record `(none)` as the routed identities and refuse while any task in the same backlog is still blocked by the hold, because releasing routed work without recording it is `resolve`'s job.
Every candidate found in the listing prefilter is confirmed against its own structured record before the refusal is reported.
`answer` exists so the act carrying a captain answer can also be the act that closes its hold; `decline` continues to mean the stronger claim that the answer routes no follow-up work at all.

The `repair` subcommand records the resolution block on a hold that was already closed outside the script, such as by a direct `tasks-axi done`, so an origin whose decision was genuinely answered stops failing `verify`.
It refuses a hold that is still actively held, never reopens a closed hold, and never clears a dependency edge, so an unanswered decision keeps blocking teardown until the captain's word closes it.
It also requires the identity to carry captain-hold provenance, so an ordinary captain-kind task that was never held cannot be repaired into a resolved decision.
Provenance is two signals, because an out-of-band close can erase either one on its own.
`tasks-axi` preserves `hold_kind` through a close but clears it on `unhold`, while the creation body `hold` itself writes survives `unhold`.
Both are written only by `hold`, so an identity this script never created still carries neither and is still refused; widening the evidence base is what keeps a decision that was unheld out of band from becoming permanently unattestable, and with it permanently unable to pass its origin's completion gate.
Because a successful repair replaces that creation body, the already-repaired retry is settled before provenance is read, so an exact retry stays idempotent for every hold rather than only for the ones that kept their `hold_kind`.

`hold_kind` is enough for `repair` to act on an identity the caller named itself, and it is never enough for another command to name that identity to the caller.
Acting and suggesting are different questions because a suggestion is followed: a printed `repair` invocation that lands on the wrong subject records a captain decision no captain gave, which is the harm the whole ledger exists to prevent.
So `hold`, `answer`, and `decline` reach one shared gate before they print a `repair` invocation, and none of those three carries its own copy of a clause about a closed identity.
`resolve` and `verify` refuse a closed identity with their own wording and do not route through that gate.
That gate asks `repair`'s own kind and provenance preconditions, so it never names a command `repair` would refuse, PLUS a suggestion-scope rule `repair` deliberately does not have.
It therefore answers a narrower question than `repair` does - should this identity be handed a repair command, not would `repair` accept it - and the reasoning for keeping that asymmetry lives beside the gate in `bin/fm-decision-hold.sh`, because that is where someone would be tempted to tidy it away.
An identity the scope rule declines is refused with a text that states only what the rule tested, and never asserts what `repair` would do with it, because `repair` reads a wider signal and may well accept it.
An identity that fails any of them is refused with a shared text that never names a `repair` invocation, and for a closed identity the kind and lost-provenance refusals are the audit's own sentences verbatim, so one closed identity gets one verdict across those four surfaces.
Whether that shared text names any command at all is decided per refusal rather than once, because the three refusals know different amounts.
The out-of-scope refusal names none, because the scope rule tested nothing that would license one and `repair` may well accept the identity anyway.
The kind refusal names the `tasks-axi update` that restores the identity, and the lost-provenance refusal names the four-step same-key recovery, because each of those is one command sequence that is correct for every identity its finding fires on and a regression walks it end to end.
The closed-identity qualifier is load-bearing rather than decoration, because only a closed identity routes through that gate: an identity whose kind drifted while it is still open gets the audit's sentence at session start, and `hold` and `answer` refuse it in each site's own shorter wording instead.
That kind sentence splits on whether the record still carries a durable resolution block, because an identity that already holds a recorded captain answer must be restored rather than re-raised, and it names the `tasks-axi update` that actually clears the finding under either shape.
The lost-provenance sentence names the same-key recovery for the same reason: `complete` recorded that key in the origin's inventory and `verify` reads that inventory, so raising the decision again under a fresh key answers the captain's question while stranding the old key, and the finding and the origin's completion gate both keep refusing.
The refusals themselves are unchanged at every site; only the remediation a lookalike is handed changed.

## Recovering an open decision hold

The audit's open-state line states what it read and names no command, because that one line fires on every open state a decision hold can reach and no single recipe is correct for all of them.
For the same reason it claims only what is true of all of them - that no close path in this ledger accepts the identity while it sits in that state - rather than describing the hold, which `tasks-axi start` leaves in place on an otherwise healthy decision.
The recovery is here instead, in one place where it can be exhaustive and where correcting it corrects every caller at once.
`hold` is the only command that re-activates an identity, and it requires the identity to be `queued`, so each state below is a matter of getting back to `queued` first.
An identity whose `kind` drifted off `captain` is a different finding with a different line, and that line names the `tasks-axi update` that clears it.

**`state=queued held=no`** - the hold was released, typically by `tasks-axi unhold`, and the decision is now invisible to the captain.
Re-activate it with `bin/fm-decision-hold.sh hold <origin-id> <decision-key> --title "<the title it already carries>" --reason "<reason>"`, which restores the captain hold, and then close it with `resolve`, `answer`, or `decline`.
The title must match the one the identity already carries, because `hold` refuses a changed title on an existing identity.

**`state=queued held=yes` with `hold_kind` other than `captain`** - the hold was released and then re-held for something that is not the captain, so it blocks work without recording a captain question.
The same `bin/fm-decision-hold.sh hold` re-holds it with `--kind captain` and clears the finding.

**`state=in_flight`** - someone ran `tasks-axi start` on the identity, which `tasks-axi` accepts whether or not the captain hold is still on it, so this shape covers both `held=no hold_kind="-"` and `held=yes hold_kind=captain`.
Do not reach for `hold` first: it refuses an identity that is not queued, but it applies the captain hold BEFORE it refuses, so a run that exits 1 still leaves the record at `held: yes` and `hold_kind: captain` and the identity no closer to closable.
Return it to `queued` with `tasks-axi reopen <hold-id>`, which is the whole recovery for the held shape and the first half of it for the released one, and then re-activate it with `bin/fm-decision-hold.sh hold` if it is not already held for the captain.
`reopen` moves a Done or In flight task back to Queued and is idempotent, so it needs nothing before it: it preserves `held` and `hold_kind` exactly as it found them, and the routed work stays blocked through every step.
No step of this recovery closes the identity, and none may be added that does.
Closing a captain hold with `tasks-axi done` is the incident this ledger was built to detect, it releases the routed work the hold exists to block for as long as it is closed - `tasks-axi ready` will offer that work for dispatch in the gap - and an interrupted recovery would leave exactly the closed-with-no-resolution-record shape the out-of-band-close finding names.
Do not reach for `repair` either, and do not answer the decision under a fresh key; `repair` refuses an identity that is still open, and a fresh key strands this one in the origin's reviewed inventory where `verify` keeps refusing it.

## Answer-time closure

The live status-log decision ledger has always had answer-time closure through `bin/fm-send.sh --resolve-key`: answering a keyed decision closes it in the same act.
The durable hold ledger did not, so an answer could be captured, believed, and even implemented while its hold stayed open, and the captain could then be asked to re-answer a decision already on disk.

"A keyed answer closes its matching hold" is now one capability with one owner.
`answers` is its channel-agnostic entry point: it reads a key, answer, and label on each input line and closes the matching hold through the same `answer` path, so every guard applies identically no matter which channel the answer arrived on.
For a single-origin intake the key is the decision key mapped under that bound origin; for the cross-origin intake it is the full hold identity, while keys that do not name a full decision hold feed nothing.
`--source` is provenance text recorded in the durable decision, never a behavior switch, and the command carries no per-channel branch and no knowledge of chat, review decks, or any transport.
A channel's only job is to turn whatever it received into those keyed lines and pipe them in; it never maps keys to holds, builds decision records, chooses between the close paths, or closes a hold itself.
The decision text is a pure function of source, key, answer, and label, which is what makes a replayed delivery an idempotent no-op rather than a rejected different decision.
A key whose hold is absent, already closed, or still blocking routed work is reported as skipped and left for `resolve`, and the command exits nonzero when any key was skipped.

`bind`, `unbind`, and `binding` record whether a captured-answer source belongs to one origin or uses the cross-origin intake, for a channel whose answers arrive detached from the origin.
The binding is a private record under `state/decision-bindings/`, and a source with no binding feeds nothing, so the path is opt-in per source.
`bind` deliberately does not require the source to exist yet, so a channel can be bound before it is armed and never produce an answer that has nowhere to go.
The script header and `--help` own the exact cross-origin marker, identity split, limits, and refusal behavior.

Two channels feed that one intake today, and both are ordinary callers rather than special cases.

`bin/fm-send.sh --resolve-key` is the chat channel.
Its existing status-log close is unchanged for a key the status log still owns.
For a key the status log no longer owns it checks whether that key names an active captain hold on the target task, and feeds the answer as one keyed line if so, which is what lets chat answer a decision already transferred to its hold.
A key open in neither ledger is still refused before anything is sent.
Because `complete` closes the live status copy at the moment it transfers a decision to its hold, the two ledgers are the two sides of one transfer and never both own a key at once, so the common path still performs no backlog read.

`bin/fm-procevent.sh` is the captured-result channel, and its wiring is generic.
After capture, a bound source has its result passed to `bin/fm-procevent-<adapter>.sh answers <result-file>` and whatever that prints is piped into the intake, so any adapter with an `answers` command works and the runner names no adapter, parses no result, and carries no decision rule.
Feeding is independent of handling: it never acknowledges a result and never suppresses a wake, so recording the captain's answer cannot retire the notification firstmate needs in order to act on it.
`bin/fm-procevent-lavish.sh answers` is one such adapter command; it reports the structured choices a review captured and stops there, reading only rows tagged `choice` so freeform captain prose can never forge a decision key.

## Structured read surfaces

`bin/fm-fleet-snapshot.sh` parses canonical tasks-axi `(hold: ...)` and `(hold-kind: captain)` metadata alongside existing backlog fields.
It resolves every repeated `blocked-by:` edge against structured Done records, keeps missing blockers unresolved, and classifies only an unblocked captain hold as actionable.
Its secondmate-home summary classifies an actionable captain hold as `captain_decision` and preserves blocked captain holds as queued work in the owning home.

`bin/fm-bearings-snapshot.sh` projects actionable captain holds into `decisions_open` and leaves blocked captain holds in ordinary queued gates.
It excludes completed kind `captain` records from Recently Landed.
The projection remains read-only and does not inspect historical prose.

## Verification record

Verification date: 2026-07-14.
Additional quoted `blocked_by` regression verification date: 2026-07-17.
Plural blocker-readiness and mixed-home projection verification date: 2026-07-22.
Unrouted close-path verification date: 2026-08-13.
Answer-time closure verification date: 2026-08-16.
Cross-origin answer-time closure verification date: 2026-08-19.
Session-start audit and out-of-band-close provenance verification date: 2026-08-20.
Remediation-suggestion scope verification date: 2026-08-20.
Archived-resolution silence verification date: 2026-08-20.
Kind-drift detection verification date: 2026-08-20.
Repair-suggestion gate completeness verification date: 2026-08-20.
Kind-drift remediation verification date: 2026-08-20.
Out-of-scope refusal wording and hold routing verification date: 2026-08-20.
Lost-provenance remediation verification date: 2026-08-21.
Routed-close remediation branch and restored verification record date: 2026-08-21.
Open-state verdict, its recovery guidance, and the re-captured lost-provenance transcript verification date: 2026-08-21.
Open-state verdict truth across every open shape verification date: 2026-08-21.
Red-first proof of the open-state regression, and stale-claim sweep, verification date: 2026-08-21.
Close-free in_flight recovery and forbidden-close sweep verification date: 2026-08-21.

The focused end-to-end regression uses only synthetic `sample` identities and decision text.
It begins with a completed investigation and visual review whose genuine unresolved choice exists only in the report.
The initial Bearings snapshot correctly has no open decision, and the new teardown gate refuses to erase the source.
A later regression covers tasks-axi's quoted multi-entry `blocked_by` output so `resolve` matches the first, middle, and last ids and rejects a genuinely absent id.

Three further regressions cover the close paths that route no work.
A declined decision closes with a recorded answer, satisfies `verify`, leaves Bearings' Captain's Call, and is refused while the hold still blocks routed work.
A hold closed by a direct `tasks-axi done` reproduces the shape that fails `verify` and blocks teardown, and `repair` with a captain decision file clears both.
An unanswered decision still blocks completion and teardown, and neither `decline` nor `repair` can close a hold that is still actively held or supply an answer with a missing or empty decision file.
`repair` also refuses a closed captain-kind task that was never held for the captain.

Three answer-time closure regressions run against the published poll response shape, with synthetic `sample` identities.
A bound source whose origin exposes six holds captures one review carrying five structured choices plus one freeform message, and the runner feeds it through a fixture adapter that is not the review adapter at all, so what is proven is that any bound channel with an `answers` command gets closure rather than that one channel is wired specially.
Four holds whose answers route no work close, the one still blocking routed work is skipped and stays available to `resolve`, and the one whose key appears only inside the freeform prose never closes.
The capture is left unacknowledged throughout, so the wake firstmate needs in order to act on the answers is never retired.
A replayed delivery closes nothing new and is not rejected as a different decision, a source with no binding closes nothing at all, and the `answer` subcommand itself refuses an empty or missing decision file, an absent hold, and a drifted retry.
A separate regression drives the real `fm-send` over a stubbed transport to prove the chat channel reaches the same intake for a decision already transferred to its hold, which the status ledger alone can no longer close.
The cross-origin regression drives a bound source through the real runner and adapter interface, closes full-identity holds from different origins, and proves that over-limit, malformed, non-decision, routed-work, absent-hold, and replayed answers all fail or skip without weakening the existing guards.

One further regression covers the session-start audit and the wrong-close shapes it exists to name.
It reproduces all three with the exact commands that caused them - a direct `tasks-axi done`, an `unhold` followed by `done`, and a bare `unhold` - and proves the completion gate refuses, the audit names each defect, and the same findings reach a session start as `DECISION_HOLD:` lines.
The two closed shapes are cleared by the `repair` invocation their own line prints, and the released one by the recovery this document records for it, because the open-state line prints no command.
It proves `hold` and `verify` now give one verdict about one identity, that an ordinary captain-gated thread whose id merely spells the decision separator never enters the report whether it was held for the captain first or never held at all, and that the report empties only as each decision is closed with the captain's word and not before.
The unheld close is attested by `repair` rather than left permanently unattestable, while a closed captain-kind task the script never created is still refused.
A companion regression drives one origin id that spells the decision separator itself through the whole cycle and proves `audit`, `hold`, and `repair` reach a single verdict about that identity, so the report's own printed remediation always acts on the decision the report named.
Two further regressions pin what makes the detector survivable in daily use.
The cost case records every `tasks-axi` invocation the session-start audit makes and proves the count does not change when the home grows from two properly held decisions to six, while a decision closed outside its owner is still named and still re-read from its own record.
The message case releases a hold and re-holds it for something other than the captain, and proves the printed line never denies the state printed beside it, names the `hold_kind` that makes it a defect, and clears only when the recovery this document records for that shape is actually run.

A fourth drives an ordinary captain-gated thread through `hold`, `answer`, and `decline`, proves none of them names a `repair` invocation for it and that its body survives every refusal untouched, and proves all three still name the remediation for a decision this script really created.
A fifth answers three decisions through their owner, drives real retention by closing eleven unrelated tasks until `.tasks.toml`'s `done_keep` moves them into the archive, and proves the audit and the session start both stay silent about them while `verify` still refuses the absent identity at that origin's teardown.
The fourth also covers both ways an identity drifts off kind `captain` - closed out of band and then moved, and answered through its owner and then moved - and proves `hold`, `answer`, and `decline` name no `repair` command for either, give the audit's own sentence, and never claim a recorded decision is unrecorded.
It closes with the identity the scope rule declines but `repair` accepts, and proves the refusal states only what the rule tested while `repair` still attests it, so no surface asserts something a reader can disprove in one command.
A sixth moves a reviewed decision off kind `captain` with `tasks-axi update`, and proves the audit and the session start both name it and that the finding clears when the kind is restored.
A seventh follows the lost-provenance remediation instead of paraphrasing it: it parses the commands out of the audit's own line, substitutes the placeholders an operator supplies, runs them in the printed order, and proves that the audit then falls silent and the origin passes `verify` again.
It walks both branches of the printed line, because the last step names `resolve` for a hold that still blocks routed work and `answer` for one that does not, and a remedy is only followable if every branch it names can be completed.
It executes the printed text rather than the code path behind it, so a remediation that stops being followable fails the test even when every predicate still behaves.
An eighth pins the open-state fall-through to what a verdict may say, and its subject is deliberately the shape the wording was NOT written against.
It drives a correctly held decision to `state=in_flight held=yes hold_kind=captain` with the single `tasks-axi start` that `tasks-axi`'s own `ready` and `show` help advertise, keeps a routed task blocked behind it throughout, and proves the line asserts none of the six claims that state falsifies, reports the state, held and hold_kind fields the record actually carries, names none of the eleven mutating invocations the two tools offer here, and points at this document.
It carries the released shape alongside it and requires the two lines to be the same sentence once the parenthesised field group is stripped, because a verdict that reads differently for two shapes it fires on has been tuned to one of them.
It also proves the read leaves the record byte-identical and repeats identically, then runs the recovery this document records for `in_flight`, and proves the finding clears, the routed task is still blocked, and the origin passes `verify`, so the guidance is proven followable rather than asserted.
The sixth, `test_audit_names_a_reviewed_decision_moved_off_kind_captain`, is the one regression that fails if a `--kind captain` filter is ever restored to the audit's listing, which is the only way that detection could be deleted while every other regression stayed green.

### Reproduce, catch, revert, as of 2026-08-21

The transcript recorded in commit `bd041d4` is superseded, not broken.
It is accurate evidence of what the guard emitted the day it shipped, and one of its lines no longer reproduces because the message was corrected afterwards: the released-hold finding read `is open but no longer actively held (state=queued held=no)`, which denied the state it printed whenever the identity had been re-held for something other than the captain, and it was corrected to `is open but carries no active captain hold (state=queued held=no hold_kind="-")`.
That same line has since been corrected twice more, for two further reasons, and both earlier wordings are recorded here rather than dropped.
The first of the two ended `re-activate it with fm-decision-hold.sh hold before closing it with the captain word`, which is a remedy that fires on every open state and is correct for only some of them, and it now ends by pointing at the recovery section above instead.
The second opened `is open but carries no active captain hold` and claimed the identity `neither blocks work nor records an answer`, which a single `tasks-axi start` on a healthy hold falsifies: the record then reads `held=yes hold_kind=captain` and its dependents stay blocked, so the sentence denied the fields printed beside it.
It now says only what is true of every open shape - the identity is in a state this ledger cannot close - and the blocks below carry the current text.
Every block below was captured by running the commands against the shipped code, at the end of the change that last touched this mechanism, under the standing rule recorded two paragraphs down.
That rule is what keeps them current, so nothing here names the commit they were captured against - a sentence that pins evidence to a named commit goes stale the moment the next one lands, which is the defect these blocks exist to answer.
Evidence pinned to a state that later moves is the defect this branch fixed once already, so re-running is what these blocks cost rather than re-reading them.

Where this transcript lives is settled, and it is recorded here so a future reader does not re-derive it.
The maintainer verification the guards owe is the reproduce-catch-revert cycle above, and the pipeline that produced these fix rounds writes subject-only commits - `git log -1 --format=%b` returns nothing for every fix-round commit on this branch - so the literal "in the commit message" form cannot be produced from inside a run.
The current dated transcript therefore lives in this document, which is where the guidelines put maintainer verification, and it is carried into the pull request body, which is where a reviewer meets the change.
Commit `bd041d4` keeps its original transcript as dated evidence of what was true the day it shipped, superseded rather than broken, with the one line that changed named above.

```text
$ bin/fm-decision-hold.sh audit          # every decision properly held
(no output)

$ tasks-axi done samp-decision-route     # closed outside its owner
$ tasks-axi unhold samp-decision-shape
$ tasks-axi done samp-decision-shape     # unheld, then closed
$ tasks-axi unhold samp-decision-keep    # released, never closed

$ bin/fm-decision-hold.sh verify samp    # the old gate, at teardown only
fm-decision-hold: captain decision samp-decision-keep is neither actively held nor durably resolved
[exit 1]

$ bin/fm-bootstrap.sh | grep DECISION_HOLD
DECISION_HOLD: samp-decision-keep is open in a state fm-decision-hold cannot close (state=queued held=no hold_kind="-"), so no captain answer can be recorded on it while it stays there; the recovery for each open state is in docs/decision-hold-lifecycle.md under "Recovering an open decision hold"
DECISION_HOLD: samp-decision-route was closed outside fm-decision-hold with no captain decision recorded; attest the captain answer with: fm-decision-hold.sh repair samp route --decision-file <path>
DECISION_HOLD: samp-decision-shape was closed outside fm-decision-hold with no captain decision recorded; attest the captain answer with: fm-decision-hold.sh repair samp shape --decision-file <path>

$ bin/fm-decision-hold.sh hold samp route ...   # hold and verify agree
fm-decision-hold: captain decision samp-decision-route was closed outside fm-decision-hold with no captain decision recorded; attest the captain's answer with: fm-decision-hold.sh repair samp route --decision-file <path>
[exit 1]

$ bin/fm-decision-hold.sh repair samp route --decision-file a.txt
repaired: samp-decision-route
$ bin/fm-decision-hold.sh repair samp shape --decision-file b.txt
repaired: samp-decision-shape
$ bin/fm-decision-hold.sh hold samp keep ... && ... answer samp keep --decision-file c.txt
answered: samp-decision-keep

$ bin/fm-bootstrap.sh | grep DECISION_HOLD
(no output)
$ bin/fm-decision-hold.sh verify samp
verified: samp unresolved-decision inventory
```

The state that recipe was wrong for is `in_flight`, and this is the cycle that removed it, re-captured after the wording was corrected a second time.
`tasks-axi` accepts `start` on a held task and its own `ready` and `show` help advertise it, so one command takes a correctly held decision to `state=in_flight held=yes hold_kind=captain` while its routed work stays blocked.
That is the shape the block below uses, because it is the one that falsifies the most: the removed recipe applied the hold and then refused, and the wording that replaced it claimed the identity carried no active captain hold and blocked no work, both of which the fields printed beside them deny.
The verdict now claims only what is true of every open shape, and the recovery it points at is run verbatim at the foot of the block.
That recovery is a single `tasks-axi reopen`, recaptured after an earlier version of this document prescribed `tasks-axi done` before it.
The block records the routed task's `blocked:` field on both sides of the command, because closing the identity would have released that work for as long as it stayed closed, and closing a captain hold by hand is the incident this whole ledger was built to detect.

```text
$ tasks-axi start samp-decision-route        # accepted on a still-held decision
ok: start samp-decision-route -> In flight
$ tasks-axi show samp-decision-route --full | grep -E "state:|held:|hold_kind:"
  state: in_flight
  held: yes
  hold_kind: captain
$ tasks-axi show samp-route-work --full | grep -E "blocked:|blocked_by:"
  blocked: yes
  blocked_by: samp-decision-route

$ bin/fm-decision-hold.sh audit
samp-decision-route is open in a state fm-decision-hold cannot close (state=in_flight held=yes hold_kind=captain), so no captain answer can be recorded on it while it stays there; the recovery for each open state is in docs/decision-hold-lifecycle.md under "Recovering an open decision hold"
[exit 0]
$ bin/fm-decision-hold.sh audit             # again: same verdict, nothing changed
samp-decision-route is open in a state fm-decision-hold cannot close (state=in_flight held=yes hold_kind=captain), so no captain answer can be recorded on it while it stays there; the recovery for each open state is in docs/decision-hold-lifecycle.md under "Recovering an open decision hold"
$ bin/fm-decision-hold.sh verify samp
fm-decision-hold: captain decision samp-decision-route is neither actively held nor durably resolved
[exit 1]

$ bin/fm-decision-hold.sh hold samp route ...   # the wrong first move, and it mutates
fm-decision-hold: captain hold samp-decision-route is not queued (state=in_flight)
[exit 1]
$ tasks-axi show samp-decision-route --full | grep -E "held:|hold_kind:"
  held: yes
  hold_kind: captain

$ tasks-axi reopen samp-decision-route      # the recorded recovery, one command, no close
ok: reopen samp-decision-route -> Queued
$ tasks-axi show samp-decision-route --full | grep -E "state:|held:|hold_kind:"
  state: queued
  held: yes
  hold_kind: captain
$ tasks-axi show samp-route-work --full | grep "blocked:"
  blocked: yes
$ bin/fm-decision-hold.sh audit
(no output)
$ bin/fm-decision-hold.sh verify samp
verified: samp unresolved-decision inventory
```

The regression that pins the block above was itself proven the way this document requires a guard to be proven, and the proof is recorded because the previous version of that same test could not fail.
It was seeded with `state=in_flight held=no hold_kind="-"`, the shape its own fix had been written for, so its assertions about `held=yes` and `hold_kind=captain` asserted nothing.
The rebuilt test was therefore run against the verdict exactly as commit `7c2ccac` shipped it, before the current wording replaced it, and observed RED; the current code was then restored and it was observed green.
The suite stops at its first failing case and an earlier case matches the verdict's opening words, so the run below drives the one case in isolation, with the same fixtures the suite builds.

```text
# the verdict restored to the wording commit 7c2ccac shipped
$ bash tests/fm-decision-hold-lifecycle.test.sh   # driven to the one case
not ok - the open-state verdict denied the state it printed beside it (unexpected: 'carries no active captain hold')
--- output ---
sample-inflight-review-decision-route is open but carries no active captain hold (state=in_flight held=yes hold_kind=captain), so it is neither actively held nor durably resolved and therefore neither blocks work nor records an answer; the recovery for each open state is in docs/decision-hold-lifecycle.md under "Recovering an open decision hold"

# the verdict as it stands now
$ bash tests/fm-decision-hold-lifecycle.test.sh   # driven to the one case
ok - the audit's open-state verdict is true of every open shape, names no command, and changes nothing
```

The same cycle for the suggestion scope, on the nearest legitimate lookalike: the captain-gated thread `AGENTS.md` section 10 prescribes, whose id merely spells the decision separator.
Before this change `hold` answered the first command with `attest the captain's answer with: fm-decision-hold.sh repair capt ui-q2 --decision-file <path>`, and running that printed command returned `repaired: capt-decision-ui-q2` and replaced the thread's body with a resolution block no captain ever decided.

```text
$ tasks-axi add capt-decision-ui-q2 ... --kind captain --body "Some unrelated notes."
$ tasks-axi hold capt-decision-ui-q2 --reason "captain UI choice pending" --kind captain
$ tasks-axi done capt-decision-ui-q2

$ bin/fm-decision-hold.sh hold capt ui-q2 --title ... --reason ...
fm-decision-hold: backlog item capt-decision-ui-q2 is not an identity this ledger owns as a captain decision: this home records no reviewed decision under that key, and the record does not carry the creation body hold writes, so this command offers no remediation for it
[exit 1]
$ bin/fm-decision-hold.sh answer capt ui-q2 --decision-file d.txt
fm-decision-hold: backlog item capt-decision-ui-q2 is not an identity this ledger owns as a captain decision: this home records no reviewed decision under that key, and the record does not carry the creation body hold writes, so this command offers no remediation for it
[exit 1]
$ bin/fm-decision-hold.sh decline capt ui-q2 --decision-file d.txt
fm-decision-hold: backlog item capt-decision-ui-q2 is not an identity this ledger owns as a captain decision: this home records no reviewed decision under that key, and the record does not carry the creation body hold writes, so this command offers no remediation for it
[exit 1]
$ bin/fm-decision-hold.sh audit
(no output)

$ tasks-axi show capt-decision-ui-q2 --full | grep -E "body|Resolution"
  body: Some unrelated notes.
```

An identity can also drift off kind `captain` after the fact, and `repair` refuses on kind before it reads anything else, so every surface that would name `repair` asks that too and gives the audit's own sentence.
The second half below is the shape that makes a partial gate say something false rather than merely unhelpful: the decision really was answered through its owner, and its resolution record is still on the record.
That is also why the kind sentence names restoring the identity rather than giving the work a new one: the captain's answer is already recorded, and the last command below is the remediation the line printed, which is what silences it.

```text
$ bin/fm-decision-hold.sh answer samp route --decision-file a.txt   # answered through its owner
answered: samp-decision-route
$ tasks-axi update samp-decision-route --kind ship                 # moved off kind captain

$ tasks-axi show samp-decision-route --full | grep -c "Resolution recorded by fm-decision-hold."
1
$ bin/fm-decision-hold.sh audit
samp-decision-route carries a captain decision that was answered and recorded, and its kind drifted to ship, which is why verify and every close path refuse it; restore the identity with tasks-axi update samp-decision-route --kind captain rather than raising the decision again
$ bin/fm-decision-hold.sh hold samp route --title ... --reason ...
fm-decision-hold: samp-decision-route carries a captain decision that was answered and recorded, and its kind drifted to ship, which is why verify and every close path refuse it; restore the identity with tasks-axi update samp-decision-route --kind captain rather than raising the decision again
[exit 1]
$ bin/fm-decision-hold.sh answer samp route --decision-file a.txt
fm-decision-hold: samp-decision-route carries a captain decision that was answered and recorded, and its kind drifted to ship, which is why verify and every close path refuse it; restore the identity with tasks-axi update samp-decision-route --kind captain rather than raising the decision again
[exit 1]
$ bin/fm-decision-hold.sh decline samp route --decision-file a.txt
fm-decision-hold: samp-decision-route carries a captain decision that was answered and recorded, and its kind drifted to ship, which is why verify and every close path refuse it; restore the identity with tasks-axi update samp-decision-route --kind captain rather than raising the decision again
[exit 1]
$ bin/fm-decision-hold.sh repair samp route --decision-file a.txt
fm-decision-hold: backlog item samp-decision-route is not kind captain
[exit 1]

$ tasks-axi update samp-decision-route --kind captain              # the remediation the line named
$ bin/fm-decision-hold.sh audit
(no output)
$ bin/fm-decision-hold.sh verify samp
verified: samp unresolved-decision inventory
```

An identity can also lose both captain-hold signals, and then `repair` cannot attest it at all, so the remediation has to rebuild the identity rather than name a command.
It rebuilds the same one, because `complete` recorded that decision key in the origin's inventory and `verify` reads that inventory at teardown: the middle block below is the plausible wrong move, raising the decision again under a fresh key, which answers the captain's question and leaves the origin permanently unable to finish.
The last block of the first transcript is the remediation the line prints, run exactly as printed, on the unrouted branch it names.
The line branches at its last step because the identity is held again by the time a reader reaches it, and `answer` refuses a hold that still blocks routed work, so a second transcript follows for the routed branch.

```text
$ tasks-axi unhold samp-decision-route      # clears hold_kind
$ tasks-axi update samp-decision-route --body "Notes rewritten out of band."
$ tasks-axi done samp-decision-route        # both signals now gone

$ bin/fm-decision-hold.sh audit
samp-decision-route was closed outside fm-decision-hold and no longer carries captain-hold provenance, so repair cannot attest it as it stands; restore this same identity and record the captain answer on it with tasks-axi reopen samp-decision-route, then tasks-axi hold samp-decision-route --reason "<reason>" --kind captain, then fm-decision-hold.sh resolve samp route --decision-file <path> --routed-to <task-id> while that hold still blocks routed work, or fm-decision-hold.sh answer samp route --decision-file <path> once nothing is blocked by it; raising the decision again under a new key strands samp-decision-route in samp's reviewed inventory with nothing able to attest it, so that origin can never pass its completion gate
$ bin/fm-decision-hold.sh repair samp route --decision-file a.txt
fm-decision-hold: backlog item samp-decision-route was never held for the captain; repair records a captain decision only on a captain hold
[exit 1]

$ bin/fm-decision-hold.sh hold samp route-2 ... && ... answer samp route-2 --decision-file a.txt
answered: samp-decision-route-2
$ bin/fm-decision-hold.sh verify samp        # the new key changed nothing here
fm-decision-hold: captain decision samp-decision-route is neither actively held nor durably resolved
[exit 1]
$ bin/fm-decision-hold.sh audit
samp-decision-route was closed outside fm-decision-hold and no longer carries captain-hold provenance, so repair cannot attest it as it stands; restore this same identity and record the captain answer on it with tasks-axi reopen samp-decision-route, then tasks-axi hold samp-decision-route --reason "<reason>" --kind captain, then fm-decision-hold.sh resolve samp route --decision-file <path> --routed-to <task-id> while that hold still blocks routed work, or fm-decision-hold.sh answer samp route --decision-file <path> once nothing is blocked by it; raising the decision again under a new key strands samp-decision-route in samp's reviewed inventory with nothing able to attest it, so that origin can never pass its completion gate

$ tasks-axi reopen samp-decision-route                                              # the printed remediation
$ tasks-axi hold samp-decision-route --reason "captain route choice pending" --kind captain
$ bin/fm-decision-hold.sh answer samp route --decision-file a.txt
answered: samp-decision-route
$ bin/fm-decision-hold.sh audit
(no output)
$ bin/fm-decision-hold.sh verify samp
verified: samp unresolved-decision inventory
```

The routed branch of the same line, on an identity whose decision still blocks a dependent task.
The `answer` step is run first here and refuses, which is what the branch exists to answer: the same three-step recovery ends in `resolve` when routed work is still blocked, and the line names both because a reader cannot know which one they are in until they are standing there.

```text
$ tasks-axi block samp-route-work --by samp-decision-route     # the decision routes work
$ tasks-axi unhold samp-decision-route
$ tasks-axi update samp-decision-route --body "Notes rewritten out of band."
$ tasks-axi done samp-decision-route

$ bin/fm-decision-hold.sh audit
samp-decision-route was closed outside fm-decision-hold and no longer carries captain-hold provenance, so repair cannot attest it as it stands; restore this same identity and record the captain answer on it with tasks-axi reopen samp-decision-route, then tasks-axi hold samp-decision-route --reason "<reason>" --kind captain, then fm-decision-hold.sh resolve samp route --decision-file <path> --routed-to <task-id> while that hold still blocks routed work, or fm-decision-hold.sh answer samp route --decision-file <path> once nothing is blocked by it; raising the decision again under a new key strands samp-decision-route in samp's reviewed inventory with nothing able to attest it, so that origin can never pass its completion gate

$ tasks-axi reopen samp-decision-route                                              # the printed remediation
$ tasks-axi hold samp-decision-route --reason "captain route choice pending" --kind captain
$ bin/fm-decision-hold.sh answer samp route --decision-file a.txt                   # the branch that does not apply here
fm-decision-hold: captain hold samp-decision-route still blocks routed work (samp-route-work); use resolve to record that work
[exit 1]
$ bin/fm-decision-hold.sh resolve samp route --decision-file a.txt --routed-to samp-route-work
resolved: samp-decision-route -> samp-route-work
$ bin/fm-decision-hold.sh audit
(no output)
$ bin/fm-decision-hold.sh verify samp
verified: samp unresolved-decision inventory
```

The third failure of the original incident was retention, and this is the boundary it now draws.
A decision answered through its owner and then archived by ordinary retention is silent, which is what the removal of the absent-identity verdict bought; the same silence is what the coverage bound above admits costs a wrong close that is archived before any session start.
The `verify` path in the last command is rendered with `<home>` in place of the fixture's temporary directory and is otherwise verbatim.

```text
$ bin/fm-decision-hold.sh answer samp route --decision-file a.txt   # closed through its owner
answered: samp-decision-route
$ bin/fm-decision-hold.sh audit
(no output)

$ for i in 1..11; do tasks-axi add filler-$i ... && tasks-axi done filler-$i; done   # done_keep = 10
$ grep -c samp-decision-route data/backlog.md
0
$ grep -c "Resolution recorded by fm-decision-hold" data/done-archive.md
1

$ bin/fm-decision-hold.sh audit
(no output)
$ bin/fm-bootstrap.sh | grep DECISION_HOLD
(no output)
$ bin/fm-decision-hold.sh verify samp    # the gate is unchanged
fm-decision-hold: captain decision samp-decision-route is absent from <home>/data/backlog.md
[exit 1]
```

The verification commands and their exact summarized outputs follow.
This block is re-captured as the last edit of any change that touches this mechanism, after every other edit in that change is complete, because evidence captured mid-change is invalidated by the rest of the change - which has happened on this branch to a commit message, a transcript, a code comment, and this block itself.
A re-capture EXTENDS this record and never replaces it.

That rule is written here because it was broken on 2026-08-21 and this record was reduced without notice.
Commit `6350ed1` re-captured the decision-hold suite by rewriting the fenced block from its first command to the fence that closed it, which silently deleted every other command sharing that fence: the recorded runs of `tests/fm-fleet-snapshot-view.test.sh`, `tests/fm-bearings-snapshot.test.sh`, `tests/fm-send-resolve-key.test.sh`, `tests/fm-brief.test.sh` and `tests/fm-teardown.test.sh`, together with the `bin/fm-lint.sh`, `bin/fm-doc-audience-check.sh` and `git diff --check` evidence, which had no other home in the repository.
All of it is restored below by re-running each command against the code as it stands, never by pasting the deleted text, and one recorded line is now recorded as not reached rather than as passing.
The point of this record is that a reader can trust its extent, so a silent reduction is worth more here as a stated correction than as a quiet repair.

A reader re-verifies it without knowing which commit it was written against by running each command below from the repository root and comparing the output.
The per-suite counts say how many cases each run reported, so a truncated capture is visible as a smaller number rather than as a shorter list.

```text
$ bash tests/fm-decision-hold-lifecycle.test.sh
ok - report-only unresolved decision is reproduced and completion refuses before loss
ok - non-forced scout teardown always requires durable inventory verification
ok - a declined decision closes with a recorded answer and no routed work
ok - a decision closed outside the script is repairable and then clears teardown
ok - no refusal suggests repair for an ordinary captain-gated thread or for one repair would refuse, and every one still does for a real decision
ok - captain decisions closed outside their owner are named at session start and clear only when genuinely closed
ok - following the printed lost-provenance remediation clears the finding on both its branches
ok - a reviewed decision moved off kind captain is named at session start and clears when its kind is restored
ok - audit, hold, and repair give one verdict about an origin id that spells the decision separator
ok - decisions answered through their owner stay silent once retention archives them, while verify still refuses at teardown
ok - the session-start audit costs one backlog read whatever the number of healthy decisions
ok - an audit line never denies the state it prints beside it
ok - the audit's open-state verdict is true of every open shape, names no command, and changes nothing
ok - an unanswered decision still blocks completion and resists both unrouted close paths
ok - captain holds are idempotent, distinct, teardown-safe, Bearings-visible, and durably routed before close
ok - completion and verification validate origins before constructing paths
ok - ended visual review follows the same decision-hold completion owner
ok - resolved findings and decision-like prose do not create false holds
ok - terminal single-owner stale status decisions do not block empty inventory
ok - main-home and secondmate-home captain holds remain correctly routed
ok - resolve matches first/middle/last in quoted blocked_by and rejects a genuinely absent id
ok - a bound channel's captured answers close their captain holds at answer time
ok - a channel source with no decision binding closes nothing
ok - an any-origin bound source closes full-identity holds across origins
ok - the answer path keeps every guard the unrouted close path already had
ok - the chat channel feeds the same keyed-answer intake a captured review does

$ bash tests/fm-fleet-snapshot-view.test.sh
ok - backlog normalization preserves strict roles and resolves every blocker compatibly
ok - durable captain-held transfer closes the duplicate live status decision
ok - snapshot parses tasks-axi rows and respects operational overrides
(15 cases reported, all ok; the three above are the ones this mechanism owns)

$ bash tests/fm-bearings-snapshot.test.sh
ok - a completed scout with decision-like report prose is a pointer, not pending
ok - an authoritative captain hold surfaces end-to-end
ok - action-free items (working/done/queued/landed) do not leak into Captain's Call
ok - main and secondmate captain actionability use the same blocker readiness
(41 cases reported, all ok; the four above are the ones this mechanism owns)

$ bash tests/fm-send-resolve-key.test.sh
ok - fm-send --resolve-key: the answer send itself closes the open decision
ok - fm-send --resolve-key: a key that is not open refuses loudly before anything is sent
(13 cases reported, all ok; the status-log ledger's behavior is unchanged)

$ bash tests/fm-brief.test.sh
ok - fm-brief.sh: investigation and visual-review completions load the shared decision policy
(20 cases reported, all ok)

$ bash tests/fm-teardown.test.sh
ok - herdr teardown removes pane-owned escalation dedupe state
ok - herdr flat teardown refuses before returning the isolated copy under lock contention and the retry completes cleanly
ok - herdr flat teardown never erases records when pane presence is unparseable
not ok - herdr-preflight-missing-adapter: teardown continued without its required preflight
[exit 1]
(12 cases reported ok before the refusal above)

$ bin/fm-lint.sh
fm-lint.sh: ShellCheck 0.11.0 (pinned 0.11.0)
fm-lint-workflows.sh: actionlint 1.7.12 (pinned 1.7.12)
fm-lint-workflows.sh: 3 workflow files valid

$ bin/fm-doc-audience-check.sh
fm-doc-audience-check: ok surfaces=70 local_links=255

$ git diff --check
(no output)
```

The `fm-teardown` refusal above is the pre-existing herdr-preflight failure named in this change's delivery notes, and it is not this branch's.
That suite stops at the first failing case, so the line this record previously quoted from it - `ok - the run abort and the leaked-process reap both complete before the destructive worktree return` - is no longer reached, and it is recorded here as not reached rather than carried forward as passing.
This branch modifies none of the files that case exercises: `bin/fm-teardown.sh`, `tests/fm-teardown.test.sh` and the herdr libraries are all untouched between the base commit and this head, which `git diff --name-only` shows directly.
