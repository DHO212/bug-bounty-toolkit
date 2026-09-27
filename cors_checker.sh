#!/usr/bin/env bash
# cors_checker.sh — CORS misconfiguration checker (pure bash/curl)
# Usage: ./cors_checker.sh <url> [--verbose]
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'

usage() {
    echo "Usage: $0 <url> [--verbose]"
    exit 1
}

[[ $# -lt 1 ]] && usage

URL="$1"
VERBOSE="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="${SCRIPT_DIR}/results/$(echo "$URL" | sed 's|https\?://||;s|/.*||')/cors"
mkdir -p "$OUTDIR"
RESULT="${OUTDIR}/cors_$(date +%Y%m%d_%H%M%S).txt"

echo -e "${BOLD}[*] CORS Misconfiguration Check: ${URL}${NC}"
echo ""

# ─── Payloads ─────────────────────────────────────────────────────────────────
declare -a PAYLOADS=(
    "null"
    "evil.com"
    "attacker.com"
    "subdomain.$(echo "$URL" | sed 's|https\?://||;s|/.*||')"
    "$(echo "$URL" | sed 's|https\?://||;s|/.*||').evil.com"
    "https://$(echo "$URL" | sed 's|https\?://||;s|/.*||')"
    "http://$(echo "$URL" | sed 's|https\?://||;s|/.*||')"
    "https://$(echo "$URL" | sed 's|https\?://||;s|/.*||')/"
    "https://evil.com@$(echo "$URL" | sed 's|https\?://||;s|/.*||')"
    "%60evil.com"
    "%0evil.com"
    "_.evil.com"
    "évil.com"
)

VULNS=0
SAFE=0

# ─── Check ────────────────────────────────────────────────────────────────────
for payload in "${PAYLOADS[@]}"; do
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Origin: ${payload}" \
        --max-time 10 \
        "$URL" 2>/dev/null)

    CORS_HEADER=$(curl -s -D - -o /dev/null \
        -H "Origin: ${payload}" \
        --max-time 10 \
        "$URL" 2>/dev/null | grep -i "access-control-allow-origin")

    ACAC=$(curl -s -D - -o /dev/null \
        -H "Origin: ${payload}" \
        --max-time 10 \
        "$URL" 2>/dev/null | grep -i "access-control-allow-credentials")

    if [[ -n "$CORS_HEADER" ]]; then
        ACAO=$(echo "$CORS_HEADER" | tr -d '\r' | awk '{print $2}')
        CRED=""
        [[ -n "$ACAC" ]] && CRED=$(echo "$ACAC" | tr -d '\r' | awk '{print $2}')

        if [[ "$ACAO" == "$payload" || "$ACAO" == "*" ]]; then
            if [[ "$ACAO" == "$payload" && "$CRED" == "true" ]]; then
                echo -e "${RED}[!!! VULN] Origin reflected with credentials: ${payload}${NC}"
                echo -e "${RED}    ACAO: ${ACAO} | ACAC: ${CRED}${NC}"
                echo "[VULN] Origin=${payload} ACAO=${ACAO} ACAC=${CRED} HTTP=${RESPONSE}" >> "$RESULT"
                ((VULNS++))
            elif [[ "$ACAO" == "*" ]]; then
                echo -e "${YELLOW}[!!! WARN] Wildcard ACAO: *${NC}"
                echo -e "${YELLOW}    ACAO: ${ACAO}${NC}"
                echo "[WARN] Origin=${payload} ACAO=${ACAO} HTTP=${RESPONSE}" >> "$RESULT"
                ((VULNS++))
            elif [[ "$ACAO" == "$payload" ]]; then
                echo -e "${YELLOW}[!! WARN] Origin reflected (no credentials): ${payload}${NC}"
                echo -e "${YELLOW}    ACAO: ${ACAO}${NC}"
                echo "[WARN] Origin=${payload} ACAO=${ACAO} HTTP=${RESPONSE}" >> "$RESULT"
                ((VULNS++))
            fi
        elif [[ "$VERBOSE" == "--verbose" ]]; then
            echo -e "${GREEN}[SAFE] ${payload} → ${ACAO:-none}${NC}"
            echo "[SAFE] Origin=${payload} ACAO=${ACAO:-none} HTTP=${RESPONSE}" >> "$RESULT"
            ((SAFE++))
        fi
    elif [[ "$VERBOSE" == "--verbose" ]]; then
        echo -e "${GREEN}[SAFE] ${payload} → no CORS header${NC}"
        ((SAFE++))
    fi
done

# ─── Preflight Check ─────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}[*] Testing preflight (OPTIONS) response...${NC}"
PREFLIGHT=$(curl -s -o /dev/null -w "%{http_code}" \
    -X OPTIONS \
    -H "Origin: evil.com" \
    -H "Access-Control-Request-Method: GET" \
    --max-time 10 \
    "$URL" 2>/dev/null)

if [[ "$PREFLIGHT" == "200" || "$PREFLIGHT" == "204" ]]; then
    echo -e "${YELLOW}[!! WARN] Preflight accepted with 200/204 — may accept any method${NC}"
    ((VULNS++))
else
    echo -e "${GREEN}[SAFE] Preflight returned ${PREFLIGHT}${NC}"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══ CORS Check Complete ═══${NC}"
echo -e "  Vulnerabilities: ${RED}${VULNS}${NC}"
echo -e "  Safe tests:      ${GREEN}${SAFE}${NC}"
echo -e "  Results:         ${GREEN}${RESULT}${NC}"
