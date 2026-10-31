# apple-calendar-mcp

An MCP server that gives Claude access to the Calendar app on macOS — iCloud
calendars included — the way the Google Calendar connector does, but reading
the calendar database already on your Mac rather than a web API.

> **Status: work in progress. No installer yet.**
> The architecture, the permission model, all eight tools and the client
> policy work end to end, verified against real calendars. What is missing:
> an installer and notarisation, so installing today means building it
> yourself. Read [SECURITY.md](SECURITY.md) before you do — it says plainly
> what the client policy protects and what it does not.

## Tools

| Tool | |
|---|---|
| `check_access` | permission state, and what to do about it |
| `list_calendars` | every calendar, its identifier, whether it accepts changes |
| `list_events` | events in a range of up to ten years, recurrences expanded |
| `search_events` | text across title, location and notes, up to ten years |
| `find_free_slots` | openings of a given length inside working hours, up to a year |
| `create_event` | |
| `update_event` | only the fields you pass; one occurrence, it and the later ones, or the series — said explicitly |
| `delete_event` | one event — or one recurring series, when `span` says so — per call; requires `confirm: true` |

Every change is appended to `~/Library/Logs/apple-calendar-mcp-writes.log`.

Timestamps are ISO 8601 and parsed strictly: `2026-09-04T14:30:00+02:00`, the
same with `Z` or `+0200`, or without an offset — then in the Mac's time zone —
or a bare `2026-09-04` for midnight. Anything else is refused with a message
rather than read as something close: an impossible date, an hour skipped by a
daylight-saving change, a year outside 1900–2200. An empty or inverted range is
refused too, instead of answering "no events".

A recurring event is never addressed by default. Pass `occurrenceStart` with
`span` set to `thisEvent` or `futureEvents`, or `span: "series"` for every
occurrence; anything else is refused and nothing changes. `span: "series"`
takes no new start or end: given one date, the whole series moved there and
the occurrences before it vanished. Moving a series means addressing its first
occurrence with `futureEvents`, which the refusal names.

Event titles, locations, notes and attendee names are written by other people
and arrive unfiltered from invitations. Responses carrying them say so, and the
free-text fields are withheld unless a caller asks for `includeDetails`.

## Why this is not a plain stdio server

The obvious design — one binary that speaks MCP over stdio and calls EventKit —
**cannot work**, and fails in the worst possible way: silently.

macOS does not attribute a privacy request to the process that makes it. It
attributes it to the *responsible process* further up the launch chain. An MCP
server is spawned by its client, so the request is attributed to the client. If
that client's bundle does not declare `NSCalendarsFullAccessUsageDescription` —
and no MCP client does — the system refuses without showing a prompt, without
recording a decision, and without returning an error. `EKEventStore` simply
reports `notDetermined` forever.

Measured, not assumed:

| Binary | Launched by | Result |
|---|---|---|
| bare CLI, ad-hoc signed | MCP client | refused, nothing recorded |
| same, signed with a developer certificate | MCP client | refused |
| same, inside an `.app` | LaunchServices | **granted** |
| the granted `.app`'s own binary | MCP client spawning it directly | refused again |
| the granted `.app`'s own binary | Claude Desktop, through its `disclaimer` helper | **granted** |
| `.app` + LaunchAgent, `SMAppService` | launchd | **granted** |

The deciding variable is which process macOS holds responsible at spawn time —
not the code, not the signature, not the Info.plist.

The last-but-one row is the one that shapes the code. Claude Desktop starts its
MCP servers through a helper that makes each of them its own responsible
process, and any program can do the same. So the helper's executable, wherever
it is started from, holds the calendar grant in its own name. The only path in
it that reads or changes events is therefore the XPC service, which checks who
is asking; the command-line options touch no event, and `--selftest` reports
counts, never a calendar's name.

## Architecture

```
MCP client  ──stdio──▶  bridge  ──XPC──▶  helper.app + LaunchAgent  ──EventKit──▶  Calendar
                                                  │
                          checks the peer's signature, then its ancestry
```

The bridge forwards bytes and needs no privacy permission of its own. The helper
runs as a launch agent, so launchd is its parent and it holds the calendar
permission in its own name.

