/// The single source of truth for the version.
///
/// `Resources/Info.plist` carries the same number for the bundle and
/// `Resources/BridgeInfo.plist` for the bridge. `VersionTests` fails when the
/// sources drift apart, `--selftest` when the installed bundle or bridge does
/// — a version that only looks right is how the wrong build gets shipped.
let serverVersion = "0.1.0"
