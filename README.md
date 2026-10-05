# 🎯 Bug Bounty Toolkit

![License](https://img.shields.io/badge/license-MIT-blue.svg)
[![Last Updated](https://img.shields.io/badge/last%20updated-2026-10-05-blue.svg)](https://github.com/DHO212/bug-bounty-toolkit)
[![Last Updated](https://img.shields.io/badge/last%20updated-2026-09-28-blue.svg)](https://github.com/DHO212/bug-bounty-toolkit)
![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)
![GitHub stars](https://img.shields.io/github/stars/DHO212/bug-bounty-toolkit?style=social)
![GitHub forks](https://img.shields.io/github/forks/DHO212/bug-bounty-toolkit?style=social)

> A comprehensive bug bounty automation toolkit — recon, enumeration, scanning, and analysis in one place.

---

## ⚡ Features

| Module | Description |
|--------|-------------|
| `recon.sh` | Full recon pipeline — subdomain enum, live host check, screenshot, nuclei scan |
| `subdomain_enum.sh` | Multi-tool subdomain enumeration (subfinder, amass, assetfinder, crt.sh) |
| `port_scanner.sh` | Fast port scanning with nmap/rustscan integration |
| `dir_bruteforce.sh` | Directory brute-force via ffuf or gobuster |
| `cors_checker.sh` | CORS misconfiguration detection (pure bash/curl) |
| `ssl_checker.sh` | SSL/TLS configuration audit and vulnerability check |
| `dns_enum.sh` | DNS record enumeration and zone transfer testing |
| `js_extractor.sh` | JavaScript file extraction and endpoint mining |
| `api_discovery.sh` | API endpoint discovery from JS source files |
| `waf_detector.sh` | WAF/CDN detection and identification |
| `install.sh` | One-click dependency installer for all tools |

---

## 🛠 Requirements

- **OS:** Linux (Kali, Parrot, Ubuntu, Debian, etc.) or macOS
- **Shell:** Bash 4+
- **Tools:** Most are auto-installed by `install.sh`. Core: `curl`, `jq`, `dig`

---

## 🚀 Quick Start

```bash
# Clone the repo
git clone https://github.com/DHO212/bug-bounty-toolkit.git
cd bug-bounty-toolkit

# Install all dependencies
chmod +x install.sh
./install.sh

# Run full recon against a target
chmod +x recon.sh
./recon.sh example.com
```

---

## 📖 Usage

### Full Recon Pipeline

```bash
./recon.sh <domain>
```

Runs subdomain enumeration → live host probing → port scanning → directory bruteforce → nuclei scan → JS extraction → report generation. Output saved to `results/<domain>/`.

### Subdomain Enumeration

```bash
./subdomain_enum.sh <domain>          # Run all tools
./subdomain_enum.sh <domain> --crtsh  # crt.sh only
./subdomain_enum.sh <domain> --merge  # Merge all results, deduplicate
```

### Port Scanning

```bash
./port_scanner.sh <target>            # Top 1000 ports
./port_scanner.sh <target> --full     # All 65535 ports
./port_scanner.sh <target> -p 80,443,8080  # Custom ports
```

### Directory Bruteforce

```bash
./dir_bruteforce.sh <url>                        # Default wordlist
./dir_bruteforce.sh <url> -w wordlists/large.txt # Custom wordlist
./dir_bruteforce.sh <url> -x php,html,js         # File extensions
```

### CORS Checker

```bash
./cors_checker.sh <url>              # Check with default payloads
./cors_checker.sh <url> --verbose    # Verbose output
```

### SSL/TLS Checker

```bash
./ssl_checker.sh <domain>            # Basic SSL check
./ssl_checker.sh <domain> --grade    # Get letter grade
```

### DNS Enumeration

```bash
./dns_enum.sh <domain>               # Full DNS enum
./dns_enum.sh <domain> --axfr        # Zone transfer test
```

### JavaScript Endpoint Extraction

```bash
./js_extractor.sh <url>              # Extract endpoints from page JS
./js_extractor.sh <url> --crawl      # Crawl JS links recursively
```

### API Discovery

```bash
./api_discovery.sh <url>             # Discover API endpoints from JS
./api_discovery.sh <url> --depth 3   # Crawl depth
```

### WAF Detection

```bash
./waf_detector.sh <url>              # Detect WAF/CDN
./waf_detector.sh <url> --probe      # Full probe with payloads
```

---

## 📁 Directory Structure

```
bug-bounty-toolkit/
├── README.md
├── LICENSE
├── install.sh              # One-click installer
├── recon.sh                # Full recon pipeline
├── subdomain_enum.sh       # Subdomain enumeration
├── port_scanner.sh         # Port scanning
├── dir_bruteforce.sh       # Directory bruteforce
├── cors_checker.sh         # CORS misconfiguration check
├── ssl_checker.sh          # SSL/TLS audit
├── dns_enum.sh             # DNS enumeration
├── js_extractor.sh         # JS endpoint extraction
├── api_discovery.sh        # API discovery from JS
├── waf_detector.sh         # WAF detection
├── wordlists/
│   ├── small.txt           # ~1,000 common paths
│   ├── medium.txt          # ~10,000 paths
│   └── large.txt           # ~50,000+ paths
└── results/                # Output directory (auto-created)
```

---

## 🎯 Supported Tools Integration

This toolkit leverages the following open-source tools (installed via `install.sh`):

| Tool | Purpose |
|------|---------|
| [subfinder](https://github.com/projectdiscovery/subfinder) | Subdomain enumeration |
| [httpx](https://github.com/projectdiscovery/httpx) | HTTP probing |
| [nuclei](https://github.com/projectdiscovery/nuclei) | Vulnerability scanning |
| [ffuf](https://github.com/ffuf/ffuf) | Directory bruteforce |
| [gobuster](https://github.com/OJ/gobuster) | Directory/DNS bruteforce |
| [amass](https://github.com/owasp-amass/amass) | Attack surface mapping |
| [rustscan](https://github.com/RustScan/RustScan) | Fast port scanner |
| [waybackurls](https://github.com/tomnomnom/waybackurls) | Wayback Machine URLs |
| [katana](https://github.com/projectdiscovery/katana) | Web crawler |
| [dnsx](https://github.com/projectdiscovery/dnsx) | DNS toolkit |

---

## ⚠️ Disclaimer

This toolkit is for **authorized security testing and educational purposes only**. Users are responsible for obtaining proper authorization before testing any target. Unauthorized access to computer systems is illegal. The authors assume no liability for misuse.

---

## 🤝 Contributing

Contributions welcome. Open an issue or submit a PR.

## 📜 License

MIT License — see [LICENSE](LICENSE) for details.

---

<p align="center">
  <b>⚡ Built for bug bounty hunters, by bug bounty hunters ⚡</b>
</p>


---


<!-- TOOLS_HEALTH_START -->
## 🔍 Tool Health Status

| Check Date | Status |
|------------|--------|
| Last Checked | **2026-10-05** |
| Checked By | [GitHub Actions](https://github.com/DHO212/bug-bounty-toolkit/actions) |
<!-- TOOLS_HEALTH_END -->

---

<!-- WEEKLY_STATS_START -->
## 📊 Weekly Stats

| Metric | Value |
|--------|-------|
| Tools Referenced | **14** |
| Last Updated | **2026-10-05** |
<!-- WEEKLY_STATS_END -->
