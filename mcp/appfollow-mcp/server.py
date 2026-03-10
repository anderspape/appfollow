#!/usr/bin/env python3
from __future__ import annotations

import os
from collections import Counter
from datetime import date
from typing import Any

import httpx
from mcp.server.fastmcp import FastMCP

APPFOLLOW_BASE_URL = "https://api.appfollow.io/api/v2/reviews"
DEFAULT_EXT_ID = "1480220328"

mcp = FastMCP(
    name="appfollow-reviews-mcp",
    instructions="Fetch and summarize AppFollow app store reviews.",
    host=os.getenv("MCP_HOST", "0.0.0.0"),
    port=int(os.getenv("MCP_PORT", os.getenv("PORT", "8080"))),
    streamable_http_path="/mcp",
    stateless_http=True,
)


def _validate_iso_date(value: str, field_name: str) -> str:
    try:
        date.fromisoformat(value)
    except ValueError as exc:
        raise ValueError(f"{field_name} must be YYYY-MM-DD.") from exc
    return value


def _read_token() -> str:
    token = os.getenv("APPFOLLOW_API_TOKEN", "").strip()
    if not token:
        raise ValueError("Missing APPFOLLOW_API_TOKEN environment variable.")
    return token


def _fetch_page(
    *,
    token: str,
    ext_id: str,
    from_date: str,
    to_date: str,
    page: int,
) -> dict[str, Any]:
    params = {
        "ext_id": ext_id,
        "from": from_date,
        "to": to_date,
        "page": page,
    }
    headers = {"X-AppFollow-API-Token": token}

    with httpx.Client(timeout=30.0) as client:
        response = client.get(APPFOLLOW_BASE_URL, params=params, headers=headers)
        response.raise_for_status()
        payload = response.json()
    return payload


@mcp.tool()
def get_appfollow_reviews(
    from_date: str,
    to_date: str,
    ext_id: str = DEFAULT_EXT_ID,
    page: int = 1,
) -> dict[str, Any]:
    """
    Fetch one page of AppFollow reviews for an app ext_id and date range.
    """
    _validate_iso_date(from_date, "from_date")
    _validate_iso_date(to_date, "to_date")
    if page < 1:
        raise ValueError("page must be >= 1.")

    token = _read_token()
    payload = _fetch_page(
        token=token,
        ext_id=ext_id,
        from_date=from_date,
        to_date=to_date,
        page=page,
    )

    reviews = payload.get("reviews", {})
    return {
        "ext_id": reviews.get("ext_id"),
        "store": reviews.get("store"),
        "total_reviews": reviews.get("total"),
        "page": reviews.get("page"),
        "reviews": reviews.get("list", []),
    }


@mcp.tool()
def get_appfollow_reviews_summary(
    from_date: str,
    to_date: str,
    ext_id: str = DEFAULT_EXT_ID,
    max_pages: int = 20,
) -> dict[str, Any]:
    """
    Fetch reviews across pages and return a compact summary.
    """
    _validate_iso_date(from_date, "from_date")
    _validate_iso_date(to_date, "to_date")
    if max_pages < 1:
        raise ValueError("max_pages must be >= 1.")

    token = _read_token()
    first = _fetch_page(
        token=token,
        ext_id=ext_id,
        from_date=from_date,
        to_date=to_date,
        page=1,
    )

    reviews_obj = first.get("reviews", {})
    page_obj = reviews_obj.get("page", {}) or {}
    total_pages = int(page_obj.get("total", 1) or 1)
    pages_to_fetch = min(total_pages, max_pages)

    all_reviews = list(reviews_obj.get("list", []))
    for page in range(2, pages_to_fetch + 1):
        payload = _fetch_page(
            token=token,
            ext_id=ext_id,
            from_date=from_date,
            to_date=to_date,
            page=page,
        )
        all_reviews.extend(payload.get("reviews", {}).get("list", []))

    rating_counts = Counter(int(r.get("rating", 0) or 0) for r in all_reviews)
    country_counts = Counter((r.get("country") or "unknown") for r in all_reviews)

    return {
        "ext_id": reviews_obj.get("ext_id"),
        "store": reviews_obj.get("store"),
        "from_date": from_date,
        "to_date": to_date,
        "fetched_pages": pages_to_fetch,
        "available_pages": total_pages,
        "fetched_reviews": len(all_reviews),
        "total_reviews_reported": reviews_obj.get("total"),
        "ratings_breakdown": dict(sorted(rating_counts.items())),
        "top_countries": country_counts.most_common(10),
    }


if __name__ == "__main__":
    mcp.run(transport="streamable-http")
