#!/usr/bin/env bash
# port_scanner.sh — Fast port scanner wrapper (nmap/rustscan)
# Usage: ./port_scanner.sh <target> [--full|-p PORTS]
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'

usage() {
    echo "Usage: $0 <target> [options]"
    echo ""
    echo "Options:"
    echo "  (none)      Top 1000 ports (default)"
    echo "  --full      All 65535 ports"
    echo "  -p PORTS    Custom port list (e.g., 80,443,8080 or 1-1024)"
    exit 1
}

[[ $# -lt 1 ]] && usage

TARGET="$1"
MODE="${2:---top}"
PORTS=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --full)
            MODE="--full"
            shift
            ;;
        -p)
            PORTS="$2"
            MODE="-p"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="${SCRIPT_DIR}/results/${TARGET}/ports"
mkdir -p "$OUTDIR"
RESULT="${OUTDIR}/$(date +%Y%m%d_%H%M%S).txt"

echo -e "${BOLD}[*] Port Scanning: ${TARGET}${NC}"

# Determine port range
case "$MODE" in
    --full)
        NMAP_PORTS="-p-"
        RUSTSCAN_PORTS="-p 1-65535"
        echo -e "${CYAN}[*] Scanning ALL 65535 ports...${NC}"
        ;;
    -p)
        NMAP_PORTS="-p ${PORTS}"
        RUSTSCAN_PORTS="-p ${PORTS}"
        echo -e "${CYAN}[*] Scanning ports: ${PORTS}${NC}"
        ;;
    *)
        NMAP_PORTS="--top-ports 1000"
        RUSTSCAN_PORTS="--top-ports 1000"
        echo -e "${CYAN}[*] Scanning top 1000 ports...${NC}"
        ;;
esac

# Prefer rustscan → nmap pipeline for speed
if command -v rustscan &>/dev/null; then
    echo -e "${CYAN}[*] Using rustscan + nmap pipeline${NC}"
    rustscan -a "$TARGET" $RUSTSCAN_PORTS --ulimit 5000 -- -sV -sC -oN "$RESULT" 2>/dev/null || true
elif command -v nmap &>/dev/null; then
    echo -e "${CYAN}[*] Using nmap${NC}"
    nmap $NMAP_PORTS -sV -sC --open -oN "$RESULT" "$TARGET" 2>/dev/null || true
else
    echo -e "${RED}[!] Neither rustscan nor nmap found. Install one:${NC}"
    echo -e "${YELLOW}    sudo apt install nmap${NC}"
    echo -e "${YELLOW}    cargo install rustscan${NC}"
    exit 1
fi

# Count open ports
OPEN_PORTS=$(grep -cE '^[0-9]+/tcp\s+open' "$RESULT" 2>/dev/null || echo 0)
echo ""
echo -e "${GREEN}[✓] Open ports found: ${OPEN_PORTS}${NC}"
echo -e "${GREEN}    Results saved to: ${RESULT}${NC}"

# Show open ports summary
if [[ "$OPEN_PORTS" -gt 0 ]]; then
    echo -e "\n${BOLD}─── Open Ports ───${NC}"
    grep -E '^[0-9]+/tcp\s+open' "$RESULT" 2>/dev/null | while IFS= read -r line; do
        echo -e "  ${GREEN}${line}${NC}"
    done
fi
