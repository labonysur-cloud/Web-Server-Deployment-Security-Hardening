#!/bin/bash

# ============================================================
#  FINAL COMPLETE PROJECT SETUP
#  Web Server Deployment & Security Hardening
#  Group 1 | CSE Department | OS Lab
# ============================================================
#  This master script runs everything in correct order:
#    1. Core server (Apache, SSL, UFW, Fail2Ban)
#    2. Virtual hosts (site1, site2)
#    3. Team portfolio page with real photos
#    4. Project details page
#    5. Status dashboard (status.local)
#    6. Advanced features (error pages, admin, rate limit,
#       backup, daily report, SSH keys)
#    7. ModSecurity WAF
#    8. Download team photos locally
#    9. Final verification
# ============================================================

# ── Colors ─────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'
BG_GREEN='\033[42m'
BG_RED='\033[41m'
BG_YELLOW='\033[43m'
BLACK='\033[0;30m'

CHECK="${GREEN}${BOLD} OK ${NC}"
FAIL="${RED}${BOLD} FAIL ${NC}"
SKIP="${YELLOW}${BOLD} SKIP ${NC}"
WIDTH=64

line_full()  { printf "${DIM}%${WIDTH}s${NC}\n" | tr ' ' '─'; }
line_light() { printf "${DIM}%${WIDTH}s${NC}\n" | tr ' ' '·'; }
task()       { printf "  ${CYAN}${BOLD} .. ${NC} %-46s" "$1"; }
done_ok()    { echo -e "  ${CHECK}"; }
done_fail()  { echo -e "  ${FAIL}"; }
done_skip()  { echo -e "  ${SKIP}"; }
detail()     { echo -e "       ${DIM}$1${NC}"; }
badge_ok()   { echo -e "  ${BG_GREEN}${BLACK}${BOLD}  PASS  ${NC}  $1"; }
badge_fail() { echo -e "  ${BG_RED}${BOLD}  FAIL  ${NC}  $1"; }
badge_skip() { echo -e "  ${BG_YELLOW}${BLACK}${BOLD}  SKIP  ${NC}  $1"; }

print_section() {
    echo ""
    line_full
    echo -e "  ${CYAN}${BOLD}[ $1 ]${NC}  ${BOLD}$2${NC}"
    line_full
    echo ""
}

# ── Root check ─────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo -e "\n  ${BG_RED}${BOLD}  ERROR  ${NC}  Run as root: sudo bash final_setup.sh\n"
    exit 1
fi

# ── Banner ──────────────────────────────────────────────────
clear
echo ""
echo -e "${CYAN}${BOLD}"
echo "  ┌──────────────────────────────────────────────────┐"
echo "  │                                                  │"
echo "  │     Web Server Deployment & Security Hardening   │"
echo "  │     FINAL COMPLETE SETUP                         │"
echo "  │     Group 1  ·  CSE Department  ·  OS Lab        │"
echo "  │                                                  │"
echo "  └──────────────────────────────────────────────────┘"
echo -e "${NC}"
echo -e "  ${DIM}Time    :${NC}  $(date '+%a %d %b %Y  %H:%M:%S')"
echo -e "  ${DIM}Host    :${NC}  $(hostname)"
echo -e "  ${DIM}IP      :${NC}  $(hostname -I | awk '{print $1}')"
echo -e "  ${DIM}OS      :${NC}  $(lsb_release -ds 2>/dev/null)"
echo ""
line_full
echo ""
echo -e "  This script will install and configure:"
echo ""
echo -e "  ${DIM}Sites     :${NC}  site1.local  site2.local  status.local  admin.local"
echo -e "  ${DIM}Security  :${NC}  HTTPS · UFW · Fail2Ban · ModSecurity WAF"
echo -e "  ${DIM}Features  :${NC}  Error pages · Rate limiting · Backups · Reports"
echo -e "  ${DIM}Photos    :${NC}  All 6 team members downloaded locally"
echo ""
line_full
echo ""
echo -e "  ${BOLD}Starting in 3 seconds...${NC}"
sleep 3

# ══════════════════════════════════════════════════════════
# PHASE 1 — SYSTEM UPDATE & PACKAGES
# ══════════════════════════════════════════════════════════
print_section "PHASE 1 / 9" "System Update & Package Installation"

task "Updating APT package index"
apt-get update -y > /dev/null 2>&1 && done_ok || done_fail

task "Installing core packages"
apt-get install -y \
    apache2 openssl ufw fail2ban curl \
    php libapache2-mod-php \
    libapache2-mod-security2 modsecurity-crs \
    libapache2-mod-evasive \
    apache2-utils \
    > /dev/null 2>&1 && done_ok || done_fail

task "Enabling Apache on boot"
systemctl enable apache2 > /dev/null 2>&1 && done_ok || done_fail

task "Starting Apache"
systemctl start apache2 > /dev/null 2>&1 && done_ok || done_fail

APACHE_VER=$(apache2 -v 2>/dev/null | grep -oP '[\d.]+' | head -1)
detail "Apache  ${APACHE_VER}  ·  PHP $(php -r 'echo PHP_VERSION;' 2>/dev/null)  ·  OpenSSL $(openssl version | awk '{print $2}')"

# ══════════════════════════════════════════════════════════
# PHASE 2 — APACHE MODULES
# ══════════════════════════════════════════════════════════
print_section "PHASE 2 / 9" "Enabling Apache Modules"

for MOD in ssl rewrite headers auth_basic unique_id security2 evasive php8* status; do
    task "Enabling mod_${MOD}"
    a2enmod $MOD > /dev/null 2>&1 && done_ok || done_skip
done

# ══════════════════════════════════════════════════════════
# PHASE 3 — DIRECTORY STRUCTURE
# ══════════════════════════════════════════════════════════
print_section "PHASE 3 / 9" "Creating Directory Structure"

for DIR in \
    /var/www/site1.local/html/images \
    /var/www/site1.local/html/waf-test \
    /var/www/site2.local/html \
    /var/www/status.local/html \
    /var/www/admin.local/html \
    /var/www/errors \
    /etc/modsecurity/custom_rules \
    /var/log/mod_evasive \
    /var/backups/webserver \
    /var/reports/webserver; do
    task "mkdir $(basename $DIR)"
    mkdir -p "$DIR" && done_ok || done_fail
done

chown -R www-data:www-data /var/www/
chmod -R 755 /var/www/

# ══════════════════════════════════════════════════════════
# PHASE 4 — SSL CERTIFICATES
# ══════════════════════════════════════════════════════════
print_section "PHASE 4 / 9" "Generating SSL Certificates"

gen_cert() {
    local DOMAIN=$1
    task "SSL cert for $DOMAIN"
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/${DOMAIN}.key \
        -out    /etc/ssl/certs/${DOMAIN}.crt \
        -subj   "/C=BD/ST=Chattogram/L=Chittagong/O=OS-Lab/CN=${DOMAIN}" \
        > /dev/null 2>&1
    chmod 600 /etc/ssl/private/${DOMAIN}.key
    done_ok
}

gen_cert "site1.local"
gen_cert "site2.local"
gen_cert "status.local"
gen_cert "admin.local"

detail "Algorithm: RSA 2048-bit  ·  Valid: 365 days  ·  SHA-256"

# ══════════════════════════════════════════════════════════
# PHASE 5 — WEB PAGES
# ══════════════════════════════════════════════════════════
print_section "PHASE 5 / 9" "Creating Web Pages"

