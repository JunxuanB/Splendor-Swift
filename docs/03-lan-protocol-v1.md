# Luminore LAN protocol v1

The iOS host owns all lobby and game state. Clients submit commands and receive
recipient-specific snapshots. Future Internet and MultipeerConnectivity
adapters must preserve this contract; a Cloudflare service only relays frames.

## Transport

- Bonjour service: `_luminore._tcp`
- TCP payload: four-byte unsigned big-endian length followed by UTF-8 JSON
- Maximum JSON payload: 1 MiB
- `protocolVersion`: `1`
- Receivers ignore duplicate `messageID` values and non-increasing `sequence`
  values from the same sender.

The Bonjour TXT record contains only `id`, `name`, `host`, `count`, `max`,
`locked`, `stage`, and `pv`. Passwords and account UUIDs are never advertised.

## Authentication and reconnect

The host sends a random 16-byte salt and 32-byte nonce. The client derives a
SHA-256 key from the normalized password plus salt, then sends an HMAC-SHA256
of the nonce. A successful join returns an in-memory session token.

The `join` payload also carries an optional `deviceInstallID`: a local,
non-synced identifier of the joining device. Because the account UUID lives in
iCloud, two devices signed into one Apple ID share it; the install ID
distinguishes them. A player can reclaim a disconnected seat only when the UUID,
the session token, **and** the recorded device install all match. The field is
optional for protocol-v1 compatibility — when either side omits it, the host
falls back to UUID + token reclaim.

This handshake prevents clear-text password transmission but is not intended
to provide TLS-grade privacy or anti-cheat protection.

## Message envelope

Every JSON object contains `protocolVersion`, `messageID`, `roomID`,
`senderID`, `sequence`, and `payload`. Payload objects have a stable `type`
discriminator. Actions use the same pattern and are applied atomically.

See [`ios/ProtocolFixtures/action-take.json`](../ios/ProtocolFixtures/action-take.json)
for a versioned example. Codable definitions in `LuminoreCore` are the source
of truth.

## Compatibility

Unknown protocol versions are rejected. Adding optional fields is compatible;
renaming fields, changing semantics, or adding required fields requires a new
protocol version and matching fixtures.
