# AppFollow Reviews MCP Server

This package exposes AppFollow review tools over Streamable HTTP.

## Run locally

```bash
cd "/Users/andersskovpape/Documents/New project/mcp"
APPFOLLOW_API_TOKEN="YOUR_APPFOLLOW_TOKEN" ./run.sh
```

Endpoint:

- `http://127.0.0.1:8080/mcp`

## Tools

- `get_appfollow_reviews(from_date, to_date, ext_id="1480220328", page=1)`
- `get_appfollow_reviews_summary(from_date, to_date, ext_id="1480220328", max_pages=20)`
- `get_appfollow_ratings_history(from_date, to_date, ext_id="1480220328", collection_name="my-first-workspace", country=None, store="as", version=None, period="daily", score_type="total", offset=0, limit=100, extra_query=None)`

`extra_query` lets you pass raw URL params like:
- `"sort=asc&timezone=UTC"`

Both date args must be `YYYY-MM-DD`.

## Environment variables

- `APPFOLLOW_API_TOKEN` (required)
- `MCP_HOST` (optional, default `0.0.0.0`)
- `MCP_PORT` (optional, default `8080`; falls back to `PORT`)

## Deploy with Docker

1. Use folder `mcp` as Docker build context.
2. Set env var `APPFOLLOW_API_TOKEN`.
3. Expose port `8080` (or set `PORT` via host platform).
4. Use public endpoint:
   - `https://<your-domain>/mcp`
