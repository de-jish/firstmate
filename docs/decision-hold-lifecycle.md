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
It is a detector and not a gate: it prints one remediation per defect, always exits 0, and stays silent when tasks-axi cannot be read at all, because bootstrap already reports that on its own line.
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
So `hold`, `answer`, and `decline` reach one shared gate before they print a `repair` invocation, and no caller carries its own copy of a clause about a closed identity.
That gate asks `repair`'s own kind and provenance preconditions, so it never names a command `repair` would refuse, PLUS a suggestion-scope rule `repair` deliberately does not have.
It therefore answers a narrower question than `repair` does - should this identity be handed a repair command, not would `repair` accept it - and the reasoning for keeping that asymmetry lives beside the gate in `bin/fm-decision-hold.sh`, because that is where someone would be tempted to tidy it away.
An identity the scope rule declines is refused with a text that states only what the rule tested, and never asserts what `repair` would do with it, because `repair` reads a wider signal and may well accept it.
An identity that fails any of them is refused with a shared text that names no mutating command, and the kind refusal is the audit's own sentence verbatim, so one identity gets one verdict whichever surface a reader meets first.
The refusals themselves are unchanged at every site; only the remediation a lookalike is handed changed.

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
Out-of-scope refusal wording and hold routing verification date: 2026-08-20.

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
It reproduces all three with the exact commands that caused them - a direct `tasks-axi done`, an `unhold` followed by `done`, and a bare `unhold` - and proves the completion gate refuses, the audit names each defect with the remediation that actually clears it, and the same findings reach a session start as `DECISION_HOLD:` lines.
It proves `hold` and `verify` now give one verdict about one identity, that an ordinary captain-gated thread whose id merely spells the decision separator never enters the report whether it was held for the captain first or never held at all, and that the report empties only as each decision is closed with the captain's word and not before.
The unheld close is attested by `repair` rather than left permanently unattestable, while a closed captain-kind task the script never created is still refused.
A companion regression drives one origin id that spells the decision separator itself through the whole cycle and proves `audit`, `hold`, and `repair` reach a single verdict about that identity, so the report's own printed remediation always acts on the decision the report named.
Two further regressions pin what makes the detector survivable in daily use.
The cost case records every `tasks-axi` invocation the session-start audit makes and proves the count does not change when the home grows from two properly held decisions to six, while a decision closed outside its owner is still named and still re-read from its own record.
The message case releases a hold and re-holds it for something other than the captain, and proves the printed line never denies the state printed beside it, names the `hold_kind` that makes it a defect, and clears only when the remediation it prints is actually run.

A fourth drives an ordinary captain-gated thread through `hold`, `answer`, and `decline`, proves none of them names a `repair` invocation for it and that its body survives every refusal untouched, and proves all three still name the remediation for a decision this script really created.
A fifth answers three decisions through their owner, drives real retention by closing eleven unrelated tasks until `.tasks.toml`'s `done_keep` moves them into the archive, and proves the audit and the session start both stay silent about them while `verify` still refuses the absent identity at that origin's teardown.
The fourth also covers both ways an identity drifts off kind `captain` - closed out of band and then moved, and answered through its owner and then moved - and proves `hold`, `answer`, and `decline` name no `repair` command for either, give the audit's own sentence, and never claim a recorded decision is unrecorded.
It closes with the identity the scope rule declines but `repair` accepts, and proves the refusal states only what the rule tested while `repair` still attests it, so no surface asserts something a reader can disprove in one command.
A sixth moves a reviewed decision off kind `captain` with `tasks-axi update`, and proves the audit and the session start both name it and that the finding clears when the kind is restored.
That case is the one regression that fails if a `--kind captain` filter is ever restored to the audit's listing, which is the only way that detection could be deleted while every other regression stayed green.

### Reproduce, catch, revert, as of 2026-08-20

The transcript recorded in commit `bd041d4` is superseded, not broken.
It is accurate evidence of what the guard emitted the day it shipped, and one of its lines no longer reproduces because the message was corrected afterwards: the released-hold finding read `is open but no longer actively held (state=queued held=no)`, which denied the state it printed whenever the identity had been re-held for something other than the captain, and it now reads `is open but carries no active captain hold (state=queued held=no hold_kind="-")`.
Every block below was captured by running the commands against the shipped code, and every command in every block was re-run against the code as it stands after the last behavioural change on this branch, which removed the audit's absent-identity verdict.
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
DECISION_HOLD: samp-decision-keep is open but carries no active captain hold (state=queued held=no hold_kind="-"), so it neither blocks work nor records an answer; re-activate it with fm-decision-hold.sh hold before closing it with the captain word
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

The same cycle for the suggestion scope, on the nearest legitimate lookalike: the captain-gated thread `AGENTS.md` section 10 prescribes, whose id merely spells the decision separator.
Before this change `hold` answered the first command with `attest the captain's answer with: fm-decision-hold.sh repair capt ui-q2 --decision-file <path>`, and running that printed command returned `repaired: capt-decision-ui-q2` and replaced the thread's body with a resolution block no captain ever decided.