Splitting the process this way creates a local endpoint that holds a permission
— a confused deputy. The helper therefore checks both that the peer is signed by
its own team and that the processes above it are exactly Claude Desktop's:

```
bridge  <-  disclaimer  <-  Claude Desktop  <-  launchd
```

**Claude Desktop is the only client.** That is compiled into the helper, not a
setting; any other client is refused with a JSON-RPC error that says so.

That narrows the exposure; it does not close it. [SECURITY.md](SECURITY.md) sets
out what each check covers, and the four things none of them do.

## The setup window

Opening `AppleCalendarMCP.app` shows the two things that have to be true —
calendar access and the helper registered — each one a reading taken from the
system rather than a checkbox recording what was once done, so revoking a
permission in System Settings shows up here. It also says which client is
allowed, and prints the configuration line to paste into Claude Desktop.

Available in English and French, following the system language. The command
line, the logs and the MCP tool descriptions stay in English: tool descriptions
are read by models, and diagnostics end up in public issues.

## Requirements

- macOS 14.4 or later, set by the most demanding API used:
  `xpc_connection_set_peer_team_identity_requirement`, which lets the helper
  accept only its own bridge — the bridge's signing identifier, under the same
  team as the helper itself — so you can build and
  sign this with your own certificate, with no team identifier to edit
- Apple Silicon

## Building

```sh
Scripts/build-app.sh --sign "Your Developer ID"     # builds and installs to ~/Applications
"$HOME/Applications/AppleCalendarMCP.app/Contents/MacOS/apple-calendar-mcp" --register-agent
```

Then add the bridge to Claude Desktop's configuration,
`~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
"apple-calendar": {
  "command": "/Users/you/Applications/AppleCalendarMCP.app/Contents/MacOS/apple-calendar-mcp-bridge"
}
```

**Quit Claude Desktop before editing that file**, then start it again. It keeps
the configuration in memory and rewrites the whole file often: an entry added
while it runs was measured gone within seconds.

`--sign` takes a certificate name or its SHA-1 fingerprint. Use the fingerprint
once you hold two certificates with the same name — typically an old Developer
ID beside its replacement — or `codesign` refuses the name as ambiguous:

```sh
security find-identity -v -p codesigning     # the 40-character hash on each line
```

`swift build` alone produces the two executables but not the bundle, and the
helper cannot obtain calendar access outside one.

Three things the build script handles that are easy to get wrong by hand:

- **It stages in `/tmp`.** A checkout inside iCloud Drive — `~/Documents` and
  `~/Desktop` are synced by default — collects `com.apple.FinderInfo` and file
  provider attributes that `codesign` refuses, and that come straight back after
  `xattr -c`.
- **It signs the executables inside out.** Signing the bundle seals a second
  executable in `Contents/MacOS` as a nested resource *without re-signing it*,
  so the bridge keeps SwiftPM's ad-hoc signature and the helper then refuses it
  for having no team identifier. `codesign --verify --strict` passes anyway, so
  the script compares the team identifier of every executable instead.
- **It grants the calendar entitlement under the hardened runtime.**
  Notarisation requires the hardened runtime, and under it a process without
  `com.apple.security.personal-information.calendars` can ask for calendar
  access and simply never see a prompt. The window and the helper are signed
  with it; the bridge, which never touches EventKit, is not — and the script
  checks all three. Signing the bundle re-signs the window, so the entitlement
  has to be passed there too or it is silently dropped.

  This one is easy to miss for a reason worth knowing: a grant obtained
  earlier survives rebuilds signed with the same certificate, so an existing
  install keeps working without the entitlement. Only a fresh grant — a new
  machine, or a different certificate — exposes it.

## Development

launchd resolves the agent to the path the helper app had **when it was
registered**. Rebuilding into a different directory, or deleting the bundle
without unregistering first, leaves launchd pointing at a path that no longer
exists. It then refuses the job with `EX_CONFIG`, and the only visible symptom
is that the helper never answers — `launchctl print` will still show
the *new* bundle identifier while resolving the *old* path, so trust the
launchd log rather than the printed state.

Unregister before moving or rebuilding the bundle:

```sh
AppleCalendarMCP.app/Contents/MacOS/apple-calendar-mcp --unregister-agent
```

