#!/usr/bin/env bash
# subdomain_enum.sh — Multi-tool subdomain enumeration wrapper
# Usage: ./subdomain_enum.sh <domain> [--crtsh|--amass|--merge]
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'

usage() {
    echo "Usage: $0 <domain> [options]"
    echo ""
    echo "Options:"
    echo "  (none)      Run all available tools and merge results"
    echo "  --crtsh     Use crt.sh only"
    echo "  --amass     Use amass only"
    echo "  --merge     Merge all previous results and deduplicate"
    exit 1
}

[[ $# -lt 1 ]] && usage

DOMAIN="$1"
MODE="${2:---all}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="${SCRIPT_DIR}/results/${DOMAIN}/subdomains"
mkdir -p "$OUTDIR"

echo -e "${BOLD}[*] Subdomain Enumeration: ${DOMAIN}${NC}"

# ─── crt.sh ────────────────────────────────────────────────────────────────────
run_crtsh() {
    echo -e "${CYAN}[*] Querying crt.sh...${NC}"
    curl -s "https://crt.sh/?q=%25.${DOMAIN}&output=json" | \
        jq -r '.[].name_value' 2>/dev/null | \
        grep -v '^$' | sort -u > "${OUTDIR}/crtsh.txt"
    local count=$(wc -l < "${OUTDIR}/crtsh.txt")
    echo -e "${GREEN}[✓] crt.sh: ${count} subdomains${NC}"
}

# ─── subfinder ─────────────────────────────────────────────────────────────────
run_subfinder() {
    if ! command -v subfinder &>/dev/null; then
        echo -e "${YELLOW}[!] subfinder not found, skipping${NC}"
        return
    fi
    echo -e "${CYAN}[*] Running subfinder...${NC}"
    subfinder -d "$DOMAIN" -silent -o "${OUTDIR}/subfinder.txt" 2>/dev/null
    local count=$(wc -l < "${OUTDIR}/subfinder.txt")
    echo -e "${GREEN}[✓] subfinder: ${count} subdomains${NC}"
}

# ─── amass ─────────────────────────────────────────────────────────────────────
run_amass() {
    if ! command -v amass &>/dev/null; then
        echo -e "${YELLOW}[!] amass not found, skipping${NC}"
        return
    fi
    echo -e "${CYAN}[*] Running amass enum (passive)...${NC}"
    amass enum -passive -d "$DOMAIN" -o "${OUTDIR}/amass.txt" 2>/dev/null
    local count=$(wc -l < "${OUTDIR}/amass.txt" 2>/dev/null || echo 0)
    echo -e "${GREEN}[✓] amass: ${count} subdomains${NC}"
}

# ─── assetfinder ───────────────────────────────────────────────────────────────
run_assetfinder() {
    if ! command -v assetfinder &>/dev/null; then
        echo -e "${YELLOW}[!] assetfinder not found, skipping${NC}"
        return
    fi
    echo -e "${CYAN}[*] Running assetfinder...${NC}"
    assetfinder --subs-only "$DOMAIN" > "${OUTDIR}/assetfinder.txt" 2>/dev/null
    local count=$(wc -l < "${OUTDIR}/assetfinder.txt")
    echo -e "${GREEN}[✓] assetfinder: ${count} subdomains${NC}"
}

# ─── Merge ─────────────────────────────────────────────────────────────────────
merge_results() {
    echo -e "${CYAN}[*] Merging all results...${NC}"
    cat "${OUTDIR}"/*.txt 2>/dev/null | sort -u > "${OUTDIR}/all.txt"
    local count=$(wc -l < "${OUTDIR}/all.txt")
    echo -e "${GREEN}[✓] Total unique subdomains: ${count}${NC}"
    echo -e "${GREEN}    Saved to: ${OUTDIR}/all.txt${NC}"
}

# ─── Execute ──────────────────────────────────────────────────────────────────
case "$MODE" in
    --crtsh)
        run_crtsh
        ;;
    --amass)
        run_amass
        ;;
    --merge)
        merge_results
        ;;
    --all|"")
        run_crtsh
        run_subfinder
        run_assetfinder
        run_amass
        merge_results
        ;;
    *)
        echo -e "${RED}[!] Unknown option: $MODE${NC}"
        usage
        ;;
esac
