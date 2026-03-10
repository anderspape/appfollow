# MCP for Stilla: Tiimo AppFollow Reviews

This MCP server exposes AppFollow review tools over Streamable HTTP so it can be added in Stilla via URL.

## 1) Start the server

```bash
cd "/Users/andersskovpape/Documents/New project/mcp/stilla-appfollow"
APPFOLLOW_API_TOKEN="YOUR_APPFOLLOW_TOKEN" ./run.sh
```

Server URL:

- Local: `http://127.0.0.1:8080/mcp`
- Server-side/public: `https://<your-domain>/mcp`

## 2) Add in Stilla

Use the values below in the "Add MCP Server" form:

- Server Name: `Tiimo AppFollow Local`
- Server URL:
  - local testing: `http://127.0.0.1:8080/mcp`
  - server-side Stilla: `https://<your-domain>/mcp`
- Description: `Fetches and summarizes Tiimo AppFollow reviews`
- Custom request headers: none (token is read locally from env var when starting the server)

## 3) Available tools

- `get_appfollow_reviews(from_date, to_date, ext_id="1480220328", page=1)`
- `get_appfollow_reviews_summary(from_date, to_date, ext_id="1480220328", max_pages=20)`

Both date args must use `YYYY-MM-DD`.

## Notes

- Default `ext_id` is Tiimo iOS: `1480220328`.
- Keep the terminal running while Stilla uses the local MCP.
- If Stilla runs in another environment, use your machine IP instead of `127.0.0.1`.
- For server-side Stilla, deploy this MCP where Stilla can reach it over public HTTPS.
- This server binds to `0.0.0.0` by default. Override with:
  - `MCP_HOST` (default `0.0.0.0`)
  - `MCP_PORT` (default `8080`; falls back to `PORT` on hosting platforms)

## Public Deploy Option A (recommended): Render (Docker)

1. Push `mcp/stilla-appfollow` to a GitHub repo.
2. In Render, create a new `Web Service` from that repo.
3. Configure:
   - Runtime: `Docker`
   - Docker context: `mcp/stilla-appfollow`
   - Branch: your branch
4. Add environment variable:
   - `APPFOLLOW_API_TOKEN=...`
5. Deploy.
6. Use your Render service URL in Stilla:
   - `https://<render-service>.onrender.com/mcp`

## Public Deploy Option B (fast): Cloudflare Tunnel from your machine

If you just need quick access and accept that it runs from your laptop:

1. Start MCP server locally:
   ```bash
   cd "/Users/andersskovpape/Documents/New project/mcp/stilla-appfollow"
   APPFOLLOW_API_TOKEN="YOUR_APPFOLLOW_TOKEN" ./run.sh
   ```
2. In another terminal, start a temporary tunnel:
   ```bash
   cloudflared tunnel --url http://127.0.0.1:8080
   ```
3. Cloudflared prints a public HTTPS URL like:
   - `https://random-name.trycloudflare.com`
4. Add this URL in Stilla as:
   - `https://random-name.trycloudflare.com/mcp`

This URL changes every time you restart the tunnel.
