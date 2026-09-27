#!/usr/bin/env bash
# recon.sh — Full recon pipeline for bug bounty targets
# Usage: ./recon.sh <domain>
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'

banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
  ____            _   _             ___               _    
 | __ )  __ _ ___| |_(_)_ __ ___  |_ _|_ ____   __ _| | __
 |  _ \ / _` / __| __| | '_ ` _ \  | || '_ \ \ / / _` |/ /
 | |_) | (_| \__ \ |_| | | | | | | | || | | \ V / (_| | < 
 |____/ \__,_|___/\__|_|_| |_| |_|___|_| |_|\_/ \__,_|_|\_\
EOF
    echo -e "${NC}"
    echo -e "  ${BOLD}Full Recon Pipeline${NC} — Target: ${GREEN}${1}${NC}"
    echo ""
}

usage() {
    echo "Usage: $0 <domain> [--quick|--full]"
    echo ""
    echo "Options:"
    echo "  --quick   Skip port scan and dir bruteforce"
    echo "  --full    Full pipeline (default)"
    exit 1
}

[[ $# -lt 1 ]] && usage

DOMAIN="$1"
MODE="${2:---full}"
TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="${TOOLS_DIR}/results/${DOMAIN}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ─── Setup ────────────────────────────────────────────────────────────────────
banner "$DOMAIN"
mkdir -p "$RESULTS_DIR"/{subdomains,live,ports,dirs,nuclei,js,api,reports}
LOG="${RESULTS_DIR}/reports/recon_${TIMESTAMP}.log"
exec > >(tee -a "$LOG") 2>&1

echo -e "${YELLOW}[*] Results directory: ${RESULTS_DIR}${NC}"
echo -e "${YELLOW}[*] Started at: $(date)${NC}"
echo ""

# ─── Helper ───────────────────────────────────────────────────────────────────
check_tool() {
    command -v "$1" &>/dev/null
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[!] Required tool not found: $1${NC}"
        echo -e "${YELLOW}[!] Run ./install.sh to install dependencies${NC}"
        return 1
    fi
    echo -e "${GREEN}[✓] Found: $1${NC}"
}

# ─── Check Tools ──────────────────────────────────────────────────────────────
echo -e "${BOLD}═══ Checking Dependencies ═══${NC}"
for tool in subfinder httpx nuclei ffuf; do
    check_tool "$tool" || true
done
echo ""

# ─── Step 1: Subdomain Enumeration ────────────────────────────────────────────
echo -e "${BOLD}═══ [1/7] Subdomain Enumeration ═══${NC}"
SUBDOMAINS="${RESULTS_DIR}/subdomains/all.txt"

if check_tool subfinder; then
    echo -e "${CYAN}[*] Running subfinder...${NC}"
    subfinder -d "$DOMAIN" -silent -o "${RESULTS_DIR}/subdomains/subfinder.txt" 2>/dev/null || true
fi

# crt.sh passive enumeration
echo -e "${CYAN}[*] Querying crt.sh...${NC}"
curl -s "https://crt.sh/?q=%25.${DOMAIN}&output=json" 2>/dev/null | \
    jq -r '.[].name_value' 2>/dev/null | \
    grep -v '^$' | sort -u > "${RESULTS_DIR}/subdomains/crtsh.txt" 2>/dev/null || true

# wayback subdomains
if check_tool waybackurls; then
    echo "$DOMAIN" | waybackurls 2>/dev/null | \
        awk -F/ '{print $3}' | sort -u > "${RESULTS_DIR}/subdomains/wayback.txt" 2>/dev/null || true
fi

# Merge and deduplicate
cat "${RESULTS_DIR}/subdomains/"*.txt 2>/dev/null | sort -u > "$SUBDOMAINS"
SUB_COUNT=$(wc -l < "$SUBDOMAINS")
echo -e "${GREEN}[✓] Total unique subdomains: ${SUB_COUNT}${NC}"
echo ""

# ─── Step 2: Live Host Probing ────────────────────────────────────────────────
echo -e "${BOLD}═══ [2/7] Live Host Probing ═══${NC}"
LIVE="${RESULTS_DIR}/live/live.txt"

if [[ -s "$SUBDOMAINS" ]] && check_tool httpx; then
    echo -e "${CYAN}[*] Probing with httpx...${NC}"
    httpx -l "$SUBDOMAINS" -silent -status-code -title -tech-detect -follow-redirects \
        -o "$LIVE" 2>/dev/null || true
    LIVE_COUNT=$(wc -l < "$LIVE" 2>/dev/null || echo 0)
    echo -e "${GREEN}[✓] Live hosts: ${LIVE_COUNT}${NC}"
else
    echo -e "${YELLOW}[!] No subdomains or httpx not found, skipping live probe${NC}"
fi
echo ""

# ─── Step 3: Port Scanning ───────────────────────────────────────────────────
if [[ "$MODE" != "--quick" ]]; then
    echo -e "${BOLD}═══ [3/7] Port Scanning ═══${NC}"
    if [[ -s "$LIVE" ]]; then
        while IFS= read -r host; do
            TARGET=$(echo "$host" | awk '{print $1}' | sed 's|https\?://||;s|/.*||')
            echo -e "${CYAN}[*] Scanning ${TARGET}...${NC}"
            bash "${TOOLS_DIR}/port_scanner.sh" "$TARGET" 2>/dev/null > "${RESULTS_DIR}/ports/${TARGET}.txt" || true
        done < "$LIVE"
    else
        echo -e "${YELLOW}[!] No live hosts to scan${NC}"
    fi
    echo ""
fi

# ─── Step 4: Directory Bruteforce ────────────────────────────────────────────
if [[ "$MODE" != "--quick" ]]; then
    echo -e "${BOLD}═══ [4/7] Directory Bruteforce ═══${NC}"
    if [[ -s "$LIVE" ]] && check_tool ffuf; then
        while IFS= read -r host; do
            URL=$(echo "$host" | awk '{print $1}')
            TARGET=$(echo "$URL" | sed 's|https\?://||;s|/.*||')
            echo -e "${CYAN}[*] Brute-forcing ${URL}...${NC}"
            ffuf -u "${URL}/FUZZ" -w "${TOOLS_DIR}/wordlists/medium.txt" \
                -mc 200,204,301,302,307,401,403,405 \
                -s -o "${RESULTS_DIR}/dirs/${TARGET}.json" -of json 2>/dev/null || true
        done < "$LIVE"
    else
        echo -e "${YELLOW}[!] No live hosts or ffuf not found${NC}"
    fi
    echo ""
fi

# ─── Step 5: JavaScript Extraction ───────────────────────────────────────────
echo -e "${BOLD}═══ [5/7] JavaScript Extraction ═══${NC}"
if [[ -s "$LIVE" ]]; then
    while IFS= read -r host; do
        URL=$(echo "$host" | awk '{print $1}')
        echo -e "${CYAN}[*] Extracting JS from ${URL}...${NC}"
        bash "${TOOLS_DIR}/js_extractor.sh" "$URL" 2>/dev/null >> "${RESULTS_DIR}/js/endpoints.txt" || true
    done < "$LIVE"
    JS_COUNT=$(wc -l < "${RESULTS_DIR}/js/endpoints.txt" 2>/dev/null || echo 0)
    echo -e "${GREEN}[✓] JS endpoints found: ${JS_COUNT}${NC}"
fi
echo ""

# ─── Step 6: API Discovery ──────────────────────────────────────────────────
echo -e "${BOLD}═══ [6/7] API Discovery ═══${NC}"
if [[ -s "${RESULTS_DIR}/js/endpoints.txt" ]]; then
    echo -e "${CYAN}[*] Discovering API endpoints...${NC}"
    grep -oE '(https?://[^"'\''` ]+|/[a-zA-Z0-9/_-]+\?)' "${RESULTS_DIR}/js/endpoints.txt" | \
        sort -u > "${RESULTS_DIR}/api/endpoints.txt" 2>/dev/null || true
    API_COUNT=$(wc -l < "${RESULTS_DIR}/api/endpoints.txt" 2>/dev/null || echo 0)
    echo -e "${GREEN}[✓] API endpoints discovered: ${API_COUNT}${NC}"
fi
echo ""

# ─── Step 7: Nuclei Scan ─────────────────────────────────────────────────────
if [[ -s "$LIVE" ]] && check_tool nuclei; then
    echo -e "${BOLD}═══ [7/7] Nuclei Vulnerability Scan ═══${NC}"
    awk '{print $1}' "$LIVE" > "${RESULTS_DIR}/live/urls.txt"
    echo -e "${CYAN}[*] Running nuclei template scan...${NC}"
    nuclei -l "${RESULTS_DIR}/live/urls.txt" -silent -severity critical,high,medium \
        -o "${RESULTS_DIR}/nuclei/results.txt" 2>/dev/null || true
    NUCLEI_COUNT=$(wc -l < "${RESULTS_DIR}/nuclei/results.txt" 2>/dev/null || echo 0)
    echo -e "${GREEN}[✓] Nuclei findings: ${NUCLEI_COUNT}${NC}"
fi
echo ""

# ─── Summary ──────────────────────────────────────────────────────────────────
echo -e "${BOLD}═══ Recon Complete ═══${NC}"
echo -e "  Domain:    ${GREEN}${DOMAIN}${NC}"
echo -e "  Subdomains: ${GREEN}${SUB_COUNT}${NC}"
echo -e "  Live hosts: ${GREEN}${LIVE_COUNT:-0}${NC}"
echo -e "  Results:   ${GREEN}${RESULTS_DIR}${NC}"
echo -e "  Log:       ${GREEN}${LOG}${NC}"
echo -e "  Finished:  ${GREEN}$(date)${NC}"
