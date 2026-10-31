# Security

Installing this gives a background process on your Mac permanent read and write
access to your calendar. This document says what protects that access, and —
more usefully — what does not.

## The shape of the problem

macOS grants calendar access per application. A program you download has none,
and asking for it puts a prompt in front of you.

The helper here holds that grant permanently, and acts on behalf of whatever
asks it to. That makes it a *confused deputy*: the guard has the key and opens
the door for whoever knocks. Anything able to reach the helper inherits calendar
access without a prompt and without leaving a trace in the system's own records.

This is inherent to any MCP server holding a system permission. It is not
peculiar to this project, and it is not solved here. It is narrowed.

## What is checked

**Events are reached only through the XPC service.** The helper's executable
holds the calendar grant in its own name, wherever it is started from: Claude
Desktop launches its MCP servers through a helper that makes each one its own
responsible process for privacy purposes, and any program can do the same. So
nothing in that executable other than the XPC service reads or changes events.
Its command-line options touch no event, and `--selftest` prints counts, never
a calendar's name. A copy started outside launchd cannot take over the service
either: it is refused the Mach name, and exits.

**The peer must be the bridge.**
`xpc_connection_set_peer_team_identity_requirement`, given the bridge's signing
identifier: the peer must be signed by the same team as the helper *and* under
that identifier, checked on every message. An attacker cannot write their own
client, and cannot patch the bridge, because either breaks the signature the
helper requires — and another program signed by the same team is refused too.

**The bridge must have been started by Claude Desktop — exactly.** The bridge
is a public binary; anyone can run it. So the helper walks the processes above
the peer and requires precisely this chain, nothing in between and nothing
above:

```
bridge  <-  disclaimer  <-  Claude Desktop  <-  launchd
```

`disclaimer` is the helper Claude Desktop starts its MCP servers through. Each
of the two is checked against its publisher's designated requirement — its
signing identifier under Anthropic's team, `Q6L2SF6YDW` — so updates to Claude
Desktop keep matching. Sessions of Claude Code inside the app are covered too:
the app itself starts the servers declared in its configuration (measured).

Exactly, because "somewhere above" was measured to be too weak: a shell started
by a Claude Code session has Claude Desktop above it as well, so any command run
from there — including one a model was talked into — reached the calendar.

**`disclaimer` must have been told to run the bridge.** A process keeps its id
and its parent when it replaces itself with another program. So any MCP server
Claude Desktop starts could turn itself into the bridge, with its input and
output wired to a process of its own, and sit in exactly the chain above —
measured: it got full access, while the same server starting the bridge as a
child was refused. What `disclaimer` was told to run is kept by the kernel and
does not change when its child replaces itself, so the helper reads it
(`KERN_PROCARGS2`) and requires that the program after `--` is, links
resolved, the one the peer is running. A server declared with the bridge's own
path gets a real bridge, wired to Claude Desktop, and nothing more.

**The policy is compiled in.** Earlier versions pinned a client in the
keychain. Any process running as you could delete that item without a prompt,
and an empty pin accepted everyone. There is now nothing to delete and nothing
to set: changing who is allowed means shipping another signed build. It lives
in `Sources/AppleCalendarMCP/ClientPolicy.swift`.

**Process ids are checked against start times.** The ancestors are found by
process id, and an ancestor can have exited and its id been reused. A parent
cannot have started after its child, so an id that reads otherwise is refused;
the start time is read again after the signature check, so the process that
passed is the one that was measured.

**A refused client is told so.** Every request on a refused connection gets a
JSON-RPC error (`-32001`) saying that only Claude Desktop is accepted. Which
process was where goes to the log, not to the model:

```sh
log show --last 10m --predicate 'subsystem == "com.wilfrid.B.apple-calendar-mcp"'
```

**Together**, these mean a local attacker has to run code inside Claude
Desktop's own process — not merely be one of the MCP servers it starts, which
the previous version of this paragraph overlooked and a test disproved. That
is a real barrier. It is not a wall.

## What is not checked

**Prompt injection.** If a web page, an email or a document convinces the model
to read or change your calendar, every check above passes: the request really
does come from Claude Desktop, through your bridge.
No signature distinguishes "the model acting for you" from "the model acting on
text it just read".

Two things address that, and neither is a control:

- Event titles, locations, notes and attendee names are returned marked as
  content written by other people, with an explicit instruction not to act on
  them. Free-text fields are withheld unless a caller passes `includeDetails`.
- Every create, update and delete is appended to
  `~/Library/Logs/apple-calendar-mcp-writes.log`, with a timestamp, the span,
  and for each event its identifier, title, times, calendar and how it
  repeats. An update records the event as it was and as it is, so a change
  can be put back by hand, and when it splits a series, the part left behind
  with its new end; location, notes and url are not logged, only named when
  they change. A deletion lists everything that went: deleting a series
  also removes the parts EventKit split off it earlier, under other
  identifiers, so the helper compares the calendar before and after rather
  than record only the event addressed. That comparison covers five years
  ahead, and the line says so; a part starting later goes unlisted, and
  anything iCloud removes in the same instant would be listed too. A change
  is refused when the journal cannot be opened for writing. If appending
  fails after the change was made — a disk filling up in between — the change
  stands and the tool's result says it went unrecorded. None of this prevents
  misuse. It makes misuse visible afterwards.

**Only Claude Desktop.** Claude Code run from a terminal, a bridge declared in
Claude Code's own configuration, and every other MCP client are refused.
Supporting one means measuring the chain it starts the bridge with and adding
it to the policy — not a setting.

**The policy rests on how Claude Desktop works today.** It was measured with
Claude Desktop 3.6556.2, and again with 4.29.0. If Anthropic renames
`disclaimer`, puts another process in the chain, signs under another team or
starts servers other than as `disclaimer … -- <program>`, every connection is
refused — loudly, with the error above, not silently. `apple-calendar-mcp --selftest`
checks the installed Claude Desktop against the policy, so a signing change
shows up there first.

**Start times narrow process id reuse; they are not audit tokens.** The check
runs once, when the connection opens; after that the open XPC connection pins
the peer. Audit tokens would identify the ancestors beyond doubt, but the
public XPC API does not expose them for a connection's ancestors.

**Deletion is limited, not prevented.** `delete_event` refuses without
`confirm: true` and removes one event per call — or one whole recurring series,
when the caller passes `span: "series"`, which a caller that means harm can do
as easily as anything else. It can also call it repeatedly. `confirm` and
`span` guard against mistakes, not against intent: the model sets both.

**The permission model rests on undocumented behaviour.** See the README: macOS
attributes a privacy request to the responsible process up the launch chain,
Apple documents this nowhere, and if it changes, access stops being granted
silently. Run `apple-calendar-mcp --selftest` when anything misbehaves.

**The selftest relies on a private call.** To measure the agent's permission
rather than the terminal's, `--selftest` starts itself again with
`responsibility_spawnattrs_setdisclaim`, which is in no public header — Claude's
own `disclaimer` uses it. It is looked up at run time: without it the selftest
reports the caller's status as such and ends incomplete. Being disclaimed gives
it nothing that any process cannot already get, as main.swift explains, and it
still prints counts only and never asks for access. Its "permission measured
for" line trusts that the call succeeded; it cannot ask macOS whom it holds
responsible.

## Reporting

Open an issue, or write to wilfrid_dev@proton.me for anything you would rather
not post publicly.
