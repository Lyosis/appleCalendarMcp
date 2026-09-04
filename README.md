# apple-calendar-mcp

An MCP server that gives Claude access to the Calendar app on macOS — iCloud
calendars included — the way the Google Calendar connector does, but reading
the calendar database already on your Mac rather than a web API.

> **Status: work in progress. No installer yet.**
> The architecture, the permission model, all eight tools and the client
> pinning work end to end, verified against real calendars. What is missing:
> an installer and notarisation, so installing today means building it
> yourself. Read [SECURITY.md](SECURITY.md) before you do — it says plainly
> what the pinning protects and what it does not.

## Tools

| Tool | |
|---|---|
| `check_access` | permission state, and what to do about it |
| `list_calendars` | every calendar, its identifier, whether it accepts changes |
| `list_events` | events in a range, recurrences expanded |
| `search_events` | text across title, location and notes |
| `find_free_slots` | openings of a given length inside working hours |
| `create_event` | |
| `update_event` | only the fields you pass; one occurrence or the series |
| `delete_event` | one event per call, requires `confirm: true` |

Every change is appended to `~/Library/Logs/apple-calendar-mcp-writes.log`.

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
| the granted `.app`'s own binary | MCP client | refused again |
| `.app` + LaunchAgent, `SMAppService` | launchd | **granted** |

The deciding variable is which process macOS holds responsible at spawn time —
not the code, not the signature, not the Info.plist.

## Architecture

```
MCP client  ──stdio──▶  bridge  ──XPC──▶  helper.app + LaunchAgent  ──EventKit──▶  Calendar
                          │                       │
             checks its own ancestry     checks the peer's team identity
```

The bridge forwards bytes and needs no privacy permission of its own. The helper
runs as a launch agent, so launchd is its parent and it holds the calendar
permission in its own name.

Splitting the process this way creates a local endpoint that holds a permission
— a confused deputy. The helper therefore checks both that the peer is signed by
its own team and that the client you pinned is somewhere above it in the process
tree:

```sh
apple-calendar-mcp --pin-client-auto      # run this from your MCP client
```

That narrows the exposure; it does not close it. [SECURITY.md](SECURITY.md) sets
out what each check covers, and the four things none of them do.

## Requirements

- macOS 14.4 or later, set by the most demanding API used:
  `xpc_connection_set_peer_team_identity_requirement`, which lets the helper
  accept only peers signed by the same team as itself — so you can build and
  sign this with your own certificate, with no team identifier to edit
- Apple Silicon

## Building

```sh
Scripts/build-app.sh --sign "Your Developer ID"     # builds and installs to ~/Applications
"$HOME/Applications/AppleCalendarMCP.app/Contents/MacOS/apple-calendar-mcp" --register-agent
"$HOME/Applications/AppleCalendarMCP.app/Contents/MacOS/apple-calendar-mcp" --pin-client-auto
```

Then point your MCP client at
`~/Applications/AppleCalendarMCP.app/Contents/MacOS/apple-calendar-mcp-bridge`.

`swift build` alone produces the two executables but not the bundle, and the
helper cannot obtain calendar access outside one.

Two things the build script handles that are easy to get wrong by hand:

- **It stages in `/tmp`.** A checkout inside iCloud Drive — `~/Documents` and
  `~/Desktop` are synced by default — collects `com.apple.FinderInfo` and file
  provider attributes that `codesign` refuses, and that come straight back after
  `xattr -c`.
- **It signs the executables inside out.** Signing the bundle seals a second
  executable in `Contents/MacOS` as a nested resource *without re-signing it*,
  so the bridge keeps SwiftPM's ad-hoc signature and the helper then refuses it
  for having no team identifier. `codesign --verify --strict` passes anyway, so
  the script compares the team identifier of every executable instead.

## Development

launchd resolves the agent to the path the helper app had **when it was
registered**. Rebuilding into a different directory, or deleting the bundle
without unregistering first, leaves launchd pointing at a path that no longer
exists. It then refuses the job with `EX_CONFIG`, and the only visible symptom
is that the bridge never receives a reply — `launchctl print` will still show
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

## Checking your machine

The architecture above depends on how macOS attributes calendar permission.
**Apple does not document this behaviour.** It is observed, not promised, and a
macOS update could change it — in which case access would stop being granted,
silently, exactly as described above.

So the first thing to run when anything goes wrong is:

```sh
apple-calendar-mcp --selftest
```

It reports the real authorization status, the process macOS sees, whether the
usage description is readable at runtime, and which calendars are actually
visible. It exits non-zero when any of that fails. Include its output in any bug
report.

## Licence

MIT — see [LICENSE](LICENSE).
