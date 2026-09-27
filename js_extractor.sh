#!/usr/bin/env bash
# js_extractor.sh — JavaScript file endpoint extractor
# Usage: ./js_extractor.sh <url> [--crawl]
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'

usage() {
    echo "Usage: $0 <url> [options]"
    echo ""
    echo "Options:"
    echo "  (none)   Extract JS files from page and find endpoints"
    echo "  --crawl  Crawl JS links recursively"
    exit 1
}

[[ $# -lt 1 ]] && usage

URL="$1"
CRAWL="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOMAIN=$(echo "$URL" | sed 's|https\?://||;s|/.*||')
OUTDIR="${SCRIPT_DIR}/results/${DOMAIN}/js"
mkdir -p "$OUTDIR"
RESULT="${OUTDIR}/endpoints_$(date +%Y%m%d_%H%M%S).txt"
JSFILES="${OUTDIR}/js_files.txt"

echo -e "${BOLD}[*] JavaScript Endpoint Extraction: ${URL}${NC}"
echo ""

# ─── Step 1: Fetch page and extract JS references ────────────────────────────
echo -e "${BOLD}─── [1/4] Extracting JS file references ───${NC}"

PAGE_CONTENT=$(curl -s -L --max-time 15 "$URL" 2>/dev/null)
if [[ -z "$PAGE_CONTENT" ]]; then
    echo -e "${RED}[!] Failed to fetch page: ${URL}${NC}"
    exit 1
fi

# Extract JS file references from script tags and src attributes
echo "$PAGE_CONTENT" | \
    grep -oE 'src="[^"]*\.js[^"]*"' | \
    sed 's/src="//;s/"$//' | \
    sort -u > "$JSFILES" 2>/dev/null || true

# Also check for inline script sources
echo "$PAGE_CONTENT" | \
    grep -oE "'[^']*\.js[^']*'" | \
    sed "s/'//g" | \
    sort -u >> "$JSFILES" 2>/dev/null || true

# Convert relative URLs to absolute
JS_ABS="${OUTDIR}/js_absolute.txt"
while IFS= read -r jsurl; do
    if [[ "$jsurl" =~ ^// ]]; then
        echo "https:${jsurl}" >> "$JS_ABS"
    elif [[ "$jsurl" =~ ^/ ]]; then
        echo "https://${DOMAIN}${jsurl}" >> "$JS_ABS"
    elif [[ ! "$jsurl" =~ ^https?:// ]]; then
        echo "https://${DOMAIN}/${jsurl}" >> "$JS_ABS"
    else
        echo "$jsurl" >> "$JS_ABS"
    fi
done < "$JSFILES"

JS_COUNT=$(wc -l < "$JS_ABS" 2>/dev/null || echo 0)
echo -e "${GREEN}[✓] JS files found: ${JS_COUNT}${NC}"

if [[ "$JS_COUNT" -gt 0 ]]; then
    echo -e "${CYAN}[*] JS Files:${NC}"
    while IFS= read -r js; do
        echo -e "    ${CYAN}${js}${NC}"
    done < "$JS_ABS"
fi
echo ""

# ─── Step 2: Download and analyze JS files ────────────────────────────────────
echo -e "${BOLD}─── [2/4] Analyzing JS content ───${NC}"

ALL_ENDPOINTS="${OUTDIR}/raw_endpoints.txt"

while IFS= read -r jsurl; do
    [[ -z "$jsurl" ]] && continue
    echo -e "${CYAN}[*] Analyzing: ${jsurl}${NC}"

    JS_CONTENT=$(curl -s -L --max-time 10 "$jsurl" 2>/dev/null)
    [[ -z "$JS_CONTENT" ]] && continue

    # Extract URL-like patterns
    echo "$JS_CONTENT" | \
        grep -oE '(https?://[a-zA-Z0-9./?&=%_@:~-]+)' | \
        sort -u >> "$ALL_ENDPOINTS" 2>/dev/null || true

    # Extract path-like patterns
    echo "$JS_CONTENT" | \
        grep -oE '["'\''](/[a-zA-Z0-9._/-]+[a-zA-Z0-9/])["'\'']' | \
        tr -d "'\"" | \
        sort -u >> "$ALL_ENDPOINTS" 2>/dev/null || true

done < "$JS_ABS"

# ─── Step 3: Extract API-like endpoints ───────────────────────────────────────
echo -e "${BOLD}─── [3/4] Identifying API endpoints ───${NC}"

API_PATTERNS="${OUTDIR}/api_patterns.txt"
grep -iE '(/api/|/v[0-9]+/|graphql|/rest/|/endpoint|/query|/mutation|/action|/graphql|\.json|\.xml)' "$ALL_ENDPOINTS" 2>/dev/null | \
    sort -u > "$API_PATTERNS" || true

API_COUNT=$(wc -l < "$API_PATTERNS" 2>/dev/null || echo 0)
echo -e "${GREEN}[✓] API-like endpoints: ${API_COUNT}${NC}"

if [[ "$API_COUNT" -gt 0 ]]; then
    echo -e "${CYAN}[*] API Endpoints:${NC}"
    head -30 "$API_PATTERNS" | while IFS= read -r ep; do
        echo -e "    ${GREEN}${ep}${NC}"
    done
fi
echo ""

# ─── Step 4: Crawl JS links recursively ──────────────────────────────────────
if [[ "$CRAWL" == "--crawl" ]]; then
    echo -e "${BOLD}─── [4/4] Crawling JS links recursively ───${NC}"

    CRAWLED="${OUTDIR}/crawled_endpoints.txt"
    cp "$ALL_ENDPOINTS" "$CRAWLED" 2>/dev/null || true

    # Follow internal JS links
    while IFS= read -r endpoint; do
        if [[ "$endpoint" =~ ^https?://${DOMAIN}.*\.js ]]; then
            CRAWL_CONTENT=$(curl -s -L --max-time 10 "$endpoint" 2>/dev/null)
            [[ -z "$CRAWL_CONTENT" ]] && continue
            echo "$CRAWL_CONTENT" | \
                grep -oE '(https?://[a-zA-Z0-9./?&=%_@:~-]+)' | \
                sort -u >> "$CRAWLED" 2>/dev/null || true
        fi
    done < "$ALL_ENDPOINTS"

    sort -u "$CRAWLED" > "${CRAWLED}.tmp" && mv "${CRAWLED}.tmp" "$CRAWLED"
    CRAWL_COUNT=$(wc -l < "$CRAWLED" 2>/dev/null || echo 0)
    echo -e "${GREEN}[✓] Total crawled endpoints: ${CRAWL_COUNT}${NC}"
fi
echo ""

# ─── Final Output ────────────────────────────────────────────────────────────
echo -e "${BOLD}─── [4/4] Final Results ───${NC}"

sort -u "$ALL_ENDPOINTS" 2>/dev/null > "$RESULT" || true
TOTAL=$(wc -l < "$RESULT" 2>/dev/null || echo 0)

echo -e "${GREEN}[✓] Total unique endpoints: ${TOTAL}${NC}"
echo -e "${GREEN}    Results: ${RESULT}${NC}"
echo -e "${GREEN}    JS Files: ${JS_ABS}${NC}"
echo -e "${GREEN}    API Patterns: ${API_PATTERNS}${NC}"
