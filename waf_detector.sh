#!/usr/bin/env bash
# waf_detector.sh — WAF/CDN detection and identification
# Usage: ./waf_detector.sh <url> [--probe]
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'

usage() {
    echo "Usage: $0 <url> [--probe]"
    echo ""
    echo "Options:"
    echo "  (none)   Header-based WAF detection"
    echo "  --probe  Include active payload probing"
    exit 1
}

[[ $# -lt 1 ]] && usage

URL="$1"
PROBE="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOMAIN=$(echo "$URL" | sed 's|https\?://||;s|/.*||')
OUTDIR="${SCRIPT_DIR}/results/${DOMAIN}/waf"
mkdir -p "$OUTDIR"
RESULT="${OUTDIR}/waf_$(date +%Y%m%d_%H%M%S).txt"

echo -e "${BOLD}[*] WAF/CDN Detection: ${URL}${NC}"
echo ""

# ─── WAF Signature Database ──────────────────────────────────────────────────
declare -A WAF_SIGS=(
    # Header-based detection
    ["cloudflare"]="server:cloudflare|cf-ray|cf-cache-status|__cfduid|cf-connecting-ip"
    ["akamai"]="server:akamaighost|x-akamai-transformed|akamai-"
    ["cloudfront"]="server:cloudfront|x-amz-cf-id|x-amz-cf-pop|via:.*cloudfront"
    ["aws-waf"]="x-amzn-waf|aws-waf"
    ["incapsula"]="server:incapsula|x-iinfo|incap_ses|visid_incap"
    ["sucuri"]="server:sucuri|x-sucuri-id|sucuri_"
    ["barracuda"]="server:barracuda|barra_counter_session"
    ["f5"]="server:F5|BIGipServer|ts0|f5_"
    ["modsecurity"]="server:mod_security|modsecurity|NOYB"
    ["nginx-vts"]="server:nginx|via:.*nginx"
    ["imperva"]="server:imperva|x-cdn|imperva"
    ["radware"]="server:radware-appwall|X-Backside-Transport"
    ["fortiweb"]="server:FortiWeb|FORTIWAFSID"
    ["denyall"]="server:denyall|Cookie:.*JSSIONID"
    ["edgecast"]="server:ECS|server:ecs|edgecast"
    ["fastly"]="server:fastly|x-fastly-request-id"
    ["limelight"]="server:llnw|server:limelight"
    ["azure-front-door"]="x-azure-ref|x-azure-fdid|server:azure"
    ["vercel"]="server:vercel|x-vercel-id"
    ["netlify"]="server:netlify|x-nf-request-id"
)

# ─── Step 1: Passive Detection (Headers) ──────────────────────────────────────
echo -e "${BOLD}─── [1/3] Header Analysis ───${NC}"

HEADERS=$(curl -s -D - -o /dev/null --max-time 10 "$URL" 2>/dev/null)
HEADERS_LOWER=$(echo "$HEADERS" | tr '[:upper:]' '[:lower:]')

DETECTED=()

for waf in "${!WAF_SIGS[@]}"; do
    IFS='|' read -ra PATTERNS <<< "${WAF_SIGS[$waf]}"
    for pattern in "${PATTERNS[@]}"; do
        if echo "$HEADERS_LOWER" | grep -qiE "$pattern"; then
            DETECTED+=("$waf")
            echo -e "${GREEN}[✓] Detected: ${BOLD}${waf}${NC}"
            break
        fi
    done
done

if [[ ${#DETECTED[@]} -eq 0 ]]; then
    echo -e "${YELLOW}[!] No WAF/CDN detected from headers${NC}"
fi

# Show all headers
echo -e "\n${CYAN}[*] Response Headers:${NC}"
echo "$HEADERS" | head -30 | while IFS= read -r line; do
    echo -e "    ${CYAN}${line}${NC}"
done
echo ""

# ─── Step 2: Cookie Analysis ─────────────────────────────────────────────────
echo -e "${BOLD}─── [2/3] Cookie Analysis ───${NC}"

COOKIES=$(curl -s -D - -o /dev/null --max-time 10 "$URL" 2>/dev/null | grep -i 'set-cookie')
if [[ -n "$COOKIES" ]]; then
    echo "$COOKIES" | while IFS= read -r cookie; do
        cookie_lower=$(echo "$cookie" | tr '[:upper:]' '[:lower:]')

        if echo "$cookie_lower" | grep -qiE '__cfduid|cf_clearance'; then
            echo -e "${GREEN}[✓] Cloudflare cookies detected${NC}"
        elif echo "$cookie_lower" | grep -qiE 'incap_ses|visid_incap'; then
            echo -e "${GREEN}[✓] Incapsula cookies detected${NC}"
        elif echo "$cookie_lower" | grep -qiE 'sucuri-'; then
            echo -e "${GREEN}[✓] Sucuri cookies detected${NC}"
        elif echo "$cookie_lower" | grep -qiE 'akamai|ak_bmsc'; then
            echo -e "${GREEN}[✓] Akamai cookies detected${NC}"
        elif echo "$cookie_lower" | grep -qiE 'ts0|BIGipServer|f5_'; then
            echo -e "${GREEN}[✓] F5/BIG-IP cookies detected${NC}"
        elif echo "$cookie_lower" | grep -qiE 'awselb|AWSELBAuth'; then
            echo -e "${GREEN}[✓] AWS ELB detected${NC}"
        elif echo "$cookie_lower" | grep -qiE '__profile_'; then
            echo -e "${GREEN}[✓] Azure Front Door cookies detected${NC}"
        fi

        echo -e "    ${CYAN}$(echo "$cookie" | tr -d '\r')${NC}"
    done
else
    echo -e "${YELLOW}[!] No Set-Cookie headers found${NC}"
fi
echo ""

# ─── Step 3: Active Probing ──────────────────────────────────────────────────
echo -e "${BOLD}─── [3/3] Page Content Analysis ───${NC}"

PAGE_CONTENT=$(curl -s -L --max-time 10 "$URL" 2>/dev/null)

# Check for WAF-specific HTML/JS
declare -A PAGE_SIGS=(
    ["Cloudflare"]="cloudflare|cf-browser-verification|cloudflare-challenge"
    ["Sucuri"]="sucuri|cloudproxy"
    ["Incapsula"]="incapsula|_Incapsula_Resource"
    ["Akamai"]="akamai|akamaihd"
    ["ModSecurity"]="mod_security|modsecurity"
)

for waf in "${!PAGE_SIGS[@]}"; do
    if echo "$PAGE_CONTENT" | grep -qiE "${PAGE_SIGS[$waf]}"; then
        echo -e "${GREEN}[✓] Page content matches: ${waf}${NC}"
        DETECTED+=("$waf")
    fi
done
echo ""

# ─── Active Probe (optional) ─────────────────────────────────────────────────
if [[ "$PROBE" == "--probe" ]]; then
    echo -e "${BOLD}─── Active WAF Probing ───${NC}"
    echo -e "${CYAN}[*] Sending suspicious payloads to test WAF response...${NC}"

    declare -a PROBE_PAYLOADS=(
        '<script>alert(1)</script>'
        "' OR 1=1--"
        '../../etc/passwd'
        '{{7*7}}'
        '${7*7}'
        'cat /etc/passwd'
    )

    for payload in "${PROBE_PAYLOADS[@]}"; do
        ENCODED=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$payload'))" 2>/dev/null || echo "$payload")
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${URL}?q=${ENCODED}" 2>/dev/null)

        if [[ "$RESPONSE" == "403" || "$RESPONSE" == "406" || "$RESPONSE" == "419" || "$RESPONSE" == "429" || "$RESPONSE" == "501" ]]; then
            echo -e "${RED}[!!! WAF] Payload blocked (${RESPONSE}): ${payload:0:40}${NC}"
        elif [[ "$RESPONSE" == "418" ]]; then
            echo -e "${RED}[!!! WAF] Teapot response (418) — likely WAF: ${payload:0:40}${NC}"
        else
            echo -e "${GREEN}[ALLOWED] ${RESPONSE}: ${payload:0:40}${NC}"
        fi
    done
    echo ""
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo -e "${BOLD}═══ WAF Detection Complete ═══${NC}"

# Deduplicate
UNIQUE_DETECTED=($(printf '%s\n' "${DETECTED[@]}" 2>/dev/null | sort -u))

if [[ ${#UNIQUE_DETECTED[@]} -gt 0 ]]; then
    echo -e "  ${BOLD}Detected WAF/CDN:${NC}"
    for waf in "${UNIQUE_DETECTED[@]}"; do
        echo -e "    ${GREEN}• ${waf}${NC}"
    done
    echo "${UNIQUE_DETECTED[@]}" > "$RESULT"
else
    echo -e "  ${YELLOW}No WAF/CDN detected — target may be unprotected${NC}"
    echo "No WAF detected" > "$RESULT"
fi

echo -e "  Results: ${GREEN}${RESULT}${NC}"
