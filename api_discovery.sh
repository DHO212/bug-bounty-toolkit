#!/usr/bin/env bash
# api_discovery.sh — API endpoint discovery from JavaScript source files
# Usage: ./api_discovery.sh <url> [--depth N]
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'

usage() {
    echo "Usage: $0 <url> [options]"
    echo ""
    echo "Options:"
    echo "  --depth N   Crawl depth (default: 1)"
    exit 1
}

[[ $# -lt 1 ]] && usage

URL="$1"
DEPTH=1
shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --depth) DEPTH="$2"; shift 2 ;;
        *) shift ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOMAIN=$(echo "$URL" | sed 's|https\?://||;s|/.*||')
OUTDIR="${SCRIPT_DIR}/results/${DOMAIN}/api"
mkdir -p "$OUTDIR"
RESULT="${OUTDIR}/api_endpoints_$(date +%Y%m%d_%H%M%S).txt"

echo -e "${BOLD}[*] API Endpoint Discovery: ${URL}${NC}"
echo -e "${CYAN}[*] Crawl depth: ${DEPTH}${NC}"
echo ""

# ─── Fetch main page ──────────────────────────────────────────────────────────
echo -e "${BOLD}─── [1/4] Fetching page content ───${NC}"
PAGE=$(curl -s -L --max-time 15 "$URL" 2>/dev/null)
if [[ -z "$PAGE" ]]; then
    echo -e "${RED}[!] Failed to fetch: ${URL}${NC}"
    exit 1
fi

# ─── Extract JS files ────────────────────────────────────────────────────────
echo -e "${BOLD}─── [2/4] Discovering JS sources ───${NC}"

JS_URLS=$(echo "$PAGE" | \
    grep -oE 'src="[^"]*\.js[^"]*"' | \
    sed 's/src="//;s/"$//' | \
    sed "s|^//|https://|;s|^/|https://${DOMAIN}/|;s|^[^h]|https://${DOMAIN}/&|" | \
    sort -u)

JS_COUNT=$(echo "$JS_URLS" | grep -c '.' 2>/dev/null || echo 0)
echo -e "${GREEN}[✓] JS sources: ${JS_COUNT}${NC}"

# Also find JS from link preload/modulepreload
LINK_JS=$(echo "$PAGE" | \
    grep -oE 'href="[^"]*\.js[^"]*"' | \
    sed 's/href="//;s/"$//' | \
    sed "s|^//|https://|;s|^/|https://${DOMAIN}/|;s|^[^h]|https://${DOMAIN}/&|" | \
    sort -u)

ALL_JS=$(echo -e "${JS_URLS}\n${LINK_JS}" | sort -u | grep -v '^$')
echo ""

# ─── Analyze each JS file ────────────────────────────────────────────────────
echo -e "${BOLD}─── [3/4] Analyzing JS for API patterns ───${NC}"

TEMP_ENDPOINTS="${OUTDIR}/.temp_endpoints.txt"
> "$TEMP_ENDPOINTS"

while IFS= read -r jsurl; do
    [[ -z "$jsurl" ]] && continue
    echo -e "${CYAN}[*] Analyzing: ${jsurl}${NC}"

    JSCONTENT=$(curl -s -L --max-time 10 "$jsurl" 2>/dev/null)
    [[ -z "$JSCONTENT" ]] && continue

    # 1. API base URLs and endpoints
    echo "$JSCONTENT" | \
        grep -oE '["'\''`][a-zA-Z0-9/._-]*(api|v[0-9]|graphql|rest|query|mutation|endpoint|search|auth|login|register|user|admin|upload|download|config|settings)[a-zA-Z0-9/._?&=%-]*["'\''`]' | \
        tr -d "'\"\`" | \
        sort -u >> "$TEMP_ENDPOINTS" 2>/dev/null || true

    # 2. fetch/axios/xhr patterns
    echo "$JSCONTENT" | \
        grep -oE '(fetch|axios|\.get|\.post|\.put|\.delete|\.patch|\.request|XMLHttpRequest|ajax)\s*\(\s*["'\''`][^"'\'']*["'\''`]' | \
        grep -oE '["'\''`][^"'\'']*["'\''`]' | \
        tr -d "'\"\`" | \
        sort -u >> "$TEMP_ENDPOINTS" 2>/dev/null || true

    # 3. URL construction patterns
    echo "$JSCONTENT" | \
        grep -oE '`[^`]*\$\{[^}]*\}[^`]*`' | \
        grep -v '^\$' | \
        sort -u >> "$TEMP_ENDPOINTS" 2>/dev/null || true

    # 4. Environment/config API keys (interesting for SSRF/leaks)
    echo "$JSCONTENT" | \
        grep -oE '[A-Z_]*API[_-]?KEY[A-Z_]*\s*[=:]\s*["'\''`][^"'\'']*["'\''`]' | \
        sort -u >> "${OUTDIR}/api_keys_found.txt" 2>/dev/null || true

    echo "$JSCONTENT" | \
        grep -oE '[A-Z_]*BASE[_-]?URL[A-Z_]*\s*[=:]\s*["'\''`][^"'\'']*["'\''`]' | \
        sort -u >> "${OUTDIR}/base_urls_found.txt" 2>/dev/null || true

    echo "$JSCONTENT" | \
        grep -oE '[A-Z_]*SECRET[A-Z_]*\s*[=:]\s*["'\''`][^"'\'']*["'\''`]' | \
        sort -u >> "${OUTDIR}/secrets_found.txt" 2>/dev/null || true

