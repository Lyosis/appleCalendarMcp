/// The single source of truth for the version.
///
/// `Resources/Info.plist` carries the same number for the bundle, and
/// `--selftest` fails when the two drift apart — a version that only looks
/// right is how the wrong build gets shipped.
let serverVersion = "0.1.0"
