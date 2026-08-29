# apple-calendar-mcp

An MCP server that gives Claude access to the Calendar app on macOS — iCloud
calendars included — the way the Google Calendar connector does, but reading
the calendar database already on your Mac rather than a web API.

> **Status: work in progress. Not usable yet.**
> The permission model and the process architecture are settled and verified.
> The calendar tools are not written. Nothing here is ready to install.

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

Splitting the process this way creates a local IPC endpoint that holds a
permission — a confused deputy. Both ends therefore validate each other, and the
scope of what the helper will do is limited by configuration. See
[SECURITY.md](SECURITY.md) once written.

## Requirements

- macOS 14 or later (`requestFullAccessToEvents` is macOS 14+)
- Apple Silicon

## Building

```sh
swift build
```

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