```text
$ tasks-axi add capt-decision-ui-q2 ... --kind captain --body "Some unrelated notes."
$ tasks-axi hold capt-decision-ui-q2 --reason "captain UI choice pending" --kind captain
$ tasks-axi done capt-decision-ui-q2

$ bin/fm-decision-hold.sh hold capt ui-q2 --title ... --reason ...
fm-decision-hold: backlog item capt-decision-ui-q2 is not an identity this ledger owns as a captain decision: this home records no reviewed decision under that key, and the record no longer carries the creation body hold writes, so this command offers no remediation for it
[exit 1]
$ bin/fm-decision-hold.sh answer capt ui-q2 --decision-file d.txt
fm-decision-hold: backlog item capt-decision-ui-q2 is not an identity this ledger owns as a captain decision: this home records no reviewed decision under that key, and the record no longer carries the creation body hold writes, so this command offers no remediation for it
[exit 1]
$ bin/fm-decision-hold.sh decline capt ui-q2 --decision-file d.txt
fm-decision-hold: backlog item capt-decision-ui-q2 is not an identity this ledger owns as a captain decision: this home records no reviewed decision under that key, and the record no longer carries the creation body hold writes, so this command offers no remediation for it
[exit 1]
$ bin/fm-decision-hold.sh audit
(no output)

$ tasks-axi show capt-decision-ui-q2 --full | grep -E "body|Resolution"
  body: Some unrelated notes.
```

An identity can also drift off kind `captain` after the fact, and `repair` refuses on kind before it reads anything else, so every surface that would name `repair` asks that too and gives the audit's own sentence.
The second half below is the shape that makes a partial gate say something false rather than merely unhelpful: the decision really was answered through its owner, and its resolution record is still on the record.

```text
$ bin/fm-decision-hold.sh answer samp route --decision-file a.txt   # answered through its owner
answered: samp-decision-route
$ tasks-axi update samp-decision-route --kind ship                 # moved off kind captain

$ tasks-axi show samp-decision-route --full | grep -c "Resolution recorded by fm-decision-hold."
1
$ bin/fm-decision-hold.sh audit
samp-decision-route carries a reviewed captain decision identity but is kind ship, so it cannot hold a captain decision; give that work its own identity
$ bin/fm-decision-hold.sh hold samp route --title ... --reason ...
fm-decision-hold: samp-decision-route carries a reviewed captain decision identity but is kind ship, so it cannot hold a captain decision; give that work its own identity
[exit 1]
$ bin/fm-decision-hold.sh answer samp route --decision-file a.txt
fm-decision-hold: samp-decision-route carries a reviewed captain decision identity but is kind ship, so it cannot hold a captain decision; give that work its own identity
[exit 1]
$ bin/fm-decision-hold.sh decline samp route --decision-file a.txt
fm-decision-hold: samp-decision-route carries a reviewed captain decision identity but is kind ship, so it cannot hold a captain decision; give that work its own identity
[exit 1]
$ bin/fm-decision-hold.sh repair samp route --decision-file a.txt
fm-decision-hold: backlog item samp-decision-route is not kind captain
[exit 1]

$ tasks-axi update samp-decision-route --kind captain              # revert
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
A reader re-verifies it without knowing which commit it was written against by running `bash tests/fm-decision-hold-lifecycle.test.sh` from the repository root and comparing the `ok -` lines below.

```text
$ bash tests/fm-decision-hold-lifecycle.test.sh
ok - report-only unresolved decision is reproduced and completion refuses before loss
ok - non-forced scout teardown always requires durable inventory verification
ok - a declined decision closes with a recorded answer and no routed work
ok - a decision closed outside the script is repairable and then clears teardown
ok - no refusal suggests repair for an ordinary captain-gated thread or for one repair would refuse, and every one still does for a real decision
ok - captain decisions closed outside their owner are named at session start and clear only when genuinely closed
ok - a reviewed decision moved off kind captain is named at session start and clears when its kind is restored
ok - audit, hold, and repair give one verdict about an origin id that spells the decision separator
ok - decisions answered through their owner stay silent once retention archives them, while verify still refuses at teardown
ok - the session-start audit costs one backlog read whatever the number of healthy decisions
ok - an audit line never denies the state it prints beside it
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

$ bash tests/fm-bearings-snapshot.test.sh
ok - a completed scout with decision-like report prose is a pointer, not pending
ok - an authoritative captain hold surfaces end-to-end
ok - action-free items (working/done/queued/landed) do not leak into Captain's Call
ok - main and secondmate captain actionability use the same blocker readiness

$ bash tests/fm-send-resolve-key.test.sh
ok - fm-send --resolve-key: the answer send itself closes the open decision
ok - fm-send --resolve-key: a key that is not open refuses loudly before anything is sent
(13 assertions total; the status-log ledger's behavior is unchanged)

$ bash tests/fm-brief.test.sh
ok - fm-brief.sh: investigation and visual-review completions load the shared decision policy

$ bash tests/fm-teardown.test.sh
ok - the run abort and the leaked-process reap both complete before the destructive worktree return

$ bin/fm-lint.sh
fm-lint.sh: ShellCheck 0.11.0 (pinned 0.11.0)

$ bin/fm-doc-audience-check.sh
fm-doc-audience-check: ok surfaces=70 local_links=255

$ git diff --check
(no output)
```
