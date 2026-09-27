#!/usr/bin/env bash
# dns_enum.sh — DNS enumeration and zone transfer testing
# Usage: ./dns_enum.sh <domain> [--axfr]
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'

usage() {
    echo "Usage: $0 <domain> [options]"
    echo ""
    echo "Options:"
    echo "  (none)   Full DNS enumeration"
    echo "  --axfr   Include zone transfer test"
    exit 1
}

[[ $# -lt 1 ]] && usage

DOMAIN="$1"
AXFR="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="${SCRIPT_DIR}/results/${DOMAIN}/dns"
mkdir -p "$OUTDIR"
RESULT="${OUTDIR}/dns_$(date +%Y%m%d_%H%M%S).txt"

echo -e "${BOLD}[*] DNS Enumeration: ${DOMAIN}${NC}"
echo ""

# ─── Nameservers ──────────────────────────────────────────────────────────────
echo -e "${BOLD}─── Nameservers ───${NC}"
NS_RECORDS=$(dig +short NS "$DOMAIN" 2>/dev/null)
if [[ -n "$NS_RECORDS" ]]; then
    echo "$NS_RECORDS" | while IFS= read -r ns; do
        NS_IP=$(dig +short A "$ns" 2>/dev/null | head -1)
        echo -e "  ${GREEN}${ns}${NC} → ${CYAN}${NS_IP}${NC}"
        echo "NS: ${ns} ${IP}" >> "$RESULT"
    done
else
    echo -e "${YELLOW}[!] No NS records found${NC}"
fi
echo ""

# ─── Standard Records ────────────────────────────────────────────────────────
echo -e "${BOLD}─── Standard DNS Records ───${NC}"

RECORD_TYPES=("A" "AAAA" "MX" "TXT" "SOA" "CNAME" "SRV" "CAA")

for rtype in "${RECORD_TYPES[@]}"; do
    RECORDS=$(dig +short "$rtype" "$DOMAIN" 2>/dev/null)
    if [[ -n "$RECORDS" ]]; then
        echo -e "  ${CYAN}${rtype}:${NC}"
        echo "$RECORDS" | while IFS= read -r rec; do
            echo -e "    ${GREEN}${rec}${NC}"
            echo "${rtype}: ${rec}" >> "$RESULT"
        done
    fi
done
echo ""

# ─── Reverse DNS ──────────────────────────────────────────────────────────────
echo -e "${BOLD}─── Reverse DNS (A records) ───${NC}"
A_RECORDS=$(dig +short A "$DOMAIN" 2>/dev/null)
if [[ -n "$A_RECORDS" ]]; then
    echo "$A_RECORDS" | while IFS= read -r ip; do
        RDNS=$(dig +short -x "$ip" 2>/dev/null)
        if [[ -n "$RDNS" ]]; then
            echo -e "  ${GREEN}${ip}${NC} → ${CYAN}${RDNS}${NC}"
            echo "RDNS: ${ip} → ${RDNS}" >> "$RESULT"
        else
            echo -e "  ${YELLOW}${ip} → (no reverse DNS)${NC}"
        fi
    done
fi
echo ""

# ─── SPF/DKIM/DMARC ──────────────────────────────────────────────────────────
echo -e "${BOLD}─── Email Security Records ───${NC}"

SPF=$(dig +short TXT "$DOMAIN" 2>/dev/null | grep "v=spf1")
if [[ -n "$SPF" ]]; then
    echo -e "  ${GREEN}SPF: ${SPF}${NC}"
    echo "SPF: ${SPF}" >> "$RESULT"
else
    echo -e "  ${YELLOW}SPF: Not found${NC}"
fi

DMARC=$(dig +short TXT "_dmarc.${DOMAIN}" 2>/dev/null | grep "v=DMARC1")
if [[ -n "$DMARC" ]]; then
    echo -e "  ${GREEN}DMARC: ${DMARC}${NC}"
    echo "DMARC: ${DMARC}" >> "$RESULT"
else
    echo -e "  ${YELLOW}DMARC: Not found${NC}"
fi

# Common DKIM selectors
for selector in "default" "google" "selector1" "selector2" "mandrill" "k1" "everlytickey1" "dkim" "mail"; do
    DKIM=$(dig +short TXT "${selector}._domainkey.${DOMAIN}" 2>/dev/null)
    if [[ -n "$DKIM" ]]; then
        echo -e "  ${GREEN}DKIM (${selector}): ${DKIM}${NC}"
        echo "DKIM (${selector}): ${DKIM}" >> "$RESULT"
    fi
done
echo ""

# ─── Zone Transfer ───────────────────────────────────────────────────────────
if [[ "$AXFR" == "--axfr" ]]; then
    echo -e "${BOLD}─── Zone Transfer Test ───${NC}"
    ZONE_VULN=0

    while IFS= read -r ns; do
        ns=$(echo "$ns" | tr -d '[:space:]')
        [[ -z "$ns" ]] && continue
        echo -e "${CYAN}[*] Testing zone transfer to ${ns}...${NC}"

        AXFR_RESULT=$(dig @"$ns" "$DOMAIN" AXFR +time=5 2>/dev/null)
        if echo "$AXFR_RESULT" | grep -q "XFR size"; then
            echo -e "${RED}[!!! VULN] Zone transfer SUCCEEDED to ${ns}!${NC}"
            AXFR_COUNT=$(echo "$AXFR_RESULT" | grep -c "IN\s" || echo 0)
            echo -e "${RED}    ${AXFR_COUNT} records exposed${NC}"
            echo "ZONE_TRANSFER_VULN: ${ns} (${AXFR_COUNT} records)" >> "$RESULT"
            ((ZONE_VULN++))

            # Save zone data
            echo "$AXFR_RESULT" >> "${OUTDIR}/zone_transfer_${ns}.txt"
        else
            echo -e "${GREEN}[✓] Zone transfer refused by ${ns}${NC}"
        fi
    done <<< "$NS_RECORDS"

    if [[ $ZONE_VULN -eq 0 ]]; then
        echo -e "${GREEN}[✓] No zone transfers possible${NC}"
    else
        echo -e "${RED}[!] ${ZONE_VULN} nameserver(s) vulnerable to zone transfer!${NC}"
    fi
    echo ""
fi

# ─── DNSRecon (if available) ─────────────────────────────────────────────────
if command -v dnsrecon &>/dev/null; then
    echo -e "${BOLD}─── DNSRecon ───${NC}"
    echo -e "${CYAN}[*] Running dnsrecon...${NC}"
    dnsrecon -d "$DOMAIN" -t std 2>/dev/null > "${OUTDIR}/dnsrecon.txt" || true
    echo -e "${GREEN}[✓] dnsrecon output saved${NC}"
    echo ""
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo -e "${BOLD}═══ DNS Enumeration Complete ═══${NC}"
echo -e "  Domain:  ${GREEN}${DOMAIN}${NC}"
echo -e "  Results: ${GREEN}${RESULT}${NC}"
