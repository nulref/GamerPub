# Gamer Pub multiplayer room service

Cribbage has its own Durable Object room at `/cribbage` for the public browser table and `/api/cribbage` through the Discord Activity proxy. The room owns the host-selected mode and table size, exact-seat ready-up state, private hands, pegging, show scoring, and reconnect state.

This Cloudflare Worker uses one Durable Object for each Discord Activity
`instanceId`, one fixed Durable Object for the direct website's public lobby,
and one direct-site or per-Activity-instance Durable Object for TenK. It
provides the real-time lobby boundary for the Gamer Pub suite:

- host assignment and migration;
- player names and ready state;
- a host-only start command;
- bot-filled seats up to four players;
- free room activation for authenticated Discord participants;
- server-verified Discord identity and signed Activity sessions;
- reconnect-aware WebSocket sessions;
- ephemeral, server-routed WebRTC voice signaling for the public websites;
- a host-controlled Tenk lobby for 2–8 players with authoritative dice, scoring,
  turns, reconnect state, and optional voice without changing Joker's four-seat
  game lobby;
- per-participant Cloudflare TURN credentials when TURN secrets are configured;
- persisted room state with automatic cleanup after six idle hours.

## Endpoints

- `GET /health` returns deployment health.
- `POST /token` exchanges an Activity OAuth authorization code, verifies the
  Discord user, and returns the Discord access token plus a short-lived signed
  Activity session. Through the Discord URL mapping, clients call `/api/token`.
- `POST /entitlement` can reissue an authenticated player's signed Activity
  session if a future access model needs it.
- `GET /socket?instance_id=<discord-instance-id>` upgrades to a WebSocket.
  The Worker also accepts `/` because Discord strips a matched proxy prefix
  before forwarding it to the target.
- `GET /public` upgrades visitors from the configured public website origin to
  the singleton `public-web-lobby`. Its state is cleared when the final browser
  WebSocket disconnects.
- `GET /tenk?user_id=<browser-id>&name=<display-name>` upgrades visitors from
  `https://gamerpub.netlify.app` to the shared eight-person Tenk lobby, game,
  and voice room. `/voice/tenk` remains an alias so an older Gamer Pub bundle
  can still connect while deployments are being updated. The room clears when
  the final socket leaves.

Client messages are JSON objects with one of these shapes:

```json
{"type":"join","userId":"discord-user-id","name":"Player name","sessionToken":"signed-worker-session"}
{"type":"set_name","name":"New name"}
{"type":"set_ready","ready":true}
{"type":"start_game"}
{"type":"roll"}
{"type":"reroll","selectedIndices":[0,4]}
{"type":"keep","selectedIndices":[0,4]}
{"type":"next_player"}
{"type":"reset_game"}
{"type":"leave"}
{"type":"ping","sentAt":123}
{"type":"voice_join"}
{"type":"voice_signal","targetPeerId":"server-connection-id","signal":{"kind":"description","description":{"type":"offer","sdp":"..."}}}
{"type":"voice_leave"}
```

The service broadcasts `room_state` messages after each Tenk lobby change and
`game_state` after game actions. The Tenk Durable Object generates the dice and
accepts game commands only from the active player; only the host can start or
reset a game. Voice participants also receive a private `voice_config`, a shared
`voice_presence` list, and targeted `voice_signal` messages. The Durable Object
does not persist SDP, ICE candidates, or microphone audio. Signaling senders are
derived from the server-generated WebSocket connection ID instead of trusting a
client-supplied sender field.

## Development

```powershell
npm install
npm test
npm run check
npm run dev
```

Deploy with `npm run deploy`. The Gamer Pub Discord application maps `/api` to
the deployed Worker; Discord removes that prefix before `/token`, `/socket`,
and `/tenk` reach the service. TenK uses the signed Discord session and a
separate Durable Object for each Activity instance.

The Worker requires the Discord client secret and a random signing secret.
Store them with Wrangler's interactive prompt so they never enter source code:

```powershell
npx wrangler secret put DISCORD_CLIENT_SECRET
npx wrangler secret put ACCESS_SESSION_SECRET
```

Generate `ACCESS_SESSION_SECRET` from at least 32 random characters. The public
Application ID, free-hosting mode, and exact Netlify/Discord origins are in
`wrangler.jsonc`. No Discord bot token or SKU is needed while hosting remains
free. The entitlement implementation is retained so individual-game or
suite-wide purchases can be added later without replacing authenticated room
sessions.

### TURN relay for browser voice

Voice works peer-to-peer with Cloudflare's public STUN service when the
participants' networks permit a direct connection. Reliable cellular and
restricted-network support requires a Cloudflare Realtime TURN key. Create the
key in the Cloudflare dashboard, then store both generated values as encrypted
Worker secrets:

```powershell
npx wrangler secret put TURN_KEY_ID
npx wrangler secret put TURN_KEY_API_TOKEN
```

The Worker exchanges those long-lived server secrets for a separate 12-hour
credential whenever a player joins voice. Long-lived TURN secrets are never
sent to the browser. If either secret is absent or Cloudflare's credential API
is unavailable, the Worker returns STUN-only configuration and the client
clearly reports that no relay is configured.

## Security boundary

The Activity obtains its Discord user through OAuth. The Worker independently
loads that user and issues a short-lived HMAC-signed session bound to the
Discord user and Activity instance.
The Durable Object verifies that session before accepting a Discord lobby join,
so client-supplied identity and host-access flags are not trusted.

Direct-site visitors use a random ID stored in their browser. Those guest IDs
are not authenticated Discord identities; the dedicated public endpoints are
instead restricted to the configured website origins. Tenk caps the shared
lobby at eight players and validates host-only and active-player commands on the
server.

Voice signaling improves this boundary by taking the sender identity from the
socket attachment and allowing targets only among current voice participants of
the same kind in the same public Durable Object.