If a stale registration survives that, remove the job from the domain:

```sh
launchctl bootout gui/$UID/com.wilfrid.B.apple-calendar-mcp.agent
```

For the same reason, install the helper app at its final location before
registering it the first time.

A reinstall does not strand a running bridge. Unregistering invalidates its
connection for good, so the bridge opens a new one on the next message; while
the helper is away, each request is answered at once with error `-32002`
rather than left to time out. Requests are never resent: one the helper had
already carried out would be made twice.

### Tests

The unit tests cover the logic where a mistake is silent: timestamp parsing,
range limits, free-slot arithmetic, the `span` values and the tool catalogue.
They do not touch EventKit — that needs a granted helper and a test calendar.

```sh
swift test --scratch-path /tmp/apple-calendar-mcp-tests
```

The scratch path matters in a checkout inside iCloud Drive, for the reason the
build script stages in `/tmp`: the file provider marks the test bundle with
attributes `codesign` refuses, and `swift test` then fails to sign it.

### Changing the signing certificate

Moving to another certificate — from Apple Development to Developer ID, or to a
renewed Developer ID — has two consequences, both observed.

**The first launch can be refused.** After rebuilding with the new certificate
and registering again, launchd killed the helper on its first launch:

```
xpcproxy exited due to OS_REASON_CODESIGNING | Launch Constraint Violation (Constraint not matched)
removing service since it exited with consistent failure
```

The `EX_CONFIG` and `No such process` that follow are consequences of launchd
having removed the service, not the cause, so read the launchd log from the
first launch onwards:

```sh
log show --last 10m --predicate 'process == "launchd" AND eventMessage CONTAINS "apple-calendar-mcp"'
```

The binary itself is fine — it runs from a shell. What cleared it was a full
re-registration from the **new** binary:

```sh
AppleCalendarMCP.app/Contents/MacOS/apple-calendar-mcp --unregister-agent
launchctl bootout gui/$UID/com.wilfrid.B.apple-calendar-mcp.agent   # "No such process" just means nothing was left
AppleCalendarMCP.app/Contents/MacOS/apple-calendar-mcp --register-agent
```

Why the first registration inherited a constraint the new signature did not
meet has not been established. The background task record keeping the previous
signature is the likely explanation, not a proven one.

**The calendar permission has to be granted again.** macOS records the grant
against the signature, so a new certificate is a new client. Open the app and
grant access once more.

## Checking your machine

The architecture above depends on how macOS attributes calendar permission.
**Apple does not document this behaviour.** It is observed, not promised, and a
macOS update could change it — in which case access would stop being granted,
silently, exactly as described above.

So the first thing to run when anything goes wrong is:

```sh
apple-calendar-mcp --selftest
```

It reports the agent's authorization status — not the terminal's: it runs
itself again as its own responsible process, the way Claude Desktop starts MCP
servers, so macOS checks the grant this bundle holds. If that is not possible,
it says the status shown is the caller's and ends "INCOMPLETE" rather than
"FAILED". It also reports the process macOS sees, whether the
usage description is readable at runtime, whether the bridge beside it carries
the signing identifier the helper requires, and how many calendars of each kind
are actually visible — counts only, never their names, so the output is safe to
paste. It exits non-zero when any of that fails. Include its output in any bug
report. It never asks for access: that is done from the window.

## Prior art

[omarshahine/apple-pim](https://github.com/omarshahine/apple-pim) reached the
same conclusion about the responsible process independently, and got there
first. It covers more ground — Reminders, Contacts and Mail as well as Calendar
— ships through npm and a Claude plugin, and launches its helper app per call
with `open -W`, passing results back through files.

This project is narrower on purpose and spends the difference on the trust
boundary: one launch agent held open over XPC rather than a launch per call,
peers required to share the helper's team identifier, the client's exact
launch chain compiled in, and every write journalled.

Two things here are owed to it directly: that re-signing an unchanged bundle
drops the calendar grant, and that an ad-hoc signature is pinned by content
hash — so `Scripts/build-app.sh` leaves an unchanged install strictly alone and
refuses to sign ad-hoc over a certificate-signed one.

## Licence

MIT — see [LICENSE](LICENSE).
