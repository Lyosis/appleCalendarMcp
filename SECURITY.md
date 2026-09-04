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

**The peer must be signed by the same team as the helper.**
`xpc_connection_set_peer_team_identity_requirement` — an attacker cannot write
their own client, and cannot patch the bridge, because either breaks the
signature the helper requires.

**The pinned client must be an ancestor of the peer.** The bridge is a public
binary; anyone can run it. So the helper also asks who started it, walking the
process chain and testing each ancestor against the pinned application's
designated requirement. Pin with:

```sh
apple-calendar-mcp --pin-client-auto      # run this from your MCP client
apple-calendar-mcp --show-pin
apple-calendar-mcp --unpin-client
```

The pin lives in the keychain, not in a file. A file under your home directory
is writable by anything running as you, so an attacker could replace the pin
with their own identity and walk in. A keychain item is bound to the code that
created it.

**Together**, these mean a local attacker has to run code inside a process tree
belonging to your pinned client. That is a real barrier. It is not a wall.

## What is not checked

**Prompt injection.** If a web page, an email or a document convinces the model
to read or change your calendar, every check above passes: the request really
does come from your client, through your bridge, under your pinned application.
No signature distinguishes "the model acting for you" from "the model acting on
text it just read".

Two things address that, and neither is a control:

- Event titles, locations, notes and attendee names are returned marked as
  content written by other people, with an explicit instruction not to act on
  them. Free-text fields are withheld unless a caller passes `includeDetails`.
- Every create, update and delete is appended to
  `~/Library/Logs/apple-calendar-mcp-writes.log`, with a timestamp, the
  calendar, and the event's identifier and title. That does not prevent misuse.
  It makes misuse visible afterwards.

**Nothing is pinned by default.** A fresh install accepts any client signed by
the same team as the helper, and says so on every connection in its log.
Refusing everything until someone finds the right incantation would produce a
puzzle rather than protection — but until you pin, the second check above is
simply not running.

**Ancestors are identified by process id.** An open XPC connection keeps the
direct peer alive, so its id cannot have been reused. Its ancestors can have
exited, and a reused id there would be a way to spoof the chain. Closing this
properly needs audit tokens, which the public XPC API does not expose for a
connection's ancestors.

**Deletion is limited, not prevented.** `delete_event` removes one event per
call and refuses without `confirm: true`. A caller that means harm can call it
repeatedly.

**The permission model rests on undocumented behaviour.** See the README: macOS
attributes a privacy request to the responsible process up the launch chain,
Apple documents this nowhere, and if it changes, access stops being granted
silently. Run `apple-calendar-mcp --selftest` when anything misbehaves.

## Reporting

Open an issue, or write to wilfrid_dev@proton.me for anything you would rather
not post publicly.
