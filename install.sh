#!/usr/bin/env bash
# install.sh — One-click installer for all bug bounty toolkit dependencies
# Usage: ./install.sh [--all|--minimal]
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
    echo -e "  ${BOLD}Dependency Installer${NC}"
    echo ""
}

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; }
info() { echo -e "${CYAN}[*]${NC} $*"; }

check_root() {
    if [[ $EUID -eq 0 ]]; then
        SUDO=""
    else
        SUDO="sudo"
        warn "Running without root — some installs may need sudo"
    fi
}

install_apt() {
    local pkg="$1"
    if command -v "$pkg" &>/dev/null; then
        log "$pkg already installed"
        return 0
    fi
    info "Installing $pkg..."
    $SUDO apt-get install -y "$pkg" 2>/dev/null && log "$pkg installed" || warn "Failed to install $pkg via apt"
}

install_go_tool() {
    local tool="$1"
    local repo="$2"
    if command -v "$tool" &>/dev/null; then
        log "$tool already installed"
        return 0
    fi
    if ! command -v go &>/dev/null; then
        warn "Go not installed — skipping $tool"
        return 1
    fi
    info "Installing $tool..."
    go install -v "$repo" 2>&1 | tail -1
    if command -v "$tool" &>/dev/null; then
        log "$tool installed"
    else
        warn "$tool installed but not in PATH — add \$(go env GOPATH)/bin to PATH"
    fi
}

install_pip() {
    local tool="$1"
    local pkg="${2:-$1}"
    if command -v "$tool" &>/dev/null; then
        log "$tool already installed"
        return 0
    fi
    info "Installing $tool via pip..."
    pip3 install "$pkg" 2>/dev/null && log "$tool installed" || warn "Failed to install $tool via pip"
}

banner
check_root

# ─── System Packages ──────────────────────────────────────────────────────────
echo -e "${BOLD}═══ System Packages ═══${NC}"

$SUDO apt-get update -qq 2>/dev/null

for pkg in curl wget jq git unzip nmap python3 python3-pip dnsutils whois; do
    install_apt "$pkg"
done
echo ""

# ─── Go Installation ─────────────────────────────────────────────────────────
echo -e "${BOLD}═══ Go Language ═══${NC}"

if ! command -v go &>/dev/null; then
    info "Installing Go..."
    GO_VERSION="1.22.0"
    wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz 2>/dev/null
    $SUDO tar -C /usr/local -xzf /tmp/go.tar.gz 2>/dev/null
    export PATH=$PATH:/usr/local/go/bin:$(go env GOPATH 2>/dev/null)/bin
    echo 'export PATH=$PATH:/usr/local/go/bin:$(go env GOPATH)/bin' >> ~/.bashrc
    rm -f /tmp/go.tar.gz
    log "Go installed"
else
    log "Go already installed ($(go version))"
fi
echo ""

# ─── Recon Tools (Go) ────────────────────────────────────────────────────────
echo -e "${BOLD}═══ Recon Tools (Go) ═══${NC}"

export PATH="$PATH:$(go env GOPATH 2>/dev/null)/bin:/usr/local/bin"

install_go_tool subfinder "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
install_go_tool httpx "github.com/projectdiscovery/httpx/cmd/httpx@latest"
install_go_tool nuclei "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
install_go_tool ffuf "github.com/ffuf/ffuf/v2@latest"
install_go_tool waybackurls "github.com/tomnomnom/waybackurls@latest"
install_go_tool katana "github.com/projectdiscovery/katana/cmd/katana@latest"
install_go_tool dnsx "github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
install_go_tool gau "github.com/lc/gau/v2/cmd/gau@latest"
install_go_tool amass "github.com/owasp-amass/amass/v4/...@master"
install_go_tool assetfinder "github.com/tomnomnom/assetfinder@latest"
echo ""

# ─── Gobuster ─────────────────────────────────────────────────────────────────
echo -e "${BOLD}═══ Gobuster ═══${NC}"
install_go_tool gobuster "github.com/OJ/gobuster/v3@latest"
echo ""

# ─── RustScan (optional) ─────────────────────────────────────────────────────
echo -e "${BOLD}═══ RustScan (optional) ═══${NC}"
if command -v cargo &>/dev/null; then
    install_go_tool rustscan "rustscan" 2>/dev/null || true
    if ! command -v rustscan &>/dev/null; then
        info "Installing rustscan via cargo..."
        cargo install rustscan 2>/dev/null && log "rustscan installed" || warn "rustscan install failed"
    fi
else
    warn "Cargo not found — skipping rustscan (install Rust: https://rustup.rs)"
fi
echo ""

# ─── Python Tools ─────────────────────────────────────────────────────────────
echo -e "${BOLD}═══ Python Tools ═══${NC}"

install_pip dnsrecon
install_pip whatweb
echo ""

# ─── Nuclei Templates ────────────────────────────────────────────────────────
echo -e "${BOLD}═══ Nuclei Templates ═══${NC}"
if command -v nuclei &>/dev/null; then
    info "Updating nuclei templates..."
    nuclei -update-templates 2>/dev/null && log "Nuclei templates updated" || warn "Template update failed"
else
    warn "nuclei not found — skipping template update"
fi
echo ""

# ─── Make Scripts Executable ──────────────────────────────────────────────────
echo -e "${BOLD}═══ Setting Permissions ═══${NC}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
chmod +x "${SCRIPT_DIR}"/*.sh
log "All scripts marked executable"
echo ""

# ─── PATH Setup ───────────────────────────────────────────────────────────────
echo -e "${BOLD}═══ PATH Setup ═══${NC}"
GO_BIN="$(go env GOPATH 2>/dev/null)/bin"
if ! echo "$PATH" | grep -q "$GO_BIN"; then
    echo "export PATH=\"\$PATH:${GO_BIN}\"" >> ~/.bashrc
    warn "Added ${GO_BIN} to PATH in .bashrc — run 'source ~/.bashrc' or restart shell"
fi
echo ""

# ─── Verification ─────────────────────────────────────────────────────────────
echo -e "${BOLD}═══ Installation Verification ═══${NC}"

TOOLS=(subfinder httpx nuclei ffuf gobuster nmap curl jq dig)
INSTALLED=0
TOTAL=${#TOOLS[@]}

for tool in "${TOOLS[@]}"; do
    if command -v "$tool" &>/dev/null; then
        log "$tool"
        ((INSTALLED++))
    else
        err "$tool NOT FOUND"
    fi
done

echo ""
echo -e "${BOLD}═══ Installation Complete ═══${NC}"
echo -e "  Installed: ${GREEN}${INSTALLED}/${TOTAL}${NC} tools"

if [[ $INSTALLED -lt $TOTAL ]]; then
    echo -e "  ${YELLOW}Some tools failed to install — check errors above${NC}"
    echo -e "  ${YELLOW}Try: source ~/.bashrc && $0${NC}"
else
    echo -e "  ${GREEN}All tools installed successfully!${NC}"
fi

echo ""
echo -e "  ${BOLD}Quick start:${NC}"
echo -e "    ${CYAN}./recon.sh example.com${NC}"
echo -e "    ${CYAN}./waf_detector.sh https://example.com${NC}"
echo ""