done <<< "$ALL_JS"
echo ""

# ─── Extract from page source too ────────────────────────────────────────────
echo -e "${BOLD}─── [4/4] Page source analysis ───${NC}"

# API patterns in HTML
echo "$PAGE" | \
    grep -oE '["'\''`][^"'\'']*/(api|graphql|rest)/[^"'\'']*["'\''`]' | \
    tr -d "'\"\`" | \
    sort -u >> "$TEMP_ENDPOINTS" 2>/dev/null || true

# Action endpoints in forms
echo "$PAGE" | \
    grep -oE 'action="[^"]*"' | \
    sed 's/action="//;s/"$//' | \
    sort -u >> "$TEMP_ENDPOINTS" 2>/dev/null || true

# ─── Compile Results ─────────────────────────────────────────────────────────
sort -u "$TEMP_ENDPOINTS" > "$RESULT" 2>/dev/null || true
TOTAL=$(wc -l < "$RESULT" 2>/dev/null || echo 0)

# Categorize
APIS=$(grep -iE '^/?(api|graphql|rest|v[0-9])' "$RESULT" 2>/dev/null | wc -l || echo 0)
AUTH=$(grep -iE '(auth|login|register|signup|signin|token|session)' "$RESULT" 2>/dev/null | wc -l || echo 0)
USER=$(grep -iE '(user|profile|account|member)' "$RESULT" 2>/dev/null | wc -l || echo 0)
OTHER=$((TOTAL - APIS - AUTH - USER))

echo -e "${GREEN}[✓] Total API endpoints discovered: ${TOTAL}${NC}"
echo -e "    ${CYAN}API routes:${NC}    ${APIS}"
echo -e "    ${CYAN}Auth endpoints:${NC} ${AUTH}"
echo -e "    ${CYAN}User endpoints:${NC} ${USER}"
echo -e "    ${CYAN}Other:${NC}         ${OTHER}"
echo ""

if [[ -f "${OUTDIR}/api_keys_found.txt" ]]; then
    KEYS=$(wc -l < "${OUTDIR}/api_keys_found.txt" 2>/dev/null || echo 0)
    if [[ "$KEYS" -gt 0 ]]; then
        echo -e "${YELLOW}[!] Potential API keys found: ${KEYS}${NC}"
        echo -e "${YELLOW}    Check: ${OUTDIR}/api_keys_found.txt${NC}"
    fi
fi

if [[ -f "${OUTDIR}/secrets_found.txt" ]]; then
    SECRETS=$(wc -l < "${OUTDIR}/secrets_found.txt" 2>/dev/null || echo 0)
    if [[ "$SECRETS" -gt 0 ]]; then
        echo -e "${RED}[!!!] Potential secrets found: ${SECRETS}${NC}"
        echo -e "${RED}     Check: ${OUTDIR}/secrets_found.txt${NC}"
    fi
fi

echo ""
echo -e "${GREEN}    Full results: ${RESULT}${NC}"
rm -f "$TEMP_ENDPOINTS" 2>/dev/null
