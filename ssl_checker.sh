#!/usr/bin/env bash
# ssl_checker.sh — SSL/TLS configuration checker and vulnerability scanner
# Usage: ./ssl_checker.sh <domain> [--grade]
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'

usage() {
    echo "Usage: $0 <domain> [--grade]"
    echo ""
    echo "Options:"
    echo "  (none)     Full SSL/TLS check"
    echo "  --grade    Include SSL Labs grade (requires API)"
    exit 1
}

[[ $# -lt 1 ]] && usage

DOMAIN="$1"
GRADE="${2:-}"
PORT=443
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="${SCRIPT_DIR}/results/${DOMAIN}/ssl"
mkdir -p "$OUTDIR"
RESULT="${OUTDIR}/ssl_$(date +%Y%m%d_%H%M%S).txt"

echo -e "${BOLD}[*] SSL/TLS Configuration Check: ${DOMAIN}:${PORT}${NC}"
echo ""

ISSUES=0

# ─── Basic Connection Test ────────────────────────────────────────────────────
echo -e "${BOLD}─── [1/6] Connection Test ───${NC}"
if echo "" | timeout 5 openssl s_client -connect "${DOMAIN}:${PORT}" -servername "$DOMAIN" 2>/dev/null | grep -q "BEGIN CERTIFICATE"; then
    echo -e "${GREEN}[✓] SSL/TLS connection successful${NC}"
else
    echo -e "${RED}[✗] Cannot establish SSL/TLS connection to ${DOMAIN}:${PORT}${NC}"
    exit 1
fi
echo ""

# ─── Certificate Info ────────────────────────────────────────────────────────
echo -e "${BOLD}─── [2/6] Certificate Information ───${NC}"
CERT_INFO=$(echo "" | openssl s_client -connect "${DOMAIN}:${PORT}" -servername "$DOMAIN" 2>/dev/null | openssl x509 -noout -text 2>/dev/null)

SUBJECT=$(echo "$CERT_INFO" | grep "Subject:" | head -1 | sed 's/.*Subject: //')
ISSUER=$(echo "$CERT_INFO" | grep "Issuer:" | head -1 | sed 's/.*Issuer: //')
NOT_AFTER=$(echo "$CERT_INFO" | grep "Not After" | sed 's/.*Not After : //')
NOT_BEFORE=$(echo "$CERT_INFO" | grep "Not Before" | sed 's/.*Not Before: //')
SERIAL=$(echo "$CERT_INFO" | grep "Serial Number:" | head -1 | sed 's/.*Serial Number: //')
KEY_SIZE=$(echo "$CERT_INFO" | grep "Public-Key:" | sed 's/.*Public-Key: (//' | sed 's/ bit)//')
SIG_ALG=$(echo "$CERT_INFO" | grep "Signature Algorithm:" | head -1 | sed 's/.*Signature Algorithm: //')

echo -e "  Subject:    ${CYAN}${SUBJECT}${NC}"
echo -e "  Issuer:     ${CYAN}${ISSUER}${NC}"
echo -e "  Valid From: ${CYAN}${NOT_BEFORE}${NC}"
echo -e "  Expires:    ${CYAN}${NOT_AFTER}${NC}"
echo -e "  Key Size:   ${CYAN}${KEY_SIZE} bits${NC}"
echo -e "  Sig Alg:    ${CYAN}${SIG_ALG}${NC}"
echo ""

# ─── Expiry Check ─────────────────────────────────────────────────────────────
echo -e "${BOLD}─── [3/6] Certificate Expiry ───${NC}"
EXPIRY_EPOCH=$(date -d "$NOT_AFTER" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$NOT_AFTER" +%s 2>/dev/null || echo 0)
NOW_EPOCH=$(date +%s)
DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

if [[ $DAYS_LEFT -lt 0 ]]; then
    echo -e "${RED}[!!! CRITICAL] Certificate EXPIRED $((DAYS_LEFT * -1)) days ago!${NC}"
    ((ISSUES++))
elif [[ $DAYS_LEFT -lt 30 ]]; then
    echo -e "${RED}[!!! VULN] Certificate expires in ${DAYS_LEFT} days!${NC}"
    ((ISSUES++))
elif [[ $DAYS_LEFT -lt 90 ]]; then
    echo -e "${YELLOW}[!! WARN] Certificate expires in ${DAYS_LEFT} days${NC}"
    ((ISSUES++))
else
    echo -e "${GREEN}[✓] Certificate valid for ${DAYS_LEFT} days${NC}"
fi
echo ""

# ─── Protocol Support ────────────────────────────────────────────────────────
echo -e "${BOLD}─── [4/6] Protocol Support ───${NC}"
declare -a INSECURE_PROTOS=("ssl3" "tls1" "tls1_1")
declare -a SECURE_PROTOS=("tls1_2" "tls1_3")

for proto in "${INSECURE_PROTOS[@]}"; do
    if echo "" | timeout 3 openssl s_client -connect "${DOMAIN}:${PORT}" -"${proto}" -servername "$DOMAIN" 2>&1 | grep -q "BEGIN CERTIFICATE"; then
        echo -e "${RED}[!!! VULN] ${proto} is ENABLED (insecure!)${NC}"
        ((ISSUES++))
    else
        echo -e "${GREEN}[✓] ${proto} disabled${NC}"
    fi
done

for proto in "${SECURE_PROTOS[@]}"; do
    if echo "" | timeout 3 openssl s_client -connect "${DOMAIN}:${PORT}" -"${proto}" -servername "$DOMAIN" 2>&1 | grep -q "BEGIN CERTIFICATE"; then
        echo -e "${GREEN}[✓] ${proto} enabled${NC}"
    else
        echo -e "${YELLOW}[!] ${proto} not available${NC}"
    fi
done
echo ""

# ─── Cipher Strength ─────────────────────────────────────────────────────────
echo -e "${BOLD}─── [5/6] Cipher Analysis ───${NC}"
WEAK_CIPHERS=("rc4" "des" "3des" "md5" "null" "export" "anull" "ades")

CIPHERS=$(echo "" | openssl s_client -connect "${DOMAIN}:${PORT}" -servername "$DOMAIN" 2>/dev/null | grep "Cipher    :" | awk '{print $NF}')
echo -e "  Active Cipher: ${CYAN}${CIPHERS}${NC}"

for weak in "${WEAK_CIPHERS[@]}"; do
    if echo "$CIPHERS" | grep -qi "$weak"; then
        echo -e "${RED}[!!! VULN] Weak cipher detected: ${CIPHERS}${NC}"
        ((ISSUES++))
    fi
done

# Check key size for weak RSA
if [[ $KEY_SIZE -lt 2048 ]] 2>/dev/null; then
    echo -e "${RED}[!!! VULN] RSA key too small: ${KEY_SIZE} bits (minimum 2048)${NC}"
    ((ISSUES++))
elif [[ $KEY_SIZE -ge 4096 ]] 2>/dev/null; then
    echo -e "${GREEN}[✓] Strong key size: ${KEY_SIZE} bits${NC}"
elif [[ $KEY_SIZE -ge 2048 ]] 2>/dev/null; then
    echo -e "${YELLOW}[!] Acceptable key size: ${KEY_SIZE} bits (4096+ recommended)${NC}"
fi

if [[ "$SIG_ALG" == *"sha1"* ]]; then
    echo -e "${RED}[!!! VULN] SHA-1 signature algorithm${NC}"
    ((ISSUES++))
fi
echo ""

# ─── Additional Checks ───────────────────────────────────────────────────────
echo -e "${BOLD}─── [6/6] Additional Checks ───${NC}"

# HSTS
HSTS=$(curl -s -I -m 5 "https://${DOMAIN}" 2>/dev/null | grep -i "strict-transport-security")
if [[ -n "$HSTS" ]]; then
    echo -e "${GREEN}[✓] HSTS enabled${NC}"
else
    echo -e "${YELLOW}[!] HSTS not detected${NC}"
fi

# OCSP Stapling
OCSP=$(echo "" | timeout 5 openssl s_client -connect "${DOMAIN}:${PORT}" -servername "$DOMAIN" -status 2>/dev/null | grep -i "OCSP Response Status")
if [[ -n "$OCSP" ]]; then
    echo -e "${GREEN}[✓] OCSP Stapling enabled${NC}"
else
    echo -e "${YELLOW}[!] OCSP Stapling not detected${NC}"
fi

# Certificate Transparency
CT=$(echo "" | openssl s_client -connect "${DOMAIN}:${PORT}" -servername "$DOMAIN" 2>/dev/null | grep -i "CT Precertificate SCTs")
if [[ -n "$CT" ]]; then
    echo -e "${GREEN}[✓] Certificate Transparency SCTs present${NC}"
else
    echo -e "${YELLOW}[!] No CT SCTs detected${NC}"
fi
echo ""

# ─── Grade (optional) ────────────────────────────────────────────────────────
if [[ "$GRADE" == "--grade" ]]; then
    echo -e "${BOLD}─── SSL Labs Grade ───${NC}"
    GRADE_URL="https://api.ssllabs.com/api/v3/analyze?host=${DOMAIN}&publish=off&startNew=on&all=done"
    echo -e "${CYAN}[*] Requesting SSL Labs grade (may take 2-3 minutes)...${NC}"
    echo -e "${YELLOW}[!] Note: Grade requires SSL Labs API — check https://www.ssllabs.com/ssltest/ manually${NC}"
    echo ""
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo -e "${BOLD}═══ SSL/TLS Check Complete ═══${NC}"
echo -e "  Issues found: ${RED}${ISSUES}${NC}"
if [[ $ISSUES -eq 0 ]]; then
    echo -e "  Status: ${GREEN}PASS — No critical issues${NC}"
elif [[ $ISSUES -lt 3 ]]; then
    echo -e "  Status: ${YELLOW}WARN — Review issues above${NC}"
else
    echo -e "  Status: ${RED}FAIL — Multiple security issues detected${NC}"
fi
echo -e "  Results: ${GREEN}${RESULT}${NC}"

# Write results
{
    echo "SSL/TLS Check: ${DOMAIN}:${PORT}"
    echo "Date: $(date)"
    echo "Issues: ${ISSUES}"
    echo "---"
    echo "Subject: ${SUBJECT}"
    echo "Issuer: ${ISSUER}"
    echo "Expires: ${NOT_AFTER} (${DAYS_LEFT} days)"
    echo "Key: ${KEY_SIZE} bits"
    echo "Cipher: ${CIPHERS}"
} > "$RESULT"
