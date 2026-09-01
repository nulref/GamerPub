# Gamer Pub Discord Activity

Gamer Pub uses one browser build for its Netlify website and Discord Activity.
The small outer shell owns the Discord Embedded App SDK and loads a
content-addressed Godot export in an iframe. A changed Godot package receives a
new URL, while unchanged large files can stay cached by browsers and Discord's
proxy.

## Architecture

- `activity/` contains the Vite shell and Discord SDK integration.
- `build/web/` is temporary staging for the Godot export.
- `dist/` is the final Netlify/Discord deployment; upload this directory only.
- Direct website visits retain Tenk's shared browser lobby and guest identity.
- Discord launches authenticate with OAuth, use the Discord display name, and
  isolate Joker and Tenk rooms by Activity instance.
- Joker and Tenk authoritative state runs in Gamer Pub's own
  `multiplayer/` Cloudflare Worker package.

## Values supplied by the Discord application owner

The source is ready for these public/private deployment values:

1. The Gamer Pub Discord **Application ID**, `1540543783626870804`, is set in
   `activity/.env.example`, the ignored local `activity/.env`, and
   `multiplayer/wrangler.jsonc`.
2. The Gamer Pub Discord **Client Secret**. Store it only with Wrangler as the
   Worker's `DISCORD_CLIENT_SECRET`; never put it in `.env`, source control, or
   chat.
3. A random Worker session signing value at least 32 characters long. Store it
   only as `ACCESS_SESSION_SECRET` with Wrangler.

Optional Cloudflare TURN credentials improve Tenk voice reliability on mobile
and restrictive networks. They are not required to launch the Activity.

## Local build

Create the public Activity environment file:

```powershell
Copy-Item activity/.env.example activity/.env
```

The tracked example already contains the public Application ID. Build
everything with Godot 4.7.1:

```powershell
.\scripts\export_web.ps1 -GodotPath "C:\path\to\Godot.exe"
```

The script exports Godot to `build/web`, injects Tenk's browser bridge, stages
the export under a content-derived path, builds the Activity shell, and writes
the final site to `dist/`.

For local Discord testing, run the Gamer Pub Worker on port 8787, run the Vite
shell, and expose Vite's port through `cloudflared`:

```powershell
Set-Location "C:\path\to\Gamer Pub\multiplayer"
npx wrangler dev

Set-Location "C:\path\to\Gamer Pub\activity"
npm run dev

cloudflared tunnel --url http://localhost:5173
```

The Vite development server proxies `/api` to the local Worker, so only the
Vite tunnel needs to be placed in Discord's temporary `/` URL mapping.

## Discord Developer Portal

1. Create a Discord application named **Gamer Pub**.
2. Under OAuth2, add `https://127.0.0.1` as a redirect URI for Embedded App SDK
   authorization.
3. Enable Activities and the Web platform. Enable iOS and Android when mobile
   testing is ready.
4. For local testing, map `/` to the temporary `trycloudflare.com` host without
   `https://`.
5. For production, map `/api` to the deployed `gamerpub-multiplayer` Worker
   host, then map `/` to `gamerpub.netlify.app`. Keep the more-specific `/api`
   mapping before `/`; targets omit the protocol.
6. Enable Developer Mode in Discord and launch Gamer Pub from the developer
   Activity shelf in a test channel.

Before public discovery, add reviewed Gamer Pub privacy-policy and terms URLs,
Activity artwork, description, participant limit, and supported-platform
metadata in the Developer Portal.

## Production order

1. Configure and deploy the Gamer Pub Worker.
2. Build `dist/` with the real public Application ID.
3. Upload `dist/` to Netlify once.
4. Set the production Discord URL mappings.
5. Test Joker, Tenk, voice, reconnects, and mobile layouts inside Discord.