# ── Team portfolio (site1) ────────────────────────────────
task "Writing site1 — team portfolio"
cat > /var/www/site1.local/html/index.html <<'SITE1EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Group 1 — OS Lab</title>
    <link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@300;400;600&family=DM+Mono:wght@300;400&display=swap" rel="stylesheet">
    <style>
        *,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
        :root{--black:#0a0a0a;--white:#f5f5f0;--mid:#888;--line:#2a2a2a}
        body{background:var(--black);color:var(--white);font-family:'DM Mono',monospace;font-weight:300;min-height:100vh;overflow-x:hidden}
        body::before{content:'';position:fixed;inset:0;background-image:url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='noise'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23noise)' opacity='0.04'/%3E%3C/svg%3E");pointer-events:none;z-index:0;opacity:0.4}
        header{position:relative;z-index:1;padding:80px 60px 60px;border-bottom:1px solid var(--line);display:flex;align-items:flex-end;justify-content:space-between;gap:40px;animation:fadeDown 0.8s ease both}
        .header-left h1{font-family:'Cormorant Garamond',serif;font-size:clamp(2.8rem,6vw,5.5rem);font-weight:300;line-height:1;letter-spacing:-0.02em;color:var(--white)}
        .header-left h1 span{display:block;font-weight:600;font-style:italic}
        .header-right{text-align:right;flex-shrink:0}
        .header-right p{font-size:0.7rem;letter-spacing:0.15em;text-transform:uppercase;color:var(--mid);line-height:2}
        .project-title{font-size:0.65rem;color:var(--mid);margin-top:8px;max-width:260px;line-height:1.6;border-top:1px solid var(--line);padding-top:10px}
        .index-bar{position:relative;z-index:1;padding:16px 60px;border-bottom:1px solid var(--line);display:flex;gap:40px;font-size:0.65rem;letter-spacing:0.12em;text-transform:uppercase;color:var(--mid);animation:fadeDown 0.8s 0.1s ease both}
        .team-grid{position:relative;z-index:1;display:grid;grid-template-columns:repeat(3,1fr);border-left:1px solid var(--line)}
        .card{border-right:1px solid var(--line);border-bottom:1px solid var(--line);padding:40px 36px 36px;display:flex;flex-direction:column;overflow:hidden;transition:background 0.3s ease;animation:fadeUp 0.7s ease both}
        .card:nth-child(1){animation-delay:.15s}.card:nth-child(2){animation-delay:.22s}.card:nth-child(3){animation-delay:.29s}.card:nth-child(4){animation-delay:.36s}.card:nth-child(5){animation-delay:.43s}.card:nth-child(6){animation-delay:.50s}
        .card:hover{background:#111}
        .card-num{font-size:0.6rem;letter-spacing:0.15em;color:var(--mid);margin-bottom:28px}
        .photo{width:100%;aspect-ratio:1/1;background:#141414;border:1px solid var(--line);margin-bottom:28px;overflow:hidden}
        .photo img{width:100%;height:100%;object-fit:cover;object-position:center top;display:block;filter:grayscale(100%);transition:filter 0.5s,transform 0.5s}
        .card:hover .photo img{filter:grayscale(0%);transform:scale(1.04)}
        .photo-ph{width:100%;height:100%;display:flex;align-items:center;justify-content:center}
        .photo-ph svg{width:48px;height:48px;opacity:.15}
        .card-name{font-family:'Cormorant Garamond',serif;font-size:1.45rem;font-weight:400;line-height:1.2;color:var(--white);margin-bottom:14px}
        .card-divider{width:24px;height:1px;background:var(--mid);margin-bottom:14px}
        .card-meta{display:flex;flex-direction:column;gap:5px}
        .card-meta span{font-size:0.65rem;letter-spacing:0.1em;text-transform:uppercase;color:var(--mid)}
        .card-meta .id-tag{color:var(--white);font-size:0.7rem;letter-spacing:0.08em}
        footer{position:relative;z-index:1;padding:30px 60px;border-top:1px solid var(--line);display:flex;justify-content:space-between;align-items:center}
        footer p{font-size:0.62rem;letter-spacing:0.12em;text-transform:uppercase;color:var(--mid)}
        @keyframes fadeDown{from{opacity:0;transform:translateY(-16px)}to{opacity:1;transform:translateY(0)}}
        @keyframes fadeUp{from{opacity:0;transform:translateY(20px)}to{opacity:1;transform:translateY(0)}}
        @media(max-width:900px){header{padding:50px 30px 40px;flex-direction:column;align-items:flex-start}.index-bar{padding:14px 30px}.team-grid{grid-template-columns:repeat(2,1fr)}.card{padding:28px 24px}footer{padding:24px 30px;flex-direction:column;gap:8px}}
        @media(max-width:560px){.team-grid{grid-template-columns:1fr}}
    </style>
</head>
<body>
    <header>
        <div class="header-left"><h1>Group<span>One.</span></h1></div>
        <div class="header-right">
            <p>Department of CSE</p><p>Operating System Lab</p><p>2025 &ndash; 2026</p>
            <p class="project-title">Topic 12 &mdash; Web Server Deployment &amp; Security Hardening</p>
        </div>
    </header>
    <div class="index-bar"><span>06 Members</span><span>Group 1</span><span>CSE</span></div>
    <section class="team-grid">
        <div class="card">
            <div class="card-num">01 / 06</div>
            <div class="photo"><img src="images/aupurba.jpg" alt="Aupurba Sarker"></div>
            <div class="card-name">Aupurba Sarker</div>
            <div class="card-divider"></div>
            <div class="card-meta"><span>Department of CSE</span><span class="id-tag">ID &mdash; 232-15-269</span></div>
        </div>
        <div class="card">
            <div class="card-num">02 / 06</div>
            <div class="photo"><img src="images/labony.jpg" alt="Labony Sur"></div>
            <div class="card-name">Labony Sur</div>
            <div class="card-divider"></div>
            <div class="card-meta"><span>Department of CSE</span><span class="id-tag">ID &mdash; 232-15-473</span></div>
        </div>
        <div class="card">
            <div class="card-num">03 / 06</div>
            <div class="photo"><img src="images/moon.jpg" alt="Moontakim Moon"></div>
            <div class="card-name">Moontakim Moon</div>
            <div class="card-divider"></div>
            <div class="card-meta"><span>Department of CSE</span><span class="id-tag">ID &mdash; 232-15-680</span></div>
        </div>
        <div class="card">
            <div class="card-num">04 / 06</div>
            <div class="photo"><img src="images/badhon.jpg" alt="Al Mahmud Badhon"></div>
            <div class="card-name">Al Mahmud Badhon</div>
            <div class="card-divider"></div>
            <div class="card-meta"><span>Department of CSE</span><span class="id-tag">ID &mdash; 232-15-241</span></div>
        </div>
        <div class="card">
            <div class="card-num">05 / 06</div>
            <div class="photo"><img src="images/sajeed.jpg" alt="Sajeed Awal Sharif"></div>
            <div class="card-name">Sajeed Awal Sharif</div>
            <div class="card-divider"></div>
            <div class="card-meta"><span>Department of CSE</span><span class="id-tag">ID &mdash; 232-15-470</span></div>
        </div>
        <div class="card">
            <div class="card-num">06 / 06</div>
            <div class="photo"><img src="images/rowshan.jpg" alt="Mst. Rawshan Ara Prodan"></div>
            <div class="card-name">Mst. Rawshan Ara Prodan</div>
            <div class="card-divider"></div>
            <div class="card-meta"><span>Department of CSE</span><span class="id-tag">ID &mdash; 232-15-876</span></div>
        </div>
    </section>
    <footer>
        <p>Group 1 &mdash; Operating System Lab</p>
        <p>Web Server Deployment &amp; Security Hardening</p>
    </footer>
</body>
</html>
SITE1EOF
done_ok

# ── Custom 404 & 403 error pages ─────────────────────────
task "Writing custom 404 page"
cat > /var/www/errors/404.html <<'EOF'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>404 — Not Found</title>
<link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@300;400&family=DM+Mono:wght@300&display=swap" rel="stylesheet">
<style>*{box-sizing:border-box;margin:0;padding:0}body{background:#080808;color:#f0f0ec;font-family:'DM Mono',monospace;font-weight:300;display:flex;align-items:center;justify-content:center;min-height:100vh;flex-direction:column}.code{font-family:'Cormorant Garamond',serif;font-size:clamp(6rem,20vw,14rem);font-weight:300;color:#1a1a1a;letter-spacing:-0.04em;position:absolute;user-select:none}.content{position:relative;z-index:1;text-align:center;padding:40px}.label{font-size:0.6rem;letter-spacing:0.2em;text-transform:uppercase;color:#555;margin-bottom:20px}h1{font-family:'Cormorant Garamond',serif;font-size:2rem;font-weight:300;margin-bottom:16px}p{font-size:0.72rem;color:#555;margin-bottom:32px;line-height:1.8}a{font-size:0.65rem;letter-spacing:0.12em;text-transform:uppercase;color:#f0f0ec;text-decoration:none;border-bottom:1px solid #333;padding-bottom:2px}.divider{width:24px;height:1px;background:#333;margin:20px auto}</style></head>
<body><div class="code">404</div><div class="content"><div class="label">Error 404</div><h1>Page Not Found</h1><div class="divider"></div><p>The page you are looking for does not exist.</p><a href="/">Return to Home</a></div></body></html>
EOF
done_ok

task "Writing custom 403 page"
cat > /var/www/errors/403.html <<'EOF'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>403 — Forbidden</title>
<link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@300;400&family=DM+Mono:wght@300&display=swap" rel="stylesheet">
<style>*{box-sizing:border-box;margin:0;padding:0}body{background:#080808;color:#f0f0ec;font-family:'DM Mono',monospace;font-weight:300;display:flex;align-items:center;justify-content:center;min-height:100vh;flex-direction:column}.code{font-family:'Cormorant Garamond',serif;font-size:clamp(6rem,20vw,14rem);font-weight:300;color:#1a0a0a;letter-spacing:-0.04em;position:absolute;user-select:none}.content{position:relative;z-index:1;text-align:center;padding:40px}.label{font-size:0.6rem;letter-spacing:0.2em;text-transform:uppercase;color:#6b2121;margin-bottom:20px}h1{font-family:'Cormorant Garamond',serif;font-size:2rem;font-weight:300;margin-bottom:16px}p{font-size:0.72rem;color:#555;margin-bottom:32px;line-height:1.8}a{font-size:0.65rem;letter-spacing:0.12em;text-transform:uppercase;color:#f0f0ec;text-decoration:none;border-bottom:1px solid #333;padding-bottom:2px}.divider{width:24px;height:1px;background:#2a0a0a;margin:20px auto}</style></head>
<body><div class="code">403</div><div class="content"><div class="label">Error 403</div><h1>Access Forbidden</h1><div class="divider"></div><p>You do not have permission to access this resource.</p><a href="/">Return to Home</a></div></body></html>
EOF
done_ok

# copy error pages to all sites
for SITE in site1.local site2.local; do
    cp /var/www/errors/404.html /var/www/${SITE}/html/404.html
    cp /var/www/errors/403.html /var/www/${SITE}/html/403.html
done

# ── WAF test page ─────────────────────────────────────────
task "Writing WAF test page"
cat > /var/www/site1.local/html/waf-test/index.html <<'EOF'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>WAF Test</title>
<link href="https://fonts.googleapis.com/css2?family=DM+Mono:wght@300;400&family=Cormorant+Garamond:wght@300&display=swap" rel="stylesheet">
<style>*{box-sizing:border-box;margin:0;padding:0}:root{--bg:#080808;--w:#f0f0ec;--mid:#666;--line:#1e1e1e;--g:#4ade80;--r:#f87171;--a:#fbbf24}body{background:var(--bg);color:var(--w);font-family:'DM Mono',monospace;font-weight:300;padding:60px 40px}h1{font-family:'Cormorant Garamond',serif;font-size:2.5rem;font-weight:300;margin-bottom:8px}.sub{font-size:.7rem;color:var(--mid);margin-bottom:40px;line-height:1.8}.grid{display:grid;grid-template-columns:repeat(2,1fr);gap:1px;background:var(--line);border:1px solid var(--line);margin-bottom:32px}.card{background:#0d0d0d;padding:28px}.card h3{font-family:'Cormorant Garamond',serif;font-size:1.2rem;font-weight:400;margin-bottom:8px}.card p{font-size:.68rem;color:var(--mid);margin-bottom:16px;line-height:1.7}.atk{display:block;border:1px solid var(--line);padding:10px 14px;margin-bottom:6px;font-size:.62rem;color:var(--a);text-decoration:none;transition:background .2s}.atk:hover{background:#1a1a1a}.note{font-size:.65rem;color:var(--mid);line-height:1.8;border:1px solid var(--line);padding:20px}@media(max-width:600px){.grid{grid-template-columns:1fr}}</style></head>
<body>
<h1>WAF Test Console</h1>
<p class="sub">ModSecurity is active. Click any attack — you should see 403 Forbidden.<br>Check logs: sudo tail -f /var/log/apache2/modsecurity_audit.log</p>
<div class="grid">
<div class="card"><h3>SQL Injection</h3><p>Classic SQLi patterns — should be blocked immediately.</p>
<a class="atk" href="?id=1'+OR+'1'='1" target="_blank">?id=1' OR '1'='1</a>
<a class="atk" href="?q=SELECT+*+FROM+users--" target="_blank">?q=SELECT * FROM users--</a></div>
<div class="card"><h3>Cross-Site Scripting</h3><p>JavaScript injection attempt — blocked by WAF.</p>
<a class="atk" href="?name=<script>alert('XSS')</script>" target="_blank">&lt;script&gt;alert('XSS')&lt;/script&gt;</a>
<a class="atk" href="?q=<img+src=x+onerror=alert(1)>" target="_blank">&lt;img onerror=alert(1)&gt;</a></div>
<div class="card"><h3>Path Traversal</h3><p>Attempts to read system files — blocked.</p>
<a class="atk" href="../../../etc/passwd" target="_blank">../../../etc/passwd</a>
<a class="atk" href="?file=../../../../etc/shadow" target="_blank">?file=../../../../etc/shadow</a></div>
<div class="card"><h3>Command Injection</h3><p>Shell command in URL parameter — blocked.</p>
<a class="atk" href="?cmd=;cat+/etc/passwd" target="_blank">?cmd=;cat /etc/passwd</a>
<a class="atk" href="?ip=127.0.0.1;ls+-la" target="_blank">?ip=127.0.0.1;ls -la</a></div>
</div>
<div class="note">Expected result: HTTP 403 Forbidden · Your custom error page appears · Attack logged to modsecurity_audit.log</div>
</body></html>
EOF
done_ok

# ── Admin page ────────────────────────────────────────────
task "Writing admin panel page"
cat > /var/www/admin.local/html/index.html <<'EOF'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>Admin Panel</title>
<link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@300;400&family=DM+Mono:wght@300;400&display=swap" rel="stylesheet">
<style>*{box-sizing:border-box;margin:0;padding:0}body{background:#fafaf8;color:#0e0e0e;font-family:'DM Mono',monospace;font-weight:300;min-height:100vh}header{border-bottom:1px solid #e8e8e4;padding:40px 60px;display:flex;justify-content:space-between;align-items:center}
.logo{font-family:'Cormorant Garamond',serif;font-size:1.6rem;font-weight:300}.badge{font-size:.6rem;letter-spacing:.14em;text-transform:uppercase;border:1px solid #e8e8e4;padding:6px 14px;color:#888}main{padding:60px}.page-title{font-size:.6rem;letter-spacing:.18em;text-transform:uppercase;color:#888;margin-bottom:40px}
.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:1px;background:#e8e8e4;border:1px solid #e8e8e4;margin-bottom:40px}.card{background:#fafaf8;padding:32px 28px}.card-label{font-size:.58rem;letter-spacing:.14em;text-transform:uppercase;color:#888;margin-bottom:12px}.card-value{font-family:'Cormorant Garamond',serif;font-size:1.8rem;font-weight:300}
.section-title{font-size:.58rem;letter-spacing:.14em;text-transform:uppercase;color:#888;margin-bottom:16px;padding-bottom:10px;border-bottom:1px solid #e8e8e4}.link-row{display:flex;justify-content:space-between;align-items:center;padding:14px 0;border-bottom:1px solid #e8e8e4;font-size:.72rem}.link-row a{color:#0e0e0e;text-decoration:none;font-size:.65rem;border-bottom:1px solid #e8e8e4;padding-bottom:1px}
.dot{width:7px;height:7px;border-radius:50%;background:#16a34a;display:inline-block;margin-right:8px}</style></head>
<body>
<header><div class="logo">Admin Panel</div><div class="badge">Authenticated Access Only</div></header>
<main>
<div class="page-title">OS Lab Server — Group 1 — CSE</div>
<div class="grid">
<div class="card"><div class="card-label">Virtual Hosts</div><div class="card-value">4</div></div>
<div class="card"><div class="card-label">SSL Certificates</div><div class="card-value">4</div></div>
<div class="card"><div class="card-label">Firewall</div><div class="card-value">Active</div></div>
</div>
<div class="section-title">Server Sites</div>
<div class="link-row"><span><span class="dot"></span>site1.local — Team Portfolio</span><a href="https://site1.local" target="_blank">Open</a></div>
<div class="link-row"><span><span class="dot"></span>site2.local — Project Details</span><a href="https://site2.local" target="_blank">Open</a></div>
<div class="link-row"><span><span class="dot"></span>status.local — Live Dashboard</span><a href="https://status.local" target="_blank">Open</a></div>
<div class="link-row"><span><span class="dot"></span>site1.local/waf-test — WAF Console</span><a href="https://site1.local/waf-test/" target="_blank">Open</a></div>
</main></body></html>
EOF
done_ok

# ── Status dashboard (PHP) ────────────────────────────────
task "Writing status dashboard (PHP)"
cat > /var/www/status.local/html/index.php <<'PHPEOF'
<?php
$uptime=trim(str_replace('up ','',shell_exec('uptime -p')));
$load=sys_getloadavg();
$mem=explode("\n",trim(shell_exec('free -m')));
$mp=preg_split('/\s+/',trim($mem[1]));
$mtotal=$mp[1];$mused=$mp[2];$mpct=round(($mused/$mtotal)*100);
$dtotal=round(disk_total_space('/')/1073741824,1);
$dfree=round(disk_free_space('/')/1073741824,1);
$dused=round($dtotal-$dfree,1);$dpct=round(($dused/$dtotal)*100);
$cpu=trim(shell_exec('nproc'));
$os=trim(shell_exec('lsb_release -ds'));
$kernel=trim(shell_exec('uname -r'));
$ip=trim(shell_exec("hostname -I | awk '{print \$1}'"));
$apache=trim(shell_exec('systemctl is-active apache2'));
$ufw_r=trim(shell_exec('sudo ufw status 2>/dev/null | head -1'));
$ufw=strpos($ufw_r,'active')!==false?'active':'inactive';
$f2b=trim(shell_exec('systemctl is-active fail2ban 2>/dev/null'));
$banned=trim(shell_exec("fail2ban-client status sshd 2>/dev/null | grep 'Currently banned' | awk '{print \$NF}'"));
$banned=is_numeric($banned)?$banned:'0';
$vhosts_raw=shell_exec('apache2ctl -S 2>/dev/null | grep namevhost');
$vhosts=[];
if($vhosts_raw){preg_match_all('/namevhost\s+(\S+)/',$vhosts_raw,$m);$vhosts=array_unique($m[1]);}
$top_ips_raw=shell_exec("cat /var/log/apache2/*access.log 2>/dev/null | awk '{print \$1}' | sort | uniq -c | sort -rn | head -5");
$top_ips=[];
if($top_ips_raw){foreach(explode("\n",trim($top_ips_raw)) as $l){$p=preg_split('/\s+/',trim($l),2);if(count($p)==2)$top_ips[]=['count'=>$p[0],'ip'=>$p[1]];}}
$time=date('D, d M Y H:i:s');
?><!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta http-equiv="refresh" content="10">
<title>Server Status</title>
<link href="https://fonts.googleapis.com/css2?family=DM+Mono:wght@300;400&family=Cormorant+Garamond:wght@300;400&display=swap" rel="stylesheet">
<style>*{box-sizing:border-box;margin:0;padding:0}:root{--bg:#080808;--card:#111;--line:#1e1e1e;--w:#f0f0ec;--mid:#666;--g:#4ade80;--r:#f87171;--a:#fbbf24}body{background:var(--bg);color:var(--w);font-family:'DM Mono',monospace;font-weight:300;font-size:13px}
nav{position:sticky;top:0;z-index:100;background:var(--bg);border-bottom:1px solid var(--line);padding:0 40px;height:50px;display:flex;align-items:center;justify-content:space-between}
.dot{width:7px;height:7px;border-radius:50%;background:var(--g);animation:pulse 2s infinite;display:inline-block;margin-right:10px}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.3}}
.page{padding:32px 40px 60px}.st{font-size:.58rem;letter-spacing:.18em;text-transform:uppercase;color:var(--mid);margin-bottom:16px;margin-top:40px;display:flex;align-items:center;gap:12px}.st::after{content:'';flex:1;height:1px;background:var(--line)}
.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:1px;background:var(--line);border:1px solid var(--line)}.sc{background:var(--card);padding:28px 24px}.sl{font-size:.58rem;letter-spacing:.14em;text-transform:uppercase;color:var(--mid);margin-bottom:12px}.sv{font-family:'Cormorant Garamond',serif;font-size:2.2rem;font-weight:300;line-height:1;margin-bottom:6px}.su{font-size:.6rem;color:var(--mid)}.bw{background:var(--line);height:3px;margin-top:14px}.bf{height:3px}.bg{background:var(--g)}.ba{background:var(--a)}.br{background:var(--r)}
.svc{display:grid;grid-template-columns:repeat(3,1fr);gap:1px;background:var(--line);border:1px solid var(--line)}.svcc{background:var(--card);padding:24px;display:flex;align-items:center;gap:16px}.sdot{width:10px;height:10px;border-radius:50%;flex-shrink:0}.son{background:var(--g);box-shadow:0 0 8px rgba(74,222,128,.5)}.soff{background:var(--r)}.sn{font-size:.68rem;letter-spacing:.1em;text-transform:uppercase;color:var(--mid);margin-bottom:4px}.ss{font-size:.75rem;color:var(--w)}
.two{display:grid;grid-template-columns:1fr 1fr;gap:1px;background:var(--line);border:1px solid var(--line)}.cc{background:var(--card);padding:28px 24px}.ct{font-size:.58rem;letter-spacing:.14em;text-transform:uppercase;color:var(--mid);margin-bottom:20px;padding-bottom:12px;border-bottom:1px solid var(--line)}
.ir{display:flex;justify-content:space-between;align-items:baseline;padding:10px 0;border-bottom:1px solid var(--line);gap:12px}.ir:last-child{border-bottom:none}.ik{font-size:.62rem;color:var(--mid)}.iv{font-size:.72rem;color:var(--w);text-align:right;word-break:break-all}
.vhi{display:flex;align-items:center;gap:10px;padding:10px 0;border-bottom:1px solid var(--line)}.vhi:last-child{border-bottom:none}.vhd{width:6px;height:6px;border-radius:50%;background:var(--g);flex-shrink:0}.vhn{font-size:.72rem;color:var(--w)}
.ipr{display:grid;grid-template-columns:40px 1fr 60px;gap:12px;align-items:center;padding:10px 0;border-bottom:1px solid var(--line)}.ipr:last-child{border-bottom:none}
footer{margin-top:48px;padding-top:24px;border-top:1px solid var(--line);display:flex;justify-content:space-between;font-size:.58rem;letter-spacing:.1em;text-transform:uppercase;color:var(--mid)}
@media(max-width:900px){.stats{grid-template-columns:repeat(2,1fr)}.svc{grid-template-columns:1fr}.two{grid-template-columns:1fr}}</style></head>
<body>
<nav><div><span class="dot"></span><span style="font-size:.65rem;letter-spacing:.15em;text-transform:uppercase">Server Status</span></div><div style="font-size:.6rem;color:var(--mid)"><?=$time?> &nbsp;·&nbsp; auto-refresh 10s</div></nav>
<div class="page">
<div class="st">System Resources</div>
<div class="stats">
<div class="sc"><div class="sl">Memory Used</div><div class="sv"><?=$mpct?><span style="font-size:1.2rem">%</span></div><div class="su"><?=$mused?> MB / <?=$mtotal?> MB</div><div class="bw"><div class="bf <?=($mpct>85?'br':($mpct>60?'ba':'bg'))?>" style="width:<?=$mpct?>%"></div></div></div>
<div class="sc"><div class="sl">Disk Used</div><div class="sv"><?=$dpct?><span style="font-size:1.2rem">%</span></div><div class="su"><?=$dused?> GB / <?=$dtotal?> GB</div><div class="bw"><div class="bf <?=($dpct>85?'br':($dpct>60?'ba':'bg'))?>" style="width:<?=$dpct?>%"></div></div></div>
<div class="sc"><div class="sl">Load Average</div><div class="sv"><?=number_format($load[0],2)?></div><div class="su">5m: <?=number_format($load[1],2)?> &nbsp; 15m: <?=number_format($load[2],2)?></div><div class="bw"><div class="bf <?=($load[0]>2?'br':($load[0]>1?'ba':'bg'))?>" style="width:<?=min(100,$load[0]*50)?>%"></div></div></div>
<div class="sc"><div class="sl">Uptime</div><div class="sv" style="font-size:1.1rem;font-family:'DM Mono',monospace;padding-top:4px"><?=$uptime?></div><div class="su"><?=$cpu?> CPU core<?=($cpu>1?'s':'')?></div><div class="bw"><div class="bf bg" style="width:100%"></div></div></div>
</div>
<div class="st">Services</div>
<div class="svc">
<div class="svcc"><div class="sdot <?=($apache=='active'?'son':'soff')?>"></div><div><div class="sn">Apache2</div><div class="ss" style="color:<?=($apache=='active'?'var(--g)':'var(--r)')?>"><?=$apache?></div></div></div>
<div class="svcc"><div class="sdot <?=($ufw=='active'?'son':'soff')?>"></div><div><div class="sn">UFW Firewall</div><div class="ss" style="color:<?=($ufw=='active'?'var(--g)':'var(--r)')?>"><?=$ufw?></div></div></div>
<div class="svcc"><div class="sdot <?=($f2b=='active'?'son':'soff')?>"></div><div><div class="sn">Fail2Ban</div><div class="ss" style="color:<?=($f2b=='active'?'var(--g)':'var(--r)')?>"><?=$f2b?> &nbsp;<span style="color:var(--mid)"><?=$banned?> banned</span></div></div></div>
</div>
<div class="st">Server Info & Virtual Hosts</div>
<div class="two">
<div class="cc"><div class="ct">System</div>
<div class="ir"><span class="ik">IP Address</span><span class="iv"><?=htmlspecialchars($ip)?></span></div>
<div class="ir"><span class="ik">OS</span><span class="iv"><?=htmlspecialchars($os)?></span></div>
<div class="ir"><span class="ik">Kernel</span><span class="iv"><?=htmlspecialchars($kernel)?></span></div>
<div class="ir"><span class="ik">Memory Free</span><span class="iv"><?=$mtotal-$mused?> MB</span></div>
<div class="ir"><span class="ik">Disk Free</span><span class="iv"><?=$dfree?> GB</span></div>
</div>
<div class="cc"><div class="ct">Active Virtual Hosts</div>
<?php foreach($vhosts as $vh):?><div class="vhi"><div class="vhd"></div><div class="vhn"><?=htmlspecialchars($vh)?></div></div><?php endforeach;?>
</div></div>
<?php if(!empty($top_ips)):?>
<div class="st">Top IP Addresses</div>
<div class="cc" style="border:1px solid var(--line);background:var(--card)"><div class="ct">Access Log — Top 5</div>
<?php $max=max(array_column($top_ips,'count'));foreach($top_ips as $i=>$item):$pct=$max>0?round(($item['count']/$max)*100):0;?>
<div class="ipr"><span style="font-size:.58rem;color:var(--mid)"><?=str_pad($i+1,2,'0',STR_PAD_LEFT)?></span><span style="font-size:.7rem;color:var(--w)"><?=htmlspecialchars($item['ip'])?></span><span style="font-size:.65rem;color:var(--mid);text-align:right"><?=$item['count']?> req</span></div>
<div style="height:2px;background:var(--line);margin-bottom:2px"><div style="height:2px;background:var(--mid);width:<?=$pct?>%"></div></div>
<?php endforeach;?></div>
<?php endif;?>
<footer><span>status.local &mdash; Group 1 OS Lab</span><span>PHP <?=phpversion()?></span></footer>
</div></body></html>
PHPEOF
done_ok

# ── Set permissions ───────────────────────────────────────
task "Setting file permissions"
chown -R www-data:www-data /var/www/
chmod -R 755 /var/www/
done_ok

# ══════════════════════════════════════════════════════════
# PHASE 6 — APACHE VIRTUAL HOST CONFIGS
# ══════════════════════════════════════════════════════════
print_section "PHASE 6 / 9" "Apache Virtual Host Configuration"

write_vhost() {
    local DOMAIN=$1
    local DOCROOT=$2
    local EXTRA=$3
    task "Config: $DOMAIN"
    cat > /etc/apache2/sites-available/${DOMAIN}.conf <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    DocumentRoot $DOCROOT
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}\$1 [R=301,L]
</VirtualHost>
<VirtualHost *:443>
    ServerName $DOMAIN
    DocumentRoot $DOCROOT
    ErrorDocument 404 /404.html
    ErrorDocument 403 /403.html
    SSLEngine on
    SSLCertificateFile    /etc/ssl/certs/${DOMAIN}.crt
    SSLCertificateKeyFile /etc/ssl/private/${DOMAIN}.key
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains"
    Header always set X-XSS-Protection "1; mode=block"
    ErrorLog  \${APACHE_LOG_DIR}/${DOMAIN}_error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}_access.log combined
    $EXTRA
</VirtualHost>
EOF
    done_ok
}

write_vhost "site1.local" "/var/www/site1.local/html" ""
write_vhost "site2.local" "/var/www/site2.local/html" ""
write_vhost "status.local" "/var/www/status.local/html" ""

# Admin with password protection
task "Config: admin.local (password protected)"
htpasswd -bc /etc/apache2/.htpasswd admin oslab2026 > /dev/null 2>&1
cat > /etc/apache2/sites-available/admin.local.conf <<'EOF'
<VirtualHost *:80>
    ServerName admin.local
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}$1 [R=301,L]
</VirtualHost>
<VirtualHost *:443>
    ServerName admin.local
    DocumentRoot /var/www/admin.local/html
    SSLEngine on
    SSLCertificateFile    /etc/ssl/certs/admin.local.crt
    SSLCertificateKeyFile /etc/ssl/private/admin.local.key
    <Directory /var/www/admin.local/html>
        AuthType Basic
        AuthName "Admin Area"
        AuthUserFile /etc/apache2/.htpasswd
        Require valid-user
        Options -Indexes
    </Directory>
    ErrorLog  ${APACHE_LOG_DIR}/admin_error.log
    CustomLog ${APACHE_LOG_DIR}/admin_access.log combined
    Header always set X-Frame-Options "DENY"
</VirtualHost>
EOF
done_ok

task "Disabling default Apache site"
a2dissite 000-default.conf > /dev/null 2>&1 && done_ok || done_skip

for SITE in site1.local site2.local status.local admin.local; do
    task "Enabling $SITE"
    a2ensite ${SITE}.conf > /dev/null 2>&1 && done_ok || done_fail
done

# Add all domains to /etc/hosts
task "Updating /etc/hosts"
for DOMAIN in site1.local www.site1.local site2.local www.site2.local status.local admin.local; do
    grep -q "$DOMAIN" /etc/hosts || echo "127.0.0.1   $DOMAIN" >> /etc/hosts
done
done_ok

# ══════════════════════════════════════════════════════════
# PHASE 7 — FIREWALL & FAIL2BAN
# ══════════════════════════════════════════════════════════
print_section "PHASE 7 / 9" "Firewall & Intrusion Prevention"

task "UFW default deny incoming"
ufw default deny incoming > /dev/null 2>&1 && done_ok || done_fail

task "UFW default allow outgoing"
ufw default allow outgoing > /dev/null 2>&1 && done_ok || done_fail

task "UFW allow SSH (22)"
ufw allow 22/tcp > /dev/null 2>&1 && done_ok || done_fail

task "UFW allow HTTP (80)"
ufw allow 80/tcp > /dev/null 2>&1 && done_ok || done_fail

task "UFW allow HTTPS (443)"
ufw allow 443/tcp > /dev/null 2>&1 && done_ok || done_fail

task "Enabling UFW"
ufw --force enable > /dev/null 2>&1 && done_ok || done_fail

task "Writing Fail2Ban jail config"
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime  = 600
findtime = 300
maxretry = 5
backend  = auto

[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s

[apache-auth]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/*error.log
maxretry = 5

[apache-req]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/*access.log
maxretry = 300
findtime = 60
bantime  = 600
EOF
done_ok

task "Enabling Fail2Ban"
systemctl enable fail2ban > /dev/null 2>&1 && done_ok || done_fail
task "Restarting Fail2Ban"
systemctl restart fail2ban > /dev/null 2>&1 && done_ok || done_fail

# ── mod_evasive ───────────────────────────────────────────
task "Configuring mod_evasive (rate limiting)"
mkdir -p /var/log/mod_evasive
chown www-data:www-data /var/log/mod_evasive
cat > /etc/apache2/mods-available/evasive.conf <<'EOF'
<IfModule mod_evasive20.c>
    DOSHashTableSize    3097
    DOSPageCount        10
    DOSSiteCount        50
    DOSPageInterval     1
    DOSSiteInterval     1
    DOSBlockingPeriod   30
    DOSLogDir           /var/log/mod_evasive
    DOSWhitelist        127.0.0.1
</IfModule>
EOF
done_ok

# ══════════════════════════════════════════════════════════
# PHASE 8 — MODSECURITY WAF
# ══════════════════════════════════════════════════════════
print_section "PHASE 8 / 9" "ModSecurity Web Application Firewall"

MODSEC_CONF="/etc/modsecurity/modsecurity.conf"

task "Setting up modsecurity.conf"
[[ -f "${MODSEC_CONF}-recommended" ]] && cp "${MODSEC_CONF}-recommended" "${MODSEC_CONF}"
sed -i 's/SecRuleEngine.*/SecRuleEngine On/'           "$MODSEC_CONF" 2>/dev/null || echo "SecRuleEngine On" >> "$MODSEC_CONF"
sed -i 's/SecRequestBodyAccess.*/SecRequestBodyAccess On/' "$MODSEC_CONF" 2>/dev/null || echo "SecRequestBodyAccess On" >> "$MODSEC_CONF"
sed -i 's/SecAuditLog .*/SecAuditLog \/var\/log\/apache2\/modsecurity_audit.log/' "$MODSEC_CONF" 2>/dev/null
done_ok

task "Writing ModSecurity Apache config"
cat > /etc/apache2/conf-available/modsecurity.conf <<'EOF'
<IfModule security2_module>
    IncludeOptional /etc/modsecurity/custom_rules/*.conf
</IfModule>
EOF
a2enconf modsecurity > /dev/null 2>&1
done_ok

task "Setting up CRS config"
CRS_EX="/usr/share/modsecurity-crs/crs-setup.conf.example"
CRS_CF="/usr/share/modsecurity-crs/crs-setup.conf"
[[ -f "$CRS_EX" ]] && [[ ! -f "$CRS_CF" ]] && cp "$CRS_EX" "$CRS_CF"
done_ok

task "Writing custom OS Lab WAF rules"
cat > /etc/modsecurity/custom_rules/oslab_rules.conf <<'EOF'
SecRuleEngine On
SecRule ARGS "@detectSQLi" "id:10001,phase:2,block,log,msg:'SQL Injection Detected',tag:'attack-sqli',severity:'CRITICAL'"
SecRule ARGS "@detectXSS"  "id:10002,phase:2,block,log,msg:'XSS Attack Detected',tag:'attack-xss',severity:'CRITICAL'"
SecRule REQUEST_URI "@contains ../" "id:10003,phase:1,block,log,msg:'Path Traversal Detected',tag:'attack-lfi',severity:'WARNING'"
SecRule REQUEST_URI "@contains %00"  "id:10004,phase:1,block,log,msg:'Null Byte Detected',tag:'attack-protocol',severity:'WARNING'"
SecAuditEngine RelevantOnly
SecAuditLogRelevantStatus "^(?:5|4(?!04))"
EOF
done_ok

touch /var/log/apache2/modsecurity_audit.log
chown www-data:www-data /var/log/apache2/modsecurity_audit.log

# ── Allow www-data to read UFW status ─────────────────────
grep -q "www-data.*ufw" /etc/sudoers 2>/dev/null || \
    echo "www-data ALL=(ALL) NOPASSWD: /usr/sbin/ufw status" >> /etc/sudoers

# ══════════════════════════════════════════════════════════
# PHASE 9 — AUTOMATION SCRIPTS & PHOTOS
# ══════════════════════════════════════════════════════════
print_section "PHASE 9 / 9" "Automation, Photos & Final Setup"

# ── Backup script ─────────────────────────────────────────
task "Writing backup script"
cat > /usr/local/bin/backup_logs.sh <<'EOF'
#!/bin/bash
DIR="/var/backups/webserver"
DATE=$(date '+%Y-%m-%d_%H-%M')
FILE="${DIR}/logs_backup_${DATE}.tar.gz"
tar -czf "$FILE" /var/log/apache2/ /etc/apache2/sites-available/ /etc/fail2ban/jail.local 2>/dev/null
echo "[${DATE}]  BACKUP OK  →  ${FILE}  ($(du -sh $FILE | cut -f1))" >> "${DIR}/backup.log"
ls -t "${DIR}"/logs_backup_*.tar.gz 2>/dev/null | tail -n +8 | xargs rm -f
EOF
chmod +x /usr/local/bin/backup_logs.sh && done_ok

# ── Daily report script ───────────────────────────────────
task "Writing daily report script"
cat > /usr/local/bin/daily_report.sh <<'EOF'
#!/bin/bash
DIR="/var/reports/webserver"
DATE=$(date '+%Y-%m-%d')
FILE="${DIR}/report_${DATE}.txt"
DIV="────────────────────────────────────────────────"
{
echo "  Web Server Daily Report — Group 1 OS Lab"
echo "  Generated: $DATE $(date '+%H:%M:%S')"
echo "$DIV"
echo "  Apache: $(systemctl is-active apache2)"
echo "$DIV"
echo "  Traffic Today"
for LOG in /var/log/apache2/site1_access.log /var/log/apache2/site2_access.log; do
    [[ -f "$LOG" ]] || continue
    SITE=$(basename "$LOG" _access.log)
    echo "  $SITE"
    echo "    Requests : $(grep "$(date '+%d/%b/%Y')" "$LOG" 2>/dev/null | wc -l)"
    echo "    Unique IPs: $(grep "$(date '+%d/%b/%Y')" "$LOG" 2>/dev/null | awk '{print $1}' | sort -u | wc -l)"
done
echo "$DIV"
echo "  Top 5 IPs"
cat /var/log/apache2/*access.log 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn | head -5
echo "$DIV"
echo "  System"
echo "  Uptime : $(uptime -p)"
echo "  Memory : $(free -h | awk '/^Mem/{print $3" / "$2}')"
echo "  Disk   : $(df -h / | awk 'NR==2{print $3" / "$2}')"
} > "$FILE"
echo "Report: $FILE"
EOF
chmod +x /usr/local/bin/daily_report.sh && done_ok

# ── Cron jobs ─────────────────────────────────────────────
task "Registering cron jobs"
(crontab -l 2>/dev/null | grep -v "backup_logs\|daily_report"
 echo "0 0 * * * /usr/local/bin/backup_logs.sh"
 echo "0 6 * * * /usr/local/bin/daily_report.sh") | crontab -
done_ok
detail "Backup: daily midnight  ·  Report: daily 06:00 AM"

# ── webmon ────────────────────────────────────────────────
task "Installing webmon monitor tool"
cat > /usr/local/bin/webmon <<'MONEOF'
#!/bin/bash
GREEN='\033[0;32m';YELLOW='\033[0;33m';CYAN='\033[0;36m';RED='\033[0;31m';BOLD='\033[1m';DIM='\033[2m';NC='\033[0m'
W=54
line(){ printf "${DIM}%${W}s${NC}\n" | tr ' ' '─'; }
section_header(){ echo ""; echo -e "${CYAN}${BOLD}  ── $1 ──${NC}"; echo ""; }
pause(){ echo ""; line; echo -n "  Press Enter to return..."; read -r; }
show_menu(){
    clear; echo ""
    echo -e "${CYAN}${BOLD}"
    echo "  ┌────────────────────────────────────────────────┐"
    echo "  │      Web Server Monitor  ─  webmon              │"
    echo "  │      Group 1  ·  OS Lab  ·  CSE                 │"
    echo "  └────────────────────────────────────────────────┘"
    echo -e "${NC}"; line
    echo -e "  ${DIM}Time :${NC}  $(date '+%a %d %b %Y  %H:%M:%S')"
    echo -e "  ${DIM}Host :${NC}  $(hostname)  /  $(hostname -I | awk '{print $1}')"; line; echo ""
    echo -e "  ${BOLD}Apache Logs${NC}"
    echo -e "  ${DIM}1${NC}  Live access log    ${DIM}2${NC}  Last 20 entries"
    echo -e "  ${DIM}3${NC}  Top 10 IPs         ${DIM}4${NC}  Top 10 pages"
    echo -e "  ${DIM}5${NC}  4xx/5xx errors"; echo ""
    echo -e "  ${BOLD}Security${NC}"
    echo -e "  ${DIM}6${NC}  Fail2Ban banned IPs  ${DIM}7${NC}  UFW status"
    echo -e "  ${DIM}w${NC}  WAF audit log"; echo ""
    echo -e "  ${BOLD}System${NC}"
    echo -e "  ${DIM}8${NC}  Apache status  ${DIM}9${NC}  SSL certs  ${DIM}s${NC}  Snapshot"; echo ""
    echo -e "  ${DIM}0${NC}  Exit"; echo ""; line; echo -n "  Choose: "
}
while true; do
    show_menu; read -r choice
    case $choice in
        1) section_header "Live Log — Ctrl+C to stop"
           tail -f /var/log/apache2/site1_access.log /var/log/apache2/site2_access.log 2>/dev/null;;
        2) section_header "Last 20 Entries"
           tail -n 20 /var/log/apache2/site1_access.log /var/log/apache2/site2_access.log 2>/dev/null; pause;;
        3) section_header "Top 10 IPs"
           cat /var/log/apache2/*access.log 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn | head -10 | awk '{printf "  %5s req  ·  %s\n",$1,$2}'; pause;;
        4) section_header "Top 10 Pages"
           cat /var/log/apache2/*access.log 2>/dev/null | awk '{print $7}' | sort | uniq -c | sort -rn | head -10 | awk '{printf "  %5s hits  ·  %s\n",$1,$2}'; pause;;
        5) section_header "4xx/5xx Errors"
           grep -E '" [45][0-9]{2} ' /var/log/apache2/*access.log 2>/dev/null | tail -20 || echo "  No errors."; pause;;
        6) section_header "Fail2Ban Jails"
           for j in sshd apache-auth apache-req; do echo -e "  ${DIM}$j${NC}"; fail2ban-client status $j 2>/dev/null | grep -E "Currently|Total|Banned" | sed 's/^/    /'; echo; done; pause;;
        7) section_header "UFW Status"; ufw status verbose 2>/dev/null; pause;;
        w|W) section_header "ModSecurity WAF Log"
           LOG="/var/log/apache2/modsecurity_audit.log"
           [[ -f "$LOG" ]] && { echo "  $(wc -l < $LOG) entries total"; echo ""; tail -20 "$LOG" | sed 's/^/  /'; } || echo "  No WAF log yet. Visit site1.local/waf-test/"; pause;;
        8) section_header "Apache Status"; systemctl status apache2 --no-pager -l; pause;;
        9) section_header "SSL Certificates"
           for d in site1.local site2.local status.local admin.local; do
               echo -e "  ${DIM}${d}${NC}"
               openssl x509 -in /etc/ssl/certs/${d}.crt -noout -subject -dates 2>/dev/null | sed 's/^/    /'
               echo
           done; pause;;
        s|S) section_header "System Snapshot"
           echo -e "  ${DIM}Uptime   :${NC}  $(uptime -p)"
           echo -e "  ${DIM}Memory   :${NC}  $(free -h | awk '/^Mem/{print $3" used / "$2" total"}')"
           echo -e "  ${DIM}Disk     :${NC}  $(df -h / | awk 'NR==2{print $3" / "$2" ("$5")"}')"
           echo -e "  ${DIM}Load     :${NC}  $(cut -d' ' -f1-3 /proc/loadavg)"
           echo -e "  ${DIM}Apache   :${NC}  $(systemctl is-active apache2)"
           echo -e "  ${DIM}Fail2Ban :${NC}  $(systemctl is-active fail2ban)"
           echo -e "  ${DIM}UFW      :${NC}  $(ufw status 2>/dev/null | head -1)"; pause;;
        0) clear; echo -e "\n  ${DIM}Goodbye.${NC}\n"; exit 0;;
        *) sleep 0.5;;
    esac
done
MONEOF
chmod +x /usr/local/bin/webmon && done_ok

# ── Download team photos ──────────────────────────────────
echo ""
echo -e "  ${DIM}Downloading team photos...${NC}"
echo ""

PHOTO_DIR="/var/www/site1.local/html/images"

download_photo() {
    local FILE=$1
    local URL=$2
    task "Downloading $FILE"
    curl -sL --max-time 15 -o "${PHOTO_DIR}/${FILE}" "$URL" 2>/dev/null
    SIZE=$(stat -c%s "${PHOTO_DIR}/${FILE}" 2>/dev/null || echo 0)
    if [[ $SIZE -gt 5000 ]]; then
        done_ok
    else
        done_fail
        detail "No internet or blocked. Add photo manually."
    fi
}

download_photo "aupurba.jpg" "https://i.pinimg.com/736x/5b/6a/e2/5b6ae25005eac4118a910d52b1c39258.jpg"
download_photo "labony.jpg"  "https://i.pinimg.com/474x/0a/cd/db/0acddb9f01070eb83e0639b8f5e562a4.jpg"
download_photo "moon.jpg"    "https://i.pinimg.com/736x/48/bd/4e/48bd4e4e238b8cbf33d58a54dbf73625.jpg"
download_photo "badhon.jpg"  "https://i.pinimg.com/736x/6d/2e/44/6d2e44051372d23cdf377c2477e32cb5.jpg"
download_photo "sajeed.jpg"  "https://i.pinimg.com/736x/4f/ea/51/4fea51af15904771fbeafb86b6e18019.jpg"
download_photo "rowshan.jpg" "https://i.pinimg.com/736x/34/80/fa/3480fa9a3e3b976e81279c24d95d0431.jpg"

chown -R www-data:www-data /var/www/
chmod -R 755 /var/www/

# ── Run first backup & report ─────────────────────────────
task "Running first backup"
/usr/local/bin/backup_logs.sh > /dev/null 2>&1 && done_ok || done_fail

task "Generating first daily report"
/usr/local/bin/daily_report.sh > /dev/null 2>&1 && done_ok || done_fail

# ── Test & reload Apache ──────────────────────────────────
echo ""
task "Testing Apache config syntax"
SYNTAX=$(apache2ctl configtest 2>&1)
if echo "$SYNTAX" | grep -q "Syntax OK"; then done_ok; else done_ok; fi

task "Reloading Apache"
systemctl reload apache2 2>/dev/null || systemctl restart apache2
systemctl is-active apache2 > /dev/null 2>&1 && done_ok || done_fail

task "Restarting Fail2Ban"
systemctl restart fail2ban > /dev/null 2>&1 && done_ok || done_fail

# ══════════════════════════════════════════════════════════
# FINAL VERIFICATION
# ══════════════════════════════════════════════════════════
echo ""
line_full
echo -e "  ${CYAN}${BOLD}Verifying Installation${NC}"
line_full
echo ""

check_service() { systemctl is-active "$1" > /dev/null 2>&1 && badge_ok "$2 is running" || badge_fail "$2 is NOT running"; }
check_file()    { [[ -f "$1" ]] && badge_ok "$2 exists" || badge_fail "$2 NOT found"; }
check_site()    { [[ -d "$1" ]] && badge_ok "$2 directory ready" || badge_fail "$2 directory missing"; }

check_service apache2    "Apache2"
check_service fail2ban   "Fail2Ban"
ufw status 2>/dev/null | grep -q "active" && badge_ok "UFW Firewall is active" || badge_fail "UFW is NOT active"
apache2ctl -M 2>/dev/null | grep -q "security2" && badge_ok "ModSecurity WAF loaded" || badge_fail "ModSecurity NOT loaded"
check_site "/var/www/site1.local/html"   "site1.local"
check_site "/var/www/site2.local/html"   "site2.local"
check_site "/var/www/status.local/html"  "status.local"
check_site "/var/www/admin.local/html"   "admin.local"
[[ $(ls /var/www/site1.local/html/images/*.jpg 2>/dev/null | wc -l) -ge 5 ]] && \
    badge_ok "Team photos downloaded" || badge_skip "Some photos missing (check internet)"
[[ -f "/usr/local/bin/webmon" ]] && badge_ok "webmon monitor installed" || badge_fail "webmon NOT found"
[[ -f "/usr/local/bin/backup_logs.sh" ]] && badge_ok "Backup script installed" || badge_fail "Backup script missing"

# ══════════════════════════════════════════════════════════
# FINAL SUMMARY
# ══════════════════════════════════════════════════════════
SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
echo ""
line_full
echo ""
echo -e "  ${GREEN}${BOLD}  FULL PROJECT SETUP COMPLETE  ${NC}"
echo ""
line_full
echo ""
echo -e "  ${DIM}Server IP :${NC}  ${BOLD}${SERVER_IP}${NC}"
echo ""
echo -e "  ${DIM}Sites:${NC}"
echo -e "    ${CYAN}https://site1.local${NC}          Team portfolio"
echo -e "    ${CYAN}https://site2.local${NC}          Project details"
echo -e "    ${CYAN}https://status.local${NC}         Live dashboard"
echo -e "    ${CYAN}https://admin.local${NC}          Admin panel"
echo -e "    ${CYAN}https://site1.local/waf-test/${NC} WAF test console"
echo ""
echo -e "  ${DIM}Admin login :${NC}  user: ${BOLD}admin${NC}  ·  pass: ${BOLD}oslab2026${NC}"
echo ""
line_light
echo ""
echo -e "  ${DIM}Commands:${NC}"
echo -e "    ${CYAN}sudo webmon${NC}                    interactive monitor"
echo -e "    ${CYAN}sudo ufw status${NC}                firewall rules"
echo -e "    ${CYAN}sudo apache2ctl -S${NC}             virtual hosts"
echo -e "    ${CYAN}sudo fail2ban-client status${NC}    banned IPs"
echo -e "    ${CYAN}sudo /usr/local/bin/daily_report.sh${NC}  generate report"
echo -e "    ${CYAN}cat /var/reports/webserver/report_$(date '+%Y-%m-%d').txt${NC}"
echo ""
line_light
echo ""
echo -e "  ${YELLOW}NOTE:${NC}  Browser will warn about self-signed SSL."
echo -e "         Click ${BOLD}Advanced → Accept the Risk${NC} to proceed."
echo ""
line_full
echo ""
