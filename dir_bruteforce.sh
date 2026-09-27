#!/usr/bin/env bash
# dir_bruteforce.sh — Directory brute-force wrapper (ffuf/gobuster)
# Usage: ./dir_bruteforce.sh <url> [-w wordlist] [-x extensions]
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'

usage() {
    echo "Usage: $0 <url> [options]"
    echo ""
    echo "Options:"
    echo "  -w <wordlist>   Wordlist path (default: wordlists/medium.txt)"
    echo "  -x <extensions> File extensions (e.g., php,html,js)"
    echo "  -t <threads>    Number of threads (default: 50)"
    echo "  --gobuster      Use gobuster instead of ffuf"
    exit 1
}

[[ $# -lt 1 ]] && usage

URL="$1"
shift

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORDLIST="${SCRIPT_DIR}/wordlists/medium.txt"
EXTENSIONS=""
THREADS=50
ENGINE="ffuf"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -w) WORDLIST="$2"; shift 2 ;;
        -x) EXTENSIONS="$2"; shift 2 ;;
        -t) THREADS="$2"; shift 2 ;;
        --gobuster) ENGINE="gobuster"; shift ;;
        *) shift ;;
    esac
done

# Ensure URL ends with /
[[ ! "$URL" =~ /$ ]] && URL="${URL}/"

# Setup output
DOMAIN=$(echo "$URL" | sed 's|https\?://||;s|/.*||')
OUTDIR="${SCRIPT_DIR}/results/${DOMAIN}/dirs"
mkdir -p "$OUTDIR"
RESULT="${OUTDIR}/$(date +%Y%m%d_%H%M%S).json"

echo -e "${BOLD}[*] Directory Bruteforce: ${URL}${NC}"
echo -e "${CYAN}[*] Wordlist: ${WORDLIST}${NC}"
echo -e "${CYAN}[*] Engine: ${ENGINE}${NC}"

if [[ -n "$EXTENSIONS" ]]; then
    echo -e "${CYAN}[*] Extensions: ${EXTENSIONS}${NC}"
fi

if [[ ! -f "$WORDLIST" ]]; then
    echo -e "${RED}[!] Wordlist not found: ${WORDLIST}${NC}"
    exit 1
fi

WORDLIST_SIZE=$(wc -l < "$WORDLIST")
echo -e "${CYAN}[*] Wordlist size: ${WORDLIST_SIZE} words${NC}"

# ─── ffuf ─────────────────────────────────────────────────────────────────────
run_ffuf() {
    local ext_flag=""
    [[ -n "$EXTENSIONS" ]] && ext_flag="-e .${EXTENSIONS//,/,.}"

    ffuf -u "${URL}FUZZ" \
        -w "$WORDLIST" \
        -mc 200,204,301,302,307,401,403,405,500,502,503 \
        -fc 404 \
        -t "$THREADS" \
        -timeout 10 \
        $ext_flag \
        -s \
        -o "$RESULT" -of json 2>/dev/null
}

# ─── gobuster ─────────────────────────────────────────────────────────────────
run_gobuster() {
    local ext_flag=""
    [[ -n "$EXTENSIONS" ]] && ext_flag="-x ${EXTENSIONS}"

    gobuster dir \
        -u "$URL" \
        -w "$WORDLIST" \
        $ext_flag \
        -t "$THREADS" \
        --no-error \
        -q \
        2>/dev/null | tee "${RESULT%.json}.txt"
}

# ─── Execute ──────────────────────────────────────────────────────────────────
case "$ENGINE" in
    ffuf)
        if ! command -v ffuf &>/dev/null; then
            echo -e "${RED}[!] ffuf not found. Install: go install github.com/ffuf/ffuf/v2@latest${NC}"
            exit 1
        fi
        run_ffuf
        ;;
    gobuster)
        if ! command -v gobuster &>/dev/null; then
            echo -e "${RED}[!] gobuster not found. Install: go install github.com/OJ/gobuster/v3@latest${NC}"
            exit 1
        fi
        run_gobuster
        ;;
esac

# Count results
if [[ -f "$RESULT" ]]; then
    FOUND=$(jq '.results | length' "$RESULT" 2>/dev/null || echo "?")
    echo ""
    echo -e "${GREEN}[✓] Directories found: ${FOUND}${NC}"
    echo -e "${GREEN}    Results saved to: ${RESULT}${NC}"

    # Show top results
    if [[ "$FOUND" != "?" && "$FOUND" != "0" ]]; then
        echo -e "\n${BOLD}─── Top Findings ───${NC}"
        jq -r '.results[] | "  \(.status)\t\(.length)\t\(.url)"' "$RESULT" 2>/dev/null | head -20
    fi
fi
