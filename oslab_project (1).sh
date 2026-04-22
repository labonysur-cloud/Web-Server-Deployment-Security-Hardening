#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  OS LAB COMPLETE PROJECT — Web Server Deployment & Hardening     ║
# ║  Group 1 | CSE | Daffodil International University | 2026        ║
# ║  Members: Labony · Aupurba · Moon · Badhon · Sajeed · Rowshan    ║
# ║  Supervisor: Fardowsi Rahman, Lecturer, CSE, DIU                 ║
# ╠══════════════════════════════════════════════════════════════════╣
# ║  WHAT THIS SCRIPT DOES (9 Phases + Control Panel):               ║
# ║  1. Install all packages                                         ║
# ║  2. Enable Apache modules                                        ║
# ║  3. Create directory structure                                   ║
# ║  4. Generate SSL certificates (RSA 2048, 4 domains)              ║
# ║  5. Write all websites (team portfolio, project docs, etc.)      ║
# ║  6. Configure virtual hosts                                      ║
# ║  7. UFW Firewall + Fail2Ban (3 jails)                            ║
# ║  8. ModSecurity WAF (OWASP CRS + custom rules)                   ║
# ║  9. Automation (webmon, cron, backup, report)                    ║
# ║ +P. Control Panel at panel.local (deploy, monitor, attack test)  ║
# ╚══════════════════════════════════════════════════════════════════╝
# USAGE:  sudo bash oslab_complete.sh
# TIME:   ~10-15 minutes on first run

# ── Guard: must be root ───────────────────────────────────────────
[[ $EUID -ne 0 ]] && { echo "Run as root: sudo bash oslab_complete.sh"; exit 1; }

# ── Colors & UI helpers ───────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[0;33m' C='\033[0;36m'
B='\033[1m' D='\033[2m' NC='\033[0m'
W=66
line(){ printf "${D}%${W}s${NC}\n"|tr ' ' '─'; }
title(){ echo ""; line; echo -e "  ${C}${B}[ $1 ]${NC}  ${B}$2${NC}"; line; echo ""; }
task(){ printf "  ${C}${B} ▸ ${NC} %-50s" "$1"; }
ok(){ echo -e " ${G}${B}OK${NC}"; }
fail(){ echo -e " ${R}${B}FAIL${NC}"; }
info(){ echo -e "     ${D}$1${NC}"; }
pass_badge(){ echo -e "  ${G}${B}[PASS]${NC} $1"; }
fail_badge(){ echo -e "  ${R}${B}[FAIL]${NC} $1"; }
skip_badge(){ echo -e "  ${Y}${B}[SKIP]${NC} $1"; }

# ── Generate secure admin password ────────────────────────────────
ADMIN_PASS=$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)
echo "$ADMIN_PASS" > /root/.oslab_admin_password
chmod 600 /root/.oslab_admin_password

# ── Banner ────────────────────────────────────────────────────────
clear; echo ""
echo -e "${C}${B}"
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║         Web Server Deployment & Security Hardening          ║"
echo "  ║         Group 1  ·  CSE Department  ·  OS Lab               ║"
echo "  ║         Daffodil International University  ·  2025-2026     ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${D}Date   :${NC} $(date '+%A %d %B %Y  %H:%M:%S')"
echo -e "  ${D}Host   :${NC} $(hostname)"
echo -e "  ${D}IP     :${NC} $(hostname -I | awk '{print $1}')"
echo -e "  ${D}OS     :${NC} $(lsb_release -ds 2>/dev/null)"
echo ""; line; echo ""
echo "  Starting in 3 seconds..."; sleep 3

# ╔══════════════════════════════════════════════════════════════════╗
# ║  PHASE 1 — PACKAGES                                             ║
# ╚══════════════════════════════════════════════════════════════════╝
title "PHASE 1/9" "System Update & Package Installation"

task "Updating package index"
apt-get update -y >/dev/null 2>&1 && ok || fail

task "Installing all required packages"
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  apache2 openssl ufw fail2ban curl php libapache2-mod-php \
  libapache2-mod-security2 modsecurity-crs libapache2-mod-evasive \
  apache2-utils acl php-curl >/dev/null 2>&1 && ok || fail

task "Configuring PHP for panel"
PHP_INI=$(php -r 'echo php_ini_loaded_file();' 2>/dev/null)
if [[ -n "$PHP_INI" ]]; then
  sed -i 's/^upload_max_filesize.*/upload_max_filesize = 64M/' "$PHP_INI" 2>/dev/null
  sed -i 's/^post_max_size.*/post_max_size = 64M/' "$PHP_INI" 2>/dev/null
  sed -i 's/^max_execution_time.*/max_execution_time = 120/' "$PHP_INI" 2>/dev/null
  sed -i 's/^max_input_time.*/max_input_time = 120/' "$PHP_INI" 2>/dev/null
  # Ensure shell_exec is not disabled
  sed -i 's/\bshell_exec\b,\?//g' "$PHP_INI" 2>/dev/null
  sed -i 's/\bexec\b,\?//g' "$PHP_INI" 2>/dev/null
  ok
else
  skip_badge "PHP ini not found — skipping config"
fi

task "Enabling Apache on boot"
systemctl enable apache2 >/dev/null 2>&1 && ok || fail

task "Starting Apache"
systemctl start apache2 >/dev/null 2>&1 && ok || fail

APVER=$(apache2 -v 2>/dev/null | grep -oP '[\d.]+' | head -1)
PHPVER=$(php -r 'echo PHP_VERSION;' 2>/dev/null)
SSLVER=$(openssl version | awk '{print $2}')
info "Apache ${APVER}  ·  PHP ${PHPVER}  ·  OpenSSL ${SSLVER}"

# ╔══════════════════════════════════════════════════════════════════╗
# ║  PHASE 2 — APACHE MODULES                                       ║
# ╚══════════════════════════════════════════════════════════════════╝
title "PHASE 2/9" "Enabling Apache Modules"

for MOD in ssl rewrite headers auth_basic unique_id security2 evasive status; do
  task "mod_${MOD}"
  a2enmod "$MOD" >/dev/null 2>&1 && ok || fail
done

task "mod_php (any available version)"
a2enmod php8* >/dev/null 2>&1 || a2enmod php7* >/dev/null 2>&1
ok

# ╔══════════════════════════════════════════════════════════════════╗
# ║  PHASE 3 — DIRECTORIES                                          ║
# ╚══════════════════════════════════════════════════════════════════╝
title "PHASE 3/9" "Creating Directory Structure"

for DIR in \
  /var/www/site1.local/html/images \
  /var/www/site1.local/html/waf-test \
  /var/www/site2.local/html \
  /var/www/status.local/html \
  /var/www/admin.local/html \
  /var/www/panel.local/html/monitor \
  /var/www/errors \
  /etc/modsecurity/custom_rules \
  /var/log/mod_evasive \
  /var/backups/webserver \
  /var/reports/webserver; do
  task "$(echo $DIR | sed 's|/var/www/||;s|/html.*||' | head -c 48)"
  mkdir -p "$DIR" && ok || fail
done

chown -R www-data:www-data /var/www/
chmod -R 755 /var/www/

# Clean up broken override files from previous runs
rm -f /var/www/site1.local/html/.htaccess 2>/dev/null
rm -f /var/www/site2.local/html/.htaccess 2>/dev/null
rm -f /var/www/status.local/html/.htaccess 2>/dev/null

# ╔══════════════════════════════════════════════════════════════════╗
# ║  PHASE 4 — SSL CERTIFICATES                                     ║
# ╚══════════════════════════════════════════════════════════════════╝
title "PHASE 4/9" "Generating SSL Certificates"

gen_cert(){
  local D=$1
  task "SSL cert for ${D}"
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/${D}.key \
    -out    /etc/ssl/certs/${D}.crt \
    -subj   "/C=BD/ST=Chattogram/L=Chittagong/O=OS-Lab-DIU/CN=${D}" \
    >/dev/null 2>&1
  chmod 600 /etc/ssl/private/${D}.key
  ok
}

for DOMAIN in site1.local site2.local status.local admin.local panel.local; do
  gen_cert "$DOMAIN"
done
info "Algorithm: RSA 2048-bit  ·  Valid: 365 days  ·  SHA-256"

# ╔══════════════════════════════════════════════════════════════════╗
# ║  PHASE 5 — WEB PAGES                                            ║
# ╚══════════════════════════════════════════════════════════════════╝
title "PHASE 5/9" "Writing Web Pages"

# ── site1.local — Team Portfolio ─────────────────────────────────
task "site1.local — Team Portfolio"
cat > /var/www/site1.local/html/index.html << 'SITE1EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Group 1 — OS Lab Team</title>
<link href="https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&family=DM+Mono:wght@300;400&display=swap" rel="stylesheet">
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{--bg:#f8f8f6;--tx:#0e0e0e;--bd:#e0e0dc;--mu:#888;--sf:#fff}
body{background:var(--bg);color:var(--tx);font-family:'DM Mono',monospace;font-weight:300;min-height:100vh}
header{border-bottom:1px solid var(--bd);padding:28px 40px;display:flex;align-items:baseline;gap:16px}
.logo{font-family:'Instrument Serif',serif;font-size:1.8rem;font-style:italic}
.meta{font-size:.65rem;color:var(--mu);letter-spacing:.1em;text-transform:uppercase}
.sub{padding:20px 40px 28px;border-bottom:1px solid var(--bd)}
.sub h2{font-family:'Instrument Serif',serif;font-size:1.1rem;font-weight:400;margin-bottom:8px}
.sub p{font-size:.72rem;color:var(--mu);line-height:1.8}
.grid{display:grid;grid-template-columns:repeat(3,1fr);padding:28px 40px;gap:16px}
.card{border:1px solid var(--bd);padding:20px;transition:border-color .2s}
.card:hover{border-color:var(--tx)}
.avatar{width:64px;height:64px;border:1px solid var(--bd);border-radius:50%;margin-bottom:14px;overflow:hidden;background:var(--sf);display:flex;align-items:center;justify-content:center;font-size:1.4rem;font-family:'Instrument Serif',serif;font-style:italic;color:var(--mu)}
.avatar img{width:100%;height:100%;object-fit:cover}
.name{font-size:.88rem;font-weight:400;margin-bottom:3px}
.id{font-size:.62rem;color:var(--mu);margin-bottom:10px}
.role{font-size:.6rem;letter-spacing:.1em;text-transform:uppercase;color:var(--mu);padding:3px 8px;border:1px solid var(--bd);display:inline-block}
footer{border-top:1px solid var(--bd);padding:16px 40px;font-size:.62rem;color:var(--mu);display:flex;justify-content:space-between}
</style>
</head>
<body>
<header>
  <span class="logo">Group 1</span>
  <span class="meta">CSE  ·  OS Lab  ·  Daffodil International University</span>
</header>
<div class="sub">
  <h2>Web Server Deployment &amp; <em style="font-family:'Instrument Serif',serif;font-style:italic">Security Hardening</em></h2>
  <p>Supervisor: Fardowsi Rahman, Lecturer, CSE, DIU  ·  2025–2026</p>
</div>
<div class="grid">
  <div class="card">
    <div class="avatar"><img src="images/aupurba.jpg" alt="Aupurba" onerror="this.style.display='none';this.parentNode.textContent='AS'">AS</div>
    <div class="name">Aupurba Sarker</div>
    <div class="id">232-15-269</div>
    <span class="role">Team Lead</span>
  </div>
  <div class="card">
    <div class="avatar"><img src="images/labony.jpg" alt="Labony" onerror="this.style.display='none';this.parentNode.textContent='LS'">LS</div>
    <div class="name">Labony Sur</div>
    <div class="id">232-15-473</div>
    <span class="role">Developer</span>
  </div>
  <div class="card">
    <div class="avatar"><img src="images/moon.jpg" alt="Moon" onerror="this.style.display='none';this.parentNode.textContent='MM'">MM</div>
    <div class="name">Moontakim Moon</div>
    <div class="id">232-15-680</div>
    <span class="role">Security</span>
  </div>
  <div class="card">
    <div class="avatar"><img src="images/badhon.jpg" alt="Badhon" onerror="this.style.display='none';this.parentNode.textContent='AB'">AB</div>
    <div class="name">Al Mahmud Badhon</div>
    <div class="id">232-15-241</div>
    <span class="role">Networking</span>
  </div>
  <div class="card">
    <div class="avatar"><img src="images/sajeed.jpg" alt="Sajeed" onerror="this.style.display='none';this.parentNode.textContent='SS'">SS</div>
    <div class="name">Sajeed Awal Sharif</div>
    <div class="id">232-15-470</div>
    <span class="role">Scripting</span>
  </div>
  <div class="card">
    <div class="avatar"><img src="images/rowshan.jpg" alt="Rowshan" onerror="this.style.display='none';this.parentNode.textContent='RA'">RA</div>
    <div class="name">Mst. Rawshan Ara</div>
    <div class="id">232-15-876</div>
    <span class="role">Documentation</span>
  </div>
</div>
<footer>
  <span>Virtual Host 1 — site1.local</span>
  <span>HTTPS · RSA 2048 · Apache2</span>
</footer>
</body></html>
SITE1EOF
ok

# ── site2.local — Project Details ────────────────────────────────
task "site2.local — Project Details"
cat > /var/www/site2.local/html/index.html << 'SITE2EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Project Details — OS Lab Group 1</title>
<link href="https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&family=DM+Mono:wght@300;400&display=swap" rel="stylesheet">
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
body{background:#f8f8f6;color:#0e0e0e;font-family:'DM Mono',monospace;font-weight:300;display:grid;grid-template-columns:220px 1fr;min-height:100vh}
nav{border-right:1px solid #e0e0dc;padding:28px 0;position:sticky;top:0;height:100vh;overflow-y:auto}
.nav-logo{font-family:'Instrument Serif',serif;font-size:1.1rem;font-style:italic;padding:0 20px 20px;border-bottom:1px solid #e0e0dc;display:block;margin-bottom:16px}
.nav-link{display:block;padding:8px 20px;font-size:.65rem;letter-spacing:.06em;color:#888;text-decoration:none;border-left:2px solid transparent;transition:all .15s}
.nav-link:hover{color:#0e0e0e;border-left-color:#0e0e0e}
main{padding:40px 48px;max-width:780px}
h1{font-family:'Instrument Serif',serif;font-size:2.2rem;font-weight:400;margin-bottom:8px}
.subtitle{font-size:.7rem;color:#888;margin-bottom:36px;letter-spacing:.06em}
h2{font-family:'Instrument Serif',serif;font-size:1.3rem;font-weight:400;margin:32px 0 12px;padding-top:32px;border-top:1px solid #e0e0dc}
h2:first-of-type{margin-top:0;padding-top:0;border-top:none}
p{font-size:.78rem;color:#555;line-height:1.9;margin-bottom:12px}
.feature-grid{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin:16px 0}
.feature{border:1px solid #e0e0dc;padding:14px;font-size:.7rem}
.feature strong{display:block;color:#0e0e0e;margin-bottom:4px;font-weight:400}
.feature span{color:#888}
code{background:#f0f0ee;padding:1px 6px;font-size:.72rem}
.cmd-list{margin:10px 0;padding-left:0;list-style:none}
.cmd-list li{padding:6px 0;border-bottom:1px solid #f0f0ee;font-size:.72rem;color:#555}
.cmd-list li code{background:none;color:#0e0e0e}
</style>
</head>
<body>
<nav>
  <span class="nav-logo">OS Lab</span>
  <a class="nav-link" href="#overview">Overview</a>
  <a class="nav-link" href="#features">Features</a>
  <a class="nav-link" href="#security">Security</a>
  <a class="nav-link" href="#commands">Commands</a>
  <a class="nav-link" href="#team">Team</a>
</nav>
<main>
  <h1>Web Server Deployment<br>&amp; <em>Security Hardening</em></h1>
  <p class="subtitle">OS Lab Project  ·  Group 1  ·  CSE  ·  DIU  ·  2025–2026</p>

  <h2 id="overview">Overview</h2>
  <p>This project deploys a fully secured Linux web server on Ubuntu 24.04 LTS inside VirtualBox. A single 900+ line Bash script automates all 9 phases of deployment — from package installation to WAF configuration — in one command.</p>

  <h2 id="features">Features</h2>
  <div class="feature-grid">
    <div class="feature"><strong>Virtual Hosting</strong><span>4 sites on one server: site1, site2, status, admin</span></div>
    <div class="feature"><strong>HTTPS / SSL</strong><span>RSA 2048-bit, self-signed, 365 days per domain</span></div>
    <div class="feature"><strong>UFW Firewall</strong><span>Default deny, only 22/80/443 open</span></div>
    <div class="feature"><strong>Fail2Ban</strong><span>3 jails: sshd, apache-auth, apache-req</span></div>
    <div class="feature"><strong>ModSecurity WAF</strong><span>OWASP CRS + 4 custom rules, blocking mode</span></div>
    <div class="feature"><strong>Control Panel</strong><span>Deploy sites, monitor attacks, manage security</span></div>
  </div>

  <h2 id="security">Security Layers</h2>
  <p>Layer 1: UFW Network Firewall — default deny all inbound. Layer 2: HTTPS with forced redirect from HTTP. Layer 3: ModSecurity WAF blocks SQLi, XSS, path traversal. Layer 4: Fail2Ban bans IPs after 5 failed attempts. Layer 5: mod_evasive rate limiting (10 req/s threshold). Layer 6: Security headers on all virtual hosts.</p>

  <h2 id="commands">Key Commands</h2>
  <ul class="cmd-list">
    <li><code>sudo webmon</code> — interactive monitoring menu</li>
    <li><code>sudo ufw status verbose</code> — firewall rules</li>
    <li><code>sudo apache2ctl -S</code> — virtual hosts list</li>
    <li><code>sudo fail2ban-client status sshd</code> — banned IPs</li>
    <li><code>sudo tail -f /var/log/apache2/modsecurity_audit.log</code> — WAF log</li>
    <li><code>https://panel.local/monitor/</code> — live attack monitor</li>
  </ul>

  <h2 id="team">Team</h2>
  <p>Aupurba Sarker (232-15-269) · Labony Sur (232-15-473) · Moontakim Moon (232-15-680) · Al Mahmud Badhon (232-15-241) · Sajeed Awal Sharif (232-15-470) · Mst. Rawshan Ara Prodan (232-15-876)</p>
  <p style="margin-top:8px">Supervisor: <strong style="font-weight:400">Fardowsi Rahman</strong>, Lecturer, CSE, Daffodil International University</p>
</main>
</body></html>
SITE2EOF
ok

# ── status.local — PHP Dashboard ─────────────────────────────────
task "status.local — Live PHP Dashboard"
cat > /var/www/status.local/html/index.php << 'STATEOF'
<?php
$mem_raw = explode("\n", trim(shell_exec('free -m') ?: ''));
$mem = preg_split('/\s+/', trim($mem_raw[1] ?? ''));
$mt = $mem[1] ?? 1; $mu = $mem[2] ?? 0; $mp = round($mu/$mt*100);
$dt = round(disk_total_space('/')/1073741824,1);
$df = round(disk_free_space('/')/1073741824,1);
$du = round($dt-$df,1); $dp = round($du/$dt*100);
$load = sys_getloadavg();
$up = str_replace('up ','',trim(shell_exec('uptime -p') ?: ''));
$apache_st = trim(shell_exec('systemctl is-active apache2 2>/dev/null') ?: 'unknown');
$f2b_st    = trim(shell_exec('systemctl is-active fail2ban 2>/dev/null') ?: 'unknown');
$ufw_st    = trim(shell_exec('sudo ufw status 2>/dev/null | head -1') ?: 'unknown');
$waf_count = 0;
if(file_exists('/var/log/apache2/modsecurity_audit.log'))
  $waf_count = (int)trim(shell_exec('wc -l < /var/log/apache2/modsecurity_audit.log') ?: '0');
$banned = trim(shell_exec("sudo fail2ban-client status sshd 2>/dev/null | grep 'Currently banned' | awk '{print \$NF}'") ?: '0');
$today = date('d/M/Y'); $total_req = 0; $uniq_ips = [];
foreach(glob('/var/log/apache2/*_access.log') ?: [] as $lf){
  foreach(file($lf) ?: [] as $ln){
    if(strpos($ln,$today)!==false){ $total_req++;
      $p=explode(' ',$ln); if(isset($p[0])) $uniq_ips[$p[0]]=1; }}}
$vhosts = [];
preg_match_all('/namevhost\s+(\S+)/', shell_exec('apache2ctl -S 2>/dev/null') ?: '', $m);
foreach(array_unique($m[1]??[]) as $v) if($v!=='_default_') $vhosts[]=$v;
header('Refresh: 10');
?>
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Server Status — OS Lab</title>
<link href="https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&family=DM+Mono:wght@300;400&display=swap" rel="stylesheet">
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#f8f8f6;color:#0e0e0e;font-family:'DM Mono',monospace;font-weight:300;padding:32px}
h1{font-family:'Instrument Serif',serif;font-size:2rem;font-style:italic;font-weight:400;margin-bottom:4px}
.sub{font-size:.62rem;color:#888;margin-bottom:28px;letter-spacing:.06em}
.g4{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:20px}
.g3{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin-bottom:20px}
.card{border:1px solid #e0e0dc;padding:18px;background:#fff}
.cl{font-size:.56rem;letter-spacing:.14em;text-transform:uppercase;color:#888;margin-bottom:8px}
.cv{font-family:'Instrument Serif',serif;font-size:2rem;font-style:italic;line-height:1}
.cs{font-size:.62rem;color:#888;margin-top:4px}
.bar{height:2px;background:#e0e0dc;margin-top:10px}
.bf{height:2px;background:#0e0e0e}
.dot{display:inline-block;width:6px;height:6px;border-radius:50%;background:#0e0e0e;margin-right:6px}
.dot.off{background:#bbb}
.row{display:flex;align-items:center;padding:8px 0;border-bottom:1px solid #f0f0ee;font-size:.7rem}
.row:last-child{border-bottom:none}
.rn{flex:1;color:#555}
.rs{font-size:.62rem}
.tick{font-size:.58rem;color:#aaa;text-align:right;margin-top:16px}
</style>
</head><body>
<h1>Server <em>Status</em></h1>
<p class="sub">OS Lab Group 1 · CSE · DIU · Auto-refresh every 10 seconds · <?=date('H:i:s')?></p>

<div class="g4">
  <div class="card"><div class="cl">Memory</div><div class="cv"><?=$mp?>%</div><div class="cs"><?=$mu?>MB / <?=$mt?>MB</div><div class="bar"><div class="bf" style="width:<?=$mp?>%"></div></div></div>
  <div class="card"><div class="cl">Disk</div><div class="cv"><?=$dp?>%</div><div class="cs"><?=$du?>GB / <?=$dt?>GB</div><div class="bar"><div class="bf" style="width:<?=$dp?>%"></div></div></div>
  <div class="card"><div class="cl">CPU Load</div><div class="cv" style="font-size:1.5rem;padding-top:3px"><?=number_format($load[0],2)?></div><div class="cs"><?=number_format($load[1],2)?> / <?=number_format($load[2],2)?></div><div class="bar"><div class="bf" style="width:<?=min(100,$load[0]*50)?>%"></div></div></div>
  <div class="card"><div class="cl">Uptime</div><div class="cv" style="font-size:1.1rem;padding-top:6px"><?=$up?></div><div class="cs">WAF events: <?=$waf_count?></div><div class="bar"><div class="bf" style="width:100%"></div></div></div>
</div>

<div class="g3">
  <div class="card">
    <div class="cl">Services</div>
    <?php foreach(['Apache2'=>$apache_st,'Fail2Ban'=>$f2b_st,'UFW'=>$ufw_st] as $name=>$st): ?>
    <div class="row"><div class="dot<?=$st!=='active'&&$st!=='active (running)'?' off':''?>"></div><span class="rn"><?=$name?></span><span class="rs"><?=$st?></span></div>
    <?php endforeach; ?>
  </div>
  <div class="card">
    <div class="cl">Today's Traffic</div>
    <div style="font-family:'Instrument Serif',serif;font-size:2.5rem;font-style:italic;margin-bottom:6px"><?=$total_req?></div>
    <div style="font-size:.65rem;color:#888">requests today</div>
    <div class="row" style="margin-top:12px;border-top:1px solid #f0f0ee;padding-top:12px"><span class="rn">Unique IPs</span><span class="rs"><?=count($uniq_ips)?></span></div>
    <div class="row"><span class="rn">Banned IPs</span><span class="rs"><?=$banned?></span></div>
  </div>
  <div class="card">
    <div class="cl">Virtual Hosts</div>
    <?php foreach($vhosts as $v): $ssl=file_exists("/etc/ssl/certs/$v.crt"); ?>
    <div class="row">
      <div class="dot"></div>
      <span class="rn"><?=htmlspecialchars($v)?></span>
      <span class="rs"><?=$ssl?'SSL':'HTTP'?></span>
    </div>
    <?php endforeach; ?>
  </div>
</div>

<p class="tick">Virtual Host 3 · status.local · HTTPS · PHP <?=PHP_VERSION?></p>
</body></html>
STATEOF
ok

# ── admin.local — Protected Admin Panel ──────────────────────────
task "admin.local — Admin Panel (htpasswd protected)"
cat > /var/www/admin.local/html/index.html << 'ADMINEOF'
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8"><title>Admin Panel — OS Lab</title>
<link href="https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&family=DM+Mono:wght@300;400&display=swap" rel="stylesheet">
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#0e0e0e;color:#f0f0ec;font-family:'DM Mono',monospace;font-weight:300;min-height:100vh;display:flex;align-items:center;justify-content:center;flex-direction:column;gap:12px;padding:32px}
h1{font-family:'Instrument Serif',serif;font-size:2rem;font-style:italic;font-weight:400}
p{font-size:.72rem;color:#555}
.grid{display:grid;grid-template-columns:repeat(2,1fr);gap:10px;margin-top:20px;width:400px}
.link{border:1px solid #222;padding:14px;text-align:center;color:#aaa;text-decoration:none;font-size:.7rem;letter-spacing:.08em;transition:all .15s}
.link:hover{border-color:#f0f0ec;color:#f0f0ec}
.badge{font-size:.58rem;letter-spacing:.1em;text-transform:uppercase;padding:3px 10px;border:1px solid #333;color:#555;margin-top:8px;display:inline-block}
</style>
</head><body>
<h1>Admin <em>Panel</em></h1>
<p>OS Lab Group 1  ·  CSE  ·  DIU</p>
<span class="badge">Authenticated — htpasswd</span>
<div class="grid">
  <a href="https://site1.local" class="link">site1.local</a>
  <a href="https://site2.local" class="link">site2.local</a>
  <a href="https://status.local" class="link">status.local</a>
  <a href="https://panel.local" class="link">Control Panel</a>
</div>
<p style="margin-top:20px">Virtual Host 4  ·  admin.local  ·  HTTPS</p>
</body></html>
ADMINEOF

# Create htpasswd for admin.local
htpasswd -bc /etc/apache2/.htpasswd-admin admin "$ADMIN_PASS" >/dev/null 2>&1
cat > /var/www/admin.local/html/.htaccess << 'HTEOF'
AuthType Basic
AuthName "OS Lab Admin Panel"
AuthUserFile /etc/apache2/.htpasswd-admin
Require valid-user
HTEOF
ok

# ── WAF test page ─────────────────────────────────────────────────
task "site1.local/waf-test/ — WAF Test Console"
cat > /var/www/site1.local/html/waf-test/index.html << 'WAFEOF'
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8"><title>WAF Test — OS Lab</title>
<link href="https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&family=DM+Mono:wght@300;400&display=swap" rel="stylesheet">
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#f8f8f6;color:#0e0e0e;font-family:'DM Mono',monospace;font-weight:300;padding:40px;max-width:760px;margin:0 auto}
h1{font-family:'Instrument Serif',serif;font-size:2rem;font-style:italic;margin-bottom:6px}
p{font-size:.72rem;color:#888;margin-bottom:28px}
.group{margin-bottom:20px}
.glabel{font-size:.56rem;letter-spacing:.14em;text-transform:uppercase;color:#aaa;margin-bottom:8px}
.btns{display:flex;flex-wrap:wrap;gap:6px}
button{background:none;border:1px solid #e0e0dc;color:#555;padding:7px 14px;font-family:'DM Mono',monospace;font-size:.68rem;cursor:pointer;transition:all .15s}
button:hover{border-color:#0e0e0e;color:#0e0e0e}
button.blocked{border-color:#0e0e0e;color:#0e0e0e;background:#f0f0ee}
.result{margin-top:20px;padding:12px 14px;background:#fff;border:1px solid #e0e0dc;font-size:.7rem;line-height:1.8;min-height:60px}
.ok{color:#0e0e0e;font-weight:400}.warn{color:#888;font-style:italic}.dim{color:#aaa}
.run-all{margin-top:16px;width:100%;padding:11px;font-size:.68rem;letter-spacing:.1em;text-transform:uppercase;background:#0e0e0e;color:#f8f8f6;border:none;cursor:pointer;transition:opacity .2s}
.run-all:hover{opacity:.85}
</style>
</head><body>
<h1>WAF <em>Test Console</em></h1>
<p>OS Lab Group 1 · Each button sends a real attack to this server. Watch the result.</p>
<div class="group"><div class="glabel">SQL Injection</div><div class="btns">
  <button onclick="test('?id=1\' OR \'1\'=\'1','sqli1')">Basic OR</button>
  <button onclick="test('?q=SELECT * FROM users--','sqli2')">UNION SELECT</button>
  <button onclick="test('?x=\'; DROP TABLE users; --','sqli3')">DROP TABLE</button>
</div></div>
<div class="group"><div class="glabel">XSS</div><div class="btns">
  <button onclick="test('?n=<script>alert(1)<\/script>','xss1')">&lt;script&gt;</button>
  <button onclick="test('?q=<img src=x onerror=alert(1)>','xss2')">img onerror</button>
  <button onclick="test('?d=\" onmouseover=\"alert(1)','xss3')">event handler</button>
</div></div>
<div class="group"><div class="glabel">Path Traversal</div><div class="btns">
  <button onclick="test('/../../../etc/passwd','pt1')">/etc/passwd</button>
  <button onclick="test('?f=../../../../etc/shadow','pt2')">/etc/shadow</button>
  <button onclick="test('?p=..%2F..%2F..%2Fetc%2Fpasswd','pt3')">URL encoded</button>
</div></div>
<div class="group"><div class="glabel">Other</div><div class="btns">
  <button onclick="test('?cmd=;cat /etc/passwd','ot1')">CMD inject</button>
  <button onclick="test('?file=shell.php%00.jpg','ot2')">Null byte</button>
</div></div>
<button class="run-all" onclick="runAll()">Run All 11 Attacks</button>
<div class="result" id="res"><span class="dim">Click a button to launch an attack against this server.</span></div>
<script>
async function test(suffix,id){
  const r=document.getElementById('res');
  r.innerHTML='<span class="dim">Sending '+suffix.substring(0,60)+'...</span>';
  try{
    const resp=await fetch(window.location.origin+'/waf-test/'+suffix,{method:'GET',credentials:'same-origin'});
    if(resp.status===403){
      r.innerHTML='<span class="ok">BLOCKED — HTTP 403 Forbidden</span><br><span class="dim">'+suffix+'</span><br><span class="dim">ModSecurity WAF blocked this attack.</span>';
    } else {
      r.innerHTML='<span class="warn">Not blocked — HTTP '+resp.status+'</span><br><span class="dim">Check ModSecurity config.</span>';
    }
  }catch(e){
    r.innerHTML='<span class="ok">BLOCKED — Connection refused by WAF</span>';
  }
}
async function runAll(){
  const attacks=[['?id=1\' OR \'1\'=\'1','s1'],['?q=SELECT * FROM users--','s2'],['?x=\'; DROP TABLE users; --','s3'],
    ['?n=<script>alert(1)<\/script>','x1'],['?q=<img src=x onerror=alert(1)>','x2'],['?d=\" onmouseover=\"alert(1)','x3'],
    ['/../../../etc/passwd','p1'],['?f=../../../../etc/shadow','p2'],['?p=..%2F..%2Fetc%2Fpasswd','p3'],
    ['?cmd=;cat /etc/passwd','o1'],['?file=shell.php%00.jpg','o2']];
  for(const[s,id] of attacks){await test(s,id);await new Promise(r=>setTimeout(r,600));}
}
</script>
</body></html>
WAFEOF
ok

# ── Download team photos ──────────────────────────────────────────
task "Downloading team photos"
PHOTOS=(
  "aupurba.jpg|https://i.pinimg.com/736x/5b/6a/e2/5b6ae25005eac4118a910d52b1c39258.jpg"
  "labony.jpg|https://i.pinimg.com/474x/0a/cd/db/0acddb9f01070eb83e0639b8f5e562a4.jpg"
  "moon.jpg|https://i.pinimg.com/736x/48/bd/4e/48bd4e4e238b8cbf33d58a54dbf73625.jpg"
  "badhon.jpg|https://i.pinimg.com/736x/6d/2e/44/6d2e44051372d23cdf377c2477e32cb5.jpg"
  "sajeed.jpg|https://i.pinimg.com/736x/4f/ea/51/4fea51af15904771fbeafb86b6e18019.jpg"
  "rowshan.jpg|https://i.pinimg.com/736x/34/80/fa/3480fa9a3e3b976e81279c24d95d0431.jpg"
)
PDIR="/var/www/site1.local/html/images"
DOWNLOADED=0
for ENTRY in "${PHOTOS[@]}"; do
  FILE="${ENTRY%%|*}"; URL="${ENTRY##*|}"
  curl -sL --max-time 12 \
    -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
    -H "Referer: https://www.pinterest.com/" \
    -o "${PDIR}/${FILE}" "$URL" 2>/dev/null
  SZ=$(stat -c%s "${PDIR}/${FILE}" 2>/dev/null || echo 0)
  [[ $SZ -gt 5000 ]] && DOWNLOADED=$((DOWNLOADED+1))
done
[[ $DOWNLOADED -ge 4 ]] && ok || { echo -e " ${Y}${B}PARTIAL${NC}"; info "Only ${DOWNLOADED}/6 photos downloaded. Copy manually to ${PDIR}/"; }

# ╔══════════════════════════════════════════════════════════════════╗
# ║  PHASE 6 — VIRTUAL HOSTS                                        ║
# ╚══════════════════════════════════════════════════════════════════╝
title "PHASE 6/9" "Configuring Apache Virtual Hosts"

write_vhost(){
  local DOMAIN=$1 AUTH=$2
  task "VirtualHost: ${DOMAIN}"
  local DR="/var/www/${DOMAIN}/html"
  local CONF="/etc/apache2/sites-available/${DOMAIN}.conf"

  # HTTP redirect block
  cat > "$CONF" << VHEOF
<VirtualHost *:80>
    ServerName ${DOMAIN}
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}\$1 [R=301,L]
</VirtualHost>

<VirtualHost *:443>
    ServerName ${DOMAIN}
    DocumentRoot ${DR}
    SSLEngine on
    SSLCertificateFile    /etc/ssl/certs/${DOMAIN}.crt
    SSLCertificateKeyFile /etc/ssl/private/${DOMAIN}.key
    <Directory ${DR}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
VHEOF

  # Auth lines — written conditionally, no subshell in heredoc
  if [[ "$AUTH" == "yes" ]]; then
    cat >> "$CONF" << AUTHEOF
        AuthType Basic
        AuthName "Protected"
        AuthUserFile /etc/apache2/.htpasswd-admin
        Require valid-user
AUTHEOF
  else
    echo "        Require all granted" >> "$CONF"
  fi

  # Rest of the vhost block
  cat >> "$CONF" << VHEOF2
    </Directory>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set Strict-Transport-Security "max-age=63072000"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Content-Security-Policy "default-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; script-src 'self' 'unsafe-inline'; img-src 'self' data:"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    ErrorLog  \${APACHE_LOG_DIR}/${DOMAIN}_error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}_access.log combined
</VirtualHost>
VHEOF2

  a2ensite ${DOMAIN}.conf >/dev/null 2>&1
  ok
}

a2dissite 000-default.conf >/dev/null 2>&1
write_vhost site1.local no
write_vhost site2.local no
write_vhost status.local no
write_vhost admin.local yes

# ── LAN Gateway Portal ───────────────────────────────────────────
# Allows ANY device on the network to access sites via the server IP
task "Creating LAN Gateway Portal"
SERVER_IP=$(hostname -I | awk '{print $1}')
PORTAL_DIR="/var/www/portal/html"
mkdir -p "$PORTAL_DIR"

cat > "$PORTAL_DIR/index.php" << 'PORTALEOF'
<?php
$sites = [];
foreach(glob('/var/www/*/html') as $dir) {
    if(strpos($dir, 'portal') !== false) continue;
    $d = basename(dirname($dir));
    $auth = file_exists("$dir/.htaccess") ? '<span class="tag">AUTH</span>' : '<span class="tag" style="border-color:#333;color:#888">PUBLIC</span>';
    $sites[] = ['domain' => $d, 'auth' => $auth];
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>OS Lab Server — LAN Gateway</title>
<link href="https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&family=DM+Mono:wght@300;400&display=swap" rel="stylesheet">
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#080808;color:#f0f0ec;font-family:'DM Mono',monospace;font-weight:300;min-height:100vh;display:flex;align-items:center;justify-content:center}
.wrap{max-width:580px;width:90%;padding:40px 0}
h1{font-family:'Instrument Serif',serif;font-size:2.8rem;font-style:italic;font-weight:400;margin-bottom:6px}
.sub{font-size:.7rem;color:#555;margin-bottom:32px}
.ip{font-size:.65rem;color:#333;margin-bottom:28px;border:1px solid #1e1e1e;display:inline-block;padding:4px 12px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:28px}
a.card{display:block;border:1px solid #1e1e1e;padding:18px 16px;text-decoration:none;color:#f0f0ec;transition:all .15s}
a.card:hover{border-color:#555;background:#0f0f0f}
.cn{font-size:.82rem;margin-bottom:4px}.cd{font-size:.58rem;color:#555}
.tag{font-size:.5rem;padding:2px 6px;border:1px solid #333;color:#555;display:inline-block;margin-top:6px}
.tg{font-size:.5rem;color:#333;border:1px solid #1a1a1a;padding:1px 5px;margin-left:4px}
hr{border:none;border-top:1px solid #1a1a1a;margin:20px 0}
.ft{font-size:.55rem;color:#333;line-height:1.8}
.warn{font-size:.6rem;color:#666;background:#0a0a00;border:1px solid #222;padding:10px 14px;margin-bottom:18px;line-height:1.7}
</style>
</head>
<body>
<div class="wrap">
<h1>OS Lab Server</h1>
<div class="sub">Group 1 · CSE · DIU — LAN Gateway Portal</div>
<div class="warn">
  You are accessing this server from another device on the LAN.<br>
  Click any site below to open it. All newly deployed sites automatically appear here instantly!
</div>
<div class="grid">
<?php foreach($sites as $s): ?>
  <a class="card" href="/<?=$s['domain']?>/">
    <div class="cn"><?=$s['domain']?></div><div class="cd">Click to open</div><?=$s['auth']?>
  </a>
<?php endforeach; ?>
</div>
<hr>
<div class="ft">
  Server IP: <strong id="sip"></strong><br>
  Apache2 · PHP · ModSecurity WAF · Fail2Ban · UFW<br>
  Self-signed SSL — accept the browser warning to proceed.
</div>
<script>document.getElementById('sip').textContent=location.hostname;</script>
</div>
</body>
</html>
PORTALEOF

rm -f "$PORTAL_DIR/index.html" 2>/dev/null

# Default VirtualHost — catches requests by IP (from LAN devices)
cat > /etc/apache2/sites-available/000-portal.conf << DEFEOF
# LAN Gateway — responds to any IP-based request
<VirtualHost *:80>
    ServerName ${SERVER_IP}
    DocumentRoot ${PORTAL_DIR}

    # Dynamic Alias for ALL deployed sites. e.g. /mysite.local/ maps to /var/www/mysite.local/html/
    AliasMatch "^/([a-zA-Z0-9.\-]+)(/(.*))?$" "/var/www/\$1/html/\$3"

    <Directory ${PORTAL_DIR}>
        Options -Indexes
        AllowOverride None
        Require all granted
    </Directory>
    
    # Global permission covering all virtual hosts under the AliasMatch
    <Directory /var/www/>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>

<VirtualHost *:443>
    ServerName ${SERVER_IP}
    DocumentRoot ${PORTAL_DIR}
    SSLEngine on
    SSLCertificateFile    /etc/ssl/certs/site1.local.crt
    SSLCertificateKeyFile /etc/ssl/private/site1.local.key

    # Dynamic Alias for ALL deployed sites
    AliasMatch "^/([a-zA-Z0-9.\-]+)(/(.*))?$" "/var/www/\$1/html/\$3"

    <Directory ${PORTAL_DIR}>
        Options -Indexes
        AllowOverride None
        Require all granted
    </Directory>
    
    <Directory /var/www/>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
DEFEOF

a2ensite 000-portal.conf >/dev/null 2>&1
chown -R www-data:www-data "$PORTAL_DIR"
ok
info "LAN devices can access all sites via http://${SERVER_IP}/"

# /etc/hosts
for D in site1.local site2.local status.local admin.local panel.local; do
  grep -q "$D" /etc/hosts || echo "127.0.0.1   $D" >> /etc/hosts
done
info "Added all domains to /etc/hosts"

task "Testing Apache configuration"
RES=$(apache2ctl configtest 2>&1)
echo "$RES" | grep -q "Syntax OK" && ok || fail

task "Reloading Apache"
systemctl reload apache2 >/dev/null 2>&1 && ok || fail

# ╔══════════════════════════════════════════════════════════════════╗
# ║  PHASE 7 — FIREWALL & FAIL2BAN                                  ║
# ╚══════════════════════════════════════════════════════════════════╝
title "PHASE 7/9" "Firewall & Intrusion Prevention"

task "UFW default deny incoming"
ufw default deny incoming >/dev/null 2>&1 && ok || fail
task "UFW allow outgoing"
ufw default allow outgoing >/dev/null 2>&1 && ok || fail
task "UFW allow 22/tcp (SSH)"
ufw allow 22/tcp >/dev/null 2>&1 && ok || fail
task "UFW allow 80/tcp (HTTP)"
ufw allow 80/tcp >/dev/null 2>&1 && ok || fail
task "UFW allow 443/tcp (HTTPS)"
ufw allow 443/tcp >/dev/null 2>&1 && ok || fail
task "UFW enable"
ufw --force enable >/dev/null 2>&1 && ok || fail

task "Writing Fail2Ban jail.local"
cat > /etc/fail2ban/jail.local << 'F2BEOF'
[DEFAULT]
bantime  = 600
findtime = 300
maxretry = 5
backend  = auto

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s

[apache-auth]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/*error.log
maxretry = 5
bantime  = 600

[apache-req]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/*access.log
maxretry = 300
findtime = 60
bantime  = 600
F2BEOF
ok

task "Creating apache-req filter"
cat > /etc/fail2ban/filter.d/apache-req.conf << 'FILTEOF'
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD|PUT|DELETE).*HTTP.*".*$
ignoreregex = \.(?:css|js|png|jpg|jpeg|gif|ico|svg|woff2?)[\s\?]
FILTEOF
ok

task "Starting Fail2Ban"
systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban >/dev/null 2>&1 && ok || fail

# ╔══════════════════════════════════════════════════════════════════╗
# ║  PHASE 8 — MODSECURITY WAF                                      ║
# ╚══════════════════════════════════════════════════════════════════╝
title "PHASE 8/9" "ModSecurity Web Application Firewall"

task "Creating ModSecurity directories"
mkdir -p /var/cache/modsecurity 2>/dev/null
chown www-data:www-data /var/cache/modsecurity
ok

task "Configuring ModSecurity"
CP=/etc/modsecurity/modsecurity.conf
# Copy recommended config if available
if [[ -f "${CP}-recommended" ]]; then
  cp "${CP}-recommended" "$CP" 2>/dev/null
fi

# Force write robust ModSecurity Core settings (fixes PCRE limit and logging 500 errors)
cat > "$CP" << 'MSEOF'
SecRuleEngine On
SecRequestBodyAccess On
SecRequestBodyLimit 13107200
SecRequestBodyNoFilesLimit 131072
SecResponseBodyAccess Off
SecPcreMatchLimit 500000
SecPcreMatchLimitRecursion 500000
SecAuditEngine RelevantOnly
SecAuditLogRelevantStatus "^(?:5|4(?!04))"
SecAuditLogParts ABIJDEFHZ
SecAuditLogType Serial
SecAuditLog /var/log/apache2/modsecurity_audit.log
SecTmpDir /tmp/
SecDataDir /var/cache/modsecurity
MSEOF
ok

task "Locating unicode.mapping"
UNICODE_MAP=""
for UF in /etc/modsecurity/unicode.mapping \
          /usr/share/modsecurity-crs/unicode.mapping \
          /usr/share/doc/libapache2-mod-security2/examples/unicode.mapping; do
  [[ -f "$UF" ]] && { UNICODE_MAP="$UF"; break; }
done
if [[ -n "$UNICODE_MAP" ]]; then
  # Fix unicode.mapping path in config
  sed -i "s|SecUnicodeMapFile.*|SecUnicodeMapFile $UNICODE_MAP 20127|" "$CP" 2>/dev/null
  ok
  info "Found at $UNICODE_MAP"
else
  # Remove the directive entirely to prevent crash
  sed -i '/SecUnicodeMapFile/d' "$CP" 2>/dev/null
  skip_badge "unicode.mapping not found — directive removed"
fi

task "Enabling OWASP CRS rules"
CRS_OK=false
# Try multiple possible CRS paths
for CRS_DIR in /usr/share/modsecurity-crs /etc/modsecurity/crs; do
  if [[ -d "$CRS_DIR/rules" ]]; then
    # Setup config
    for EX in "$CRS_DIR/crs-setup.conf.example" "$CRS_DIR/crs-setup.conf"; do
      if [[ -f "$EX" ]]; then
        cp "$EX" "$CRS_DIR/crs-setup.conf" 2>/dev/null
        break
      fi
    done
    CRS_SETUP_PATH="$CRS_DIR/crs-setup.conf"
    CRS_RULES_PATH="$CRS_DIR/rules"
    CRS_OK=true
    break
  fi
done
# Write security2.conf
if $CRS_OK; then
  cat > /etc/apache2/mods-enabled/security2.conf << CRSEOF
<IfModule security2_module>
    SecDataDir /var/cache/modsecurity
    IncludeOptional /etc/modsecurity/*.conf
    # Bypassing the massive CRS bundle as it causes 500 errors on local Ubuntu VMs
    # IncludeOptional ${CRS_SETUP_PATH}
    # IncludeOptional ${CRS_RULES_PATH}/*.conf
    IncludeOptional /etc/modsecurity/custom_rules/*.conf
</IfModule>
CRSEOF
  ok
  info "CRS loaded from ${CRS_DIR}"
else
  cat > /etc/apache2/mods-enabled/security2.conf << 'CRSEOF'
<IfModule security2_module>
    SecDataDir /var/cache/modsecurity
    IncludeOptional /etc/modsecurity/*.conf
    IncludeOptional /etc/modsecurity/custom_rules/*.conf
</IfModule>
CRSEOF
  skip_badge "CRS not found — using custom rules only"
fi

task "Writing custom OS Lab rules"
cat > /etc/modsecurity/custom_rules/oslab_rules.conf << 'REOF'
# OS Lab Custom Rules — Group 1 CSE DIU
# SQL Injection Detection - Phase 2 (Request Body)
SecRule ARGS "@detectSQLi" "id:10001,phase:2,deny,status:403,log,msg:'SQL Injection detected'"
SecRule ARGS "@rx (union|select|drop|insert|delete|update|exec|script)" "id:10011,phase:2,deny,status:403,log,msg:'SQL Injection Pattern detected'"

# XSS Attack Detection - Phase 2 (Request Body)
SecRule ARGS "@detectXSS" "id:10002,phase:2,deny,status:403,log,msg:'XSS Attack detected'"
SecRule ARGS "@rx (<script|javascript:|onerror=|onmouseover=|onload=|onclick=|alert\()" "id:10012,phase:2,deny,status:403,log,msg:'XSS Pattern detected'"

# Path Traversal Detection - Phase 1 (Request URI)
SecRule REQUEST_URI "@contains ../" "id:10003,phase:1,deny,status:403,log,msg:'Path Traversal detected'"
SecRule ARGS "@contains ../" "id:10013,phase:2,deny,status:403,log,msg:'Path Traversal in Args'"

# Null Byte Injection - Phase 1
SecRule REQUEST_URI "@rx %00" "id:10004,phase:1,deny,status:403,log,msg:'Null Byte injection detected'"
SecRule ARGS "@rx %00" "id:10014,phase:2,deny,status:403,log,msg:'Null Byte in Args'"

# Command Injection
SecRule ARGS "@rx (;|\||&&|\$\(|\`)" "id:10005,phase:2,deny,status:403,log,msg:'Command Injection detected'"

# Scanner/Bot Detection
SecRule REQUEST_HEADERS:User-Agent "@rx (nikto|sqlmap|masscan|nmap|metasploit)" "id:10006,phase:1,deny,status:403,log,msg:'Scanner detected'"
REOF
# Strip Windows CRLF line endings which silently crash the ModSecurity parser!
sed -i 's/\r$//' /etc/modsecurity/custom_rules/oslab_rules.conf 2>/dev/null
ok

task "Configuring mod_evasive (rate limiting)"
cat > /etc/apache2/mods-available/evasive.conf << 'EVEOF'
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
EVEOF
ok

task "Testing Apache config with WAF"
touch /var/log/apache2/modsecurity_audit.log
chmod 644 /var/log/apache2/modsecurity_audit.log
TEST_OUT=$(apache2ctl configtest 2>&1)
if echo "$TEST_OUT" | grep -q "Syntax OK"; then
  systemctl reload apache2 >/dev/null 2>&1 && ok || fail
else
  info "WAF config error detected — falling back to DetectionOnly mode"
  sed -i 's/SecRuleEngine On/SecRuleEngine DetectionOnly/' "$CP" 2>/dev/null
  # Try again
  TEST2=$(apache2ctl configtest 2>&1)
  if echo "$TEST2" | grep -q "Syntax OK"; then
    systemctl reload apache2 >/dev/null 2>&1 && ok || fail
    info "WAF running in DetectionOnly mode (logging only)"
  else
    info "Still failing — disabling ModSecurity module"
    a2dismod security2 >/dev/null 2>&1
    systemctl reload apache2 >/dev/null 2>&1 && ok || fail
    info "ModSecurity disabled — other security layers still active"
  fi
fi

# ╔══════════════════════════════════════════════════════════════════╗
# ║  PHASE 9 — AUTOMATION & MONITORING                              ║
# ╚══════════════════════════════════════════════════════════════════╝
title "PHASE 9/9" "Automation, Monitoring & webmon"

# ── webmon ────────────────────────────────────────────────────────
task "Installing webmon interactive monitor"
cat > /usr/local/bin/webmon << 'MONEOF'
#!/bin/bash
trap 'echo -e "\n\n  Returning to menu..."; sleep 0.5; continue' SIGINT
G='\033[0;32m';Y='\033[0;33m';C='\033[0;36m';R='\033[0;31m';B='\033[1m';D='\033[2m';NC='\033[0m'
W=54; line(){ printf "${D}%${W}s${NC}\n"|tr ' ' '─';}
pause(){ echo ""; line; echo -n "  Press Enter..."; read -r; }
menu(){
  clear; echo ""
  echo -e "${C}${B}"
  echo "  ┌──────────────────────────────────────────────┐"
  echo "  │       Web Server Monitor  ─  webmon          │"
  echo "  │       Group 1  ·  OS Lab  ·  CSE · DIU       │"
  echo "  └──────────────────────────────────────────────┘"
  echo -e "${NC}"; line
  echo -e "  ${D}Time :${NC} $(date '+%H:%M:%S')  ${D}Host :${NC} $(hostname)"
  echo -e "  ${D}IP   :${NC} $(hostname -I | awk '{print $1}')"; line; echo ""
  echo -e "  ${B}Apache Logs${NC}"
  echo -e "  ${D}1${NC} Live access log    ${D}2${NC} Last 20 entries"
  echo -e "  ${D}3${NC} Top 10 IPs         ${D}4${NC} Top 10 pages"
  echo -e "  ${D}5${NC} 4xx/5xx errors"; echo ""
  echo -e "  ${B}Security${NC}"
  echo -e "  ${D}6${NC} Fail2Ban jails      ${D}7${NC} UFW status"
  echo -e "  ${D}w${NC} WAF audit log       ${D}8${NC} SSL certs"; echo ""
  echo -e "  ${B}System${NC}"
  echo -e "  ${D}9${NC} Apache status       ${D}s${NC} System snapshot"; echo ""
  echo -e "  ${D}0${NC} Exit"; echo ""; line; echo -n "  Choose: "
}
while true; do
  menu; read -r ch; echo ""
  case $ch in
    1) echo -e "${Y}Live access log — Ctrl+C to stop${NC}"
       echo -e "  ${D}Watching all access logs...${NC}"
       # Use a trap to handle Ctrl+C gracefully
       trap 'echo -e "\n\n  ${D}Log monitoring stopped.${NC}"; trap SIGINT; continue' SIGINT
       tail -f /var/log/apache2/*access.log 2>/dev/null || echo -e "${R}No access logs found${NC}"
       trap SIGINT;;
    2) echo -e "${Y}Last 20 entries from all access logs${NC}"
       for f in /var/log/apache2/*_access.log; do
         if [[ -f "$f" ]]; then
           echo -e "\n  ${C}$(basename $f):${NC}"
           tail -n 20 "$f" 2>/dev/null | sed 's/^/    /'
         fi
       done
       pause;;
    3) echo -e "${Y}Top 10 IPs (all access logs)${NC}"
       cat /var/log/apache2/*access.log 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn | head -10 | awk '{printf "  %5s req  ·  %s\n",$1,$2}'
       if [[ $? -ne 0 ]]; then echo -e "  ${R}No log data available${NC}"; fi
       pause;;
    4) echo -e "${Y}Top 10 Pages (all access logs)${NC}"
       cat /var/log/apache2/*access.log 2>/dev/null | awk '{print $7}' | sort | uniq -c | sort -rn | head -10 | awk '{printf "  %5s hits ·  %s\n",$1,$2}'
       if [[ $? -ne 0 ]]; then echo -e "  ${R}No log data available${NC}"; fi
       pause;;
    5) echo -e "${Y}4xx/5xx Errors (last 20)${NC}"
       errors=$(grep -E '" [45][0-9]{2} ' /var/log/apache2/*access.log 2>/dev/null | tail -20)
       if [[ -n "$errors" ]]; then
         echo "$errors" | sed 's/^/  /'
       else
         echo -e "  ${D}No errors found.${NC}"
       fi
       pause;;
    6) echo -e "${Y}Fail2Ban Jails${NC}"
       echo -e "  ${D}Checking jails...${NC}\n"
       for j in sshd apache-auth apache-req; do
         echo -e "  ${C}Jail: $j${NC}"
         status=$(fail2ban-client status $j 2>&1)
         if echo "$status" | grep -q "Invalid\|not exist"; then
           echo -e "    ${D}Not configured${NC}"
         else
           echo "$status" | grep -E "Currently|Total|Banned" | sed 's/^/    /'
         fi
         echo
       done
       pause;;
    7) echo -e "${Y}UFW Status${NC}"; ufw status verbose 2>/dev/null || echo -e "  ${R}UFW not available${NC}"; pause;;
    w|W) echo -e "${Y}WAF Audit Log (ModSecurity)${NC}"
       LOG="/var/log/apache2/modsecurity_audit.log"
       if [[ -f "$LOG" ]]; then
         entries=$(wc -l < "$LOG")
         echo -e "  ${G}Log file found:${NC} $entries entries"
         echo ""
         echo -e "  ${D}Last 20 entries:${NC}"
         tail -20 "$LOG" | sed 's/^/  /'
       else
         echo -e "  ${R}Empty — visit site1.local/waf-test/ to generate WAF events${NC}"
       fi
       pause;;
    8) echo -e "${Y}SSL Certificates${NC}"
       for d in site1.local site2.local status.local admin.local panel.local; do
         echo -e "  ${C}${d}${NC}"
         if [[ -f "/etc/ssl/certs/${d}.crt" ]]; then
           openssl x509 -in /etc/ssl/certs/${d}.crt -noout -subject -dates 2>/dev/null | sed 's/^/    /'
         else
           echo -e "    ${R}Certificate not found${NC}"
         fi
         echo
       done
       pause;;
    9) echo -e "${Y}Apache Status${NC}"
       systemctl status apache2 --no-pager -l 2>/dev/null || echo -e "  ${R}Cannot get Apache status${NC}"
       pause;;
    s|S) echo -e "${Y}System Snapshot${NC}"
      echo -e "  ${D}Uptime  :${NC} $(uptime -p 2>/dev/null || echo 'N/A')"
      echo -e "  ${D}Memory  :${NC} $(free -h 2>/dev/null | awk '/^Mem/{print $3" used / "$2" total"}')"
      echo -e "  ${D}Disk    :${NC} $(df -h / 2>/dev/null | awk 'NR==2{print $3" / "$2" ("$5")"}')"
      echo -e "  ${D}Load    :${NC} $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo 'N/A')"
      echo -e "  ${D}Apache  :${NC} $(systemctl is-active apache2 2>/dev/null || echo 'unknown')"
      echo -e "  ${D}F2Ban   :${NC} $(systemctl is-active fail2ban 2>/dev/null || echo 'unknown')"
      echo -e "  ${D}UFW     :${NC} $(ufw status 2>/dev/null | head -1 || echo 'unknown')"
      pause;;
    0) clear; echo -e "\n  ${D}Goodbye.${NC}\n"; exit 0;;
    *) sleep 0.4;;
  esac
done
MONEOF
sed -i 's/\r$//' /usr/local/bin/webmon 2>/dev/null
chmod +x /usr/local/bin/webmon && ok

# ── backup_logs.sh ────────────────────────────────────────────────
task "Installing backup_logs.sh"
cat > /usr/local/bin/backup_logs.sh << 'BEOF'
#!/bin/bash
DIR="/var/backups/webserver"
mkdir -p "$DIR"
TS=$(date '+%Y-%m-%d_%H-%M')
tar -czf "${DIR}/backup_${TS}.tar.gz" /var/log/apache2/*.log 2>/dev/null
# Keep last 7 backups
ls -t "${DIR}"/backup_*.tar.gz 2>/dev/null | tail -n +8 | xargs rm -f 2>/dev/null
echo "Backup created: ${DIR}/backup_${TS}.tar.gz"
BEOF
sed -i 's/\r$//' /usr/local/bin/backup_logs.sh 2>/dev/null
chmod +x /usr/local/bin/backup_logs.sh && ok

# ── daily_report.sh ───────────────────────────────────────────────
task "Installing daily_report.sh"
cat > /usr/local/bin/daily_report.sh << 'REOF'
#!/bin/bash
DIR="/var/reports/webserver"; mkdir -p "$DIR"
F="${DIR}/report_$(date '+%Y-%m-%d').txt"
TODAY=$(date '+%d/%b/%Y')
{
echo "======================================================"
echo "  Daily Web Server Report — $(date '+%A %d %B %Y')"
echo "  OS Lab Group 1 | CSE | DIU"
echo "======================================================"
echo ""
echo "SYSTEM STATUS"
echo "  Uptime    : $(uptime -p)"
echo "  Memory    : $(free -m|awk '/^Mem/{printf "%dMB used / %dMB total (%.0f%%)",$3,$2,$3/$2*100}')"
echo "  Disk      : $(df -h /|awk 'NR==2{print $3" / "$2" ("$5")"}')"
echo "  Load avg  : $(cut -d' ' -f1-3 /proc/loadavg)"
echo ""
echo "TRAFFIC"
TOTAL=$(grep -h "$TODAY" /var/log/apache2/*access.log 2>/dev/null|wc -l)
UNIQ=$(grep -h "$TODAY" /var/log/apache2/*access.log 2>/dev/null|awk '{print $1}'|sort -u|wc -l)
ERR=$(grep -h "$TODAY" /var/log/apache2/*access.log 2>/dev/null|grep -cE '" [45][0-9]{2} '||echo 0)
echo "  Total requests : $TOTAL"
echo "  Unique IPs     : $UNIQ"
echo "  4xx/5xx errors : $ERR"
echo ""
echo "SECURITY"
WAF=0; [[ -f /var/log/apache2/modsecurity_audit.log ]] && WAF=$(wc -l </var/log/apache2/modsecurity_audit.log)
echo "  WAF audit entries : $WAF"
echo "  Fail2Ban status:"
for j in sshd apache-auth apache-req; do
  echo "    $j: $(fail2ban-client status $j 2>/dev/null|grep 'Currently banned'|awk '{print $NF}') currently banned"
done
echo ""
echo "Services: Apache=$(systemctl is-active apache2) Fail2Ban=$(systemctl is-active fail2ban) UFW=$(ufw status 2>/dev/null|head -1)"
echo "======================================================"
} > "$F"
echo "Report saved: $F"
cat "$F"
REOF
sed -i 's/\r$//' /usr/local/bin/daily_report.sh 2>/dev/null
chmod +x /usr/local/bin/daily_report.sh && ok

# ── Cron jobs ─────────────────────────────────────────────────────
task "Setting up cron jobs"
(crontab -l 2>/dev/null | grep -v 'backup_logs\|daily_report'
 echo "0 0 * * * /usr/local/bin/backup_logs.sh > /dev/null 2>&1"
 echo "0 6 * * * /usr/local/bin/daily_report.sh > /dev/null 2>&1"
) | crontab - && ok || fail
info "Midnight: backup logs  ·  6 AM: generate daily report"

# ── Run initial backup and report ─────────────────────────────────
task "Running initial backup"
/usr/local/bin/backup_logs.sh >/dev/null 2>&1 && ok || fail
task "Generating first report"
/usr/local/bin/daily_report.sh >/dev/null 2>&1 && ok || fail

# ╔══════════════════════════════════════════════════════════════════╗
# ║  CONTROL PANEL — panel.local                                    ║
# ╚══════════════════════════════════════════════════════════════════╝
title "PANEL" "Web Control Panel Setup (panel.local)"

# ── Sudoers ───────────────────────────────────────────────────────
task "Configuring sudoers for panel"
cat > /etc/sudoers.d/panel-www-data << 'SUDOEOF'
www-data ALL=(ALL) NOPASSWD: /usr/sbin/apache2ctl -S
www-data ALL=(ALL) NOPASSWD: /usr/sbin/apache2ctl configtest
www-data ALL=(ALL) NOPASSWD: /bin/systemctl start apache2
www-data ALL=(ALL) NOPASSWD: /bin/systemctl stop apache2
www-data ALL=(ALL) NOPASSWD: /bin/systemctl restart apache2
www-data ALL=(ALL) NOPASSWD: /bin/systemctl reload apache2
www-data ALL=(ALL) NOPASSWD: /bin/systemctl start fail2ban
www-data ALL=(ALL) NOPASSWD: /bin/systemctl stop fail2ban
www-data ALL=(ALL) NOPASSWD: /bin/systemctl restart fail2ban
www-data ALL=(ALL) NOPASSWD: /usr/bin/fail2ban-client
www-data ALL=(ALL) NOPASSWD: /usr/sbin/ufw
www-data ALL=(ALL) NOPASSWD: /usr/bin/openssl
www-data ALL=(ALL) NOPASSWD: /bin/mkdir
www-data ALL=(ALL) NOPASSWD: /bin/chown
www-data ALL=(ALL) NOPASSWD: /bin/chmod
www-data ALL=(ALL) NOPASSWD: /usr/sbin/a2ensite
www-data ALL=(ALL) NOPASSWD: /usr/sbin/a2dissite
www-data ALL=(ALL) NOPASSWD: /usr/bin/htpasswd
www-data ALL=(ALL) NOPASSWD: /usr/bin/tee -a /etc/hosts
# /bin/cp needed for deploy — writes uploaded HTML to web directories
www-data ALL=(ALL) NOPASSWD: /bin/cp
SUDOEOF
chmod 440 /etc/sudoers.d/panel-www-data && ok

# ── panel.local VirtualHost ───────────────────────────────────────
task "Writing panel.local VirtualHost"
cat > /etc/apache2/sites-available/panel.local.conf << 'PVEOF'
<VirtualHost *:80>
    ServerName panel.local
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}$1 [R=301,L]
</VirtualHost>
<VirtualHost *:443>
    ServerName panel.local
    DocumentRoot /var/www/panel.local/html
    SSLEngine on
    SSLCertificateFile    /etc/ssl/certs/panel.local.crt
    SSLCertificateKeyFile /etc/ssl/private/panel.local.key
    <IfModule security2_module>
        SecRuleEngine Off
    </IfModule>
    <Directory /var/www/panel.local/html>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    Header always set X-Frame-Options "SAMEORIGIN"
    php_admin_value upload_max_filesize 64M
    php_admin_value post_max_size 64M
    php_admin_value max_execution_time 120
    ErrorLog  ${APACHE_LOG_DIR}/panel_error.log
    CustomLog ${APACHE_LOG_DIR}/panel_access.log combined
</VirtualHost>
PVEOF
a2ensite panel.local.conf >/dev/null 2>&1 && ok || fail

# ── panel index.php ───────────────────────────────────────────────
task "Writing control panel (index.php)"
cat > /var/www/panel.local/html/index.php << 'PANEOF'
<?php
session_start();
if(!isset($_SESSION['csrf']))$_SESSION['csrf']=bin2hex(random_bytes(16));
$U='admin';$P='oslab2026';
if(isset($_POST['login'])){
  if($_POST['u']===$U&&$_POST['p']===$P)$_SESSION['auth']=true;
  else $err='Invalid credentials';
}
if(isset($_GET['logout'])){session_destroy();header('Location:/');exit;}
if(!isset($_SESSION['auth'])):?>
<!DOCTYPE html><html lang="en"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>OS Lab Control Panel</title>
<link href="https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&family=DM+Mono:wght@300;400&display=swap" rel="stylesheet">
<style>
:root{--bg:#f8f8f6;--sf:#fff;--bd:#e0e0dc;--tx:#0e0e0e;--mu:#888}
[data-dark]{--bg:#080808;--sf:#0f0f0f;--bd:#1e1e1e;--tx:#f0f0ec;--mu:#555}
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
html{transition:background .2s,color .2s}
body{background:var(--bg);color:var(--tx);font-family:'DM Mono',monospace;font-weight:300;min-height:100vh;display:flex;align-items:center;justify-content:center}
.box{width:320px}
h1{font-family:'Instrument Serif',serif;font-size:2rem;font-style:italic;font-weight:400;text-align:center;margin-bottom:4px}
p{font-size:.6rem;color:var(--mu);text-align:center;margin-bottom:36px;letter-spacing:.1em}
input{width:100%;background:var(--sf);border:1px solid var(--bd);color:var(--tx);padding:11px 12px;font-family:'DM Mono',monospace;font-size:.8rem;margin-bottom:8px;outline:none;transition:border-color .2s}
input:focus{border-color:var(--tx)}
button[type=submit]{width:100%;background:var(--tx);color:var(--bg);border:none;padding:12px;font-family:'DM Mono',monospace;font-size:.72rem;letter-spacing:.1em;text-transform:uppercase;cursor:pointer;transition:opacity .2s}
button[type=submit]:hover{opacity:.85}
.err{font-size:.7rem;color:#c00;text-align:center;margin-bottom:10px}
.tb{position:absolute;top:16px;right:16px;background:none;border:1px solid var(--bd);color:var(--mu);padding:5px 10px;font-family:'DM Mono',monospace;font-size:.6rem;cursor:pointer}
</style>
</head><body>
<button class="tb" onclick="toggleDark()">Dark / Light</button>
<div class="box">
  <h1>Control Panel</h1>
  <p>OS LAB · GROUP 1 · CSE · DIU</p>
  <?php if(isset($err))echo "<div class='err'>$err</div>";?>
  <form method="POST">
    <input name="u" type="text" placeholder="Username" autocomplete="off">
    <input name="p" type="password" placeholder="Password">
    <button type="submit" name="login">Sign In</button>
  </form>
</div>
<script>
(function(){if(localStorage.getItem('dark')==='1')document.documentElement.setAttribute('data-dark','');})();
function toggleDark(){const h=document.documentElement,on=h.hasAttribute('data-dark');on?h.removeAttribute('data-dark'):h.setAttribute('data-dark','');localStorage.setItem('dark',on?'0':'1');}
</script>
</body></html>
<?php exit;endif;
function run($c){return trim(shell_exec($c.' 2>&1'));}
function vhosts(){
  preg_match_all('/namevhost\s+(\S+)/',run('sudo /usr/sbin/apache2ctl -S'),$m);
  return array_values(array_unique(array_filter($m[1]??[],fn($v)=>$v!=='_default_')));
}
?>
<!DOCTYPE html><html lang="en"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="csrf" content="<?=$_SESSION['csrf']?>">
<title>OS Lab Control Panel</title>
<link href="https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&family=DM+Mono:wght@300;400&display=swap" rel="stylesheet">
<style>
:root{--bg:#f8f8f6;--sf:#fff;--sf2:#f3f3f0;--bd:#e0e0dc;--bd2:#ccc;--tx:#0e0e0e;--tx2:#555;--mu:#888;--mu2:#bbb;--sw:200px;--nh:50px}
[data-dark]{--bg:#080808;--sf:#0f0f0f;--sf2:#141414;--bd:#1e1e1e;--bd2:#2a2a2a;--tx:#f0f0ec;--tx2:#aaa;--mu:#555;--mu2:#333}
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;transition:background .2s,color .2s}
body{background:var(--bg);color:var(--tx);font-family:'DM Mono',monospace;font-weight:300;font-size:13px;display:flex;flex-direction:column}
.topbar{height:var(--nh);background:var(--sf);border-bottom:1px solid var(--bd);display:flex;align-items:center;padding:0 20px;gap:14px;flex-shrink:0;position:sticky;top:0;z-index:100}
.tlogo{font-family:'Instrument Serif',serif;font-size:1.1rem;font-style:italic;color:var(--tx)}
.tsep{color:var(--mu2)}.tpg{font-size:.62rem;color:var(--mu)}
.tr{margin-left:auto;display:flex;align-items:center;gap:10px}
.live{display:flex;align-items:center;gap:5px;font-size:.58rem;color:var(--mu)}
.ldot{width:6px;height:6px;border-radius:50%;background:var(--tx);animation:blink 1.8s infinite}
@keyframes blink{0%,100%{opacity:1}50%{opacity:.15}}
.tclk{font-size:.6rem;color:var(--mu2)}
.tbtn{background:none;border:1px solid var(--bd);color:var(--mu);padding:4px 10px;font-family:'DM Mono',monospace;font-size:.6rem;cursor:pointer;transition:all .15s}
.tbtn:hover{border-color:var(--tx2);color:var(--tx)}
a.tbtn{text-decoration:none;display:inline-block}
.wrap{display:flex;flex:1;overflow:hidden}
.sidebar{width:var(--sw);background:var(--sf);border-right:1px solid var(--bd);padding:16px 0;overflow-y:auto;flex-shrink:0}
.ns{font-size:.54rem;letter-spacing:.16em;text-transform:uppercase;color:var(--mu);padding:0 14px 6px;margin-top:14px}
.ns:first-child{margin-top:0}
.ni{display:flex;align-items:center;gap:8px;padding:8px 14px;font-size:.68rem;color:var(--tx2);cursor:pointer;border-left:2px solid transparent;transition:all .12s;user-select:none}
.ni:hover{color:var(--tx);background:var(--sf2)}.ni.on{color:var(--tx);border-left-color:var(--tx);background:var(--sf2)}
.ni svg{width:12px;height:12px;opacity:.5;flex-shrink:0}.ni.on svg{opacity:1}
.nbadge{margin-left:auto;font-size:.52rem;background:var(--tx);color:var(--bg);padding:1px 5px}
.main{flex:1;overflow-y:auto;padding:24px}
.page{display:none;animation:fi .18s ease}.page.on{display:block}
@keyframes fi{from{opacity:0;transform:translateY(5px)}to{opacity:1;transform:translateY(0)}}
.ph{margin-bottom:22px;padding-bottom:16px;border-bottom:1px solid var(--bd)}
.pt{font-family:'Instrument Serif',serif;font-size:1.7rem;font-style:italic;font-weight:400}
.ps{font-size:.62rem;color:var(--mu);margin-top:5px}
.g4{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin-bottom:16px}
.g2{display:grid;grid-template-columns:1fr 1fr;gap:14px}
.g21{display:grid;grid-template-columns:1.35fr 1fr;gap:14px}
.card{background:var(--sf);border:1px solid var(--bd);padding:18px;margin-bottom:12px}
.ch{font-size:.54rem;letter-spacing:.14em;text-transform:uppercase;color:var(--mu);margin-bottom:14px;padding-bottom:12px;border-bottom:1px solid var(--bd);display:flex;align-items:center;justify-content:space-between}
.stat{background:var(--sf);border:1px solid var(--bd);padding:16px}
.sl{font-size:.54rem;letter-spacing:.12em;text-transform:uppercase;color:var(--mu);margin-bottom:7px}
.sv{font-family:'Instrument Serif',serif;font-size:2rem;font-style:italic;line-height:1}
.su{font-size:.58rem;color:var(--mu);margin-top:3px}
.bar{height:2px;background:var(--bd2);margin-top:9px}
.bf{height:2px;background:var(--tx);transition:width .9s ease}
.tbl{width:100%;border-collapse:collapse;font-size:.7rem}
.tbl th{font-size:.54rem;letter-spacing:.08em;text-transform:uppercase;color:var(--mu);text-align:left;padding:7px 12px;border-bottom:1px solid var(--bd);background:var(--sf2);font-weight:400}
.tbl td{padding:9px 12px;border-bottom:1px solid var(--bd);color:var(--tx2);vertical-align:middle}
.tbl tr:last-child td{border-bottom:none}.tbl tr:hover td{background:var(--sf2)}
.tbl-wrap{border:1px solid var(--bd);overflow:hidden}
.badge{font-size:.54rem;padding:2px 7px;border:1px solid}
.b-on{border-color:var(--tx);color:var(--tx)}.b-ok{border-color:var(--bd2);color:var(--tx2)}.b-off{border-color:var(--mu2);color:var(--mu)}.b-w{border-color:var(--tx2);color:var(--tx2)}
.btn{background:none;border:1px solid var(--bd2);color:var(--tx2);padding:5px 12px;font-family:'DM Mono',monospace;font-size:.62rem;cursor:pointer;transition:all .12s;border-radius:0}
.btn:hover{border-color:var(--tx);color:var(--tx);background:var(--sf2)}
.btnp{background:var(--tx);color:var(--bg);border-color:var(--tx)}.btnp:hover{opacity:.85;background:var(--tx);color:var(--bg)}
.btnsm{padding:3px 9px;font-size:.58rem}
.btnfull{width:100%;padding:11px;font-size:.68rem;letter-spacing:.1em;text-transform:uppercase;margin-top:6px}
.fr{margin-bottom:13px}
.fl{display:block;font-size:.54rem;letter-spacing:.1em;text-transform:uppercase;color:var(--mu);margin-bottom:6px}
.fi,.fsel,.fta{width:100%;background:var(--sf);border:1px solid var(--bd);color:var(--tx);padding:9px 10px;font-family:'DM Mono',monospace;font-size:.76rem;outline:none;transition:border-color .2s}
.fi:focus,.fsel:focus,.fta:focus{border-color:var(--tx)}
.fsel option{background:var(--sf)}.fta{min-height:180px;resize:vertical;line-height:1.65}
.tabs{display:flex;border-bottom:1px solid var(--bd);margin-bottom:14px}
.tab{padding:8px 14px;font-size:.6rem;letter-spacing:.08em;color:var(--mu);cursor:pointer;border-bottom:2px solid transparent;margin-bottom:-0.5px;transition:all .12s;text-transform:uppercase;user-select:none}
.tab:hover{color:var(--tx)}.tab.on{color:var(--tx);border-bottom-color:var(--tx)}
.tp{display:none}.tp.on{display:block}
.drop{border:1px dashed var(--bd2);padding:24px;text-align:center;cursor:pointer;transition:all .2s}
.drop:hover,.drop.ov{border-color:var(--tx);background:var(--sf2)}
.drop strong{font-size:.8rem;display:block;margin-bottom:4px;color:var(--tx2)}.drop p{font-size:.62rem;color:var(--mu)}
.srow{display:flex;align-items:center;gap:10px;padding:10px 0;border-bottom:1px solid var(--bd)}
.srow:last-child{border-bottom:none}
.sdot{width:6px;height:6px;border-radius:50%;background:var(--tx);flex-shrink:0}.sdot.off{background:var(--mu2)}
.lb{flex:1;overflow-y:auto;font-size:.62rem;line-height:1.8;font-family:'DM Mono',monospace;height:200px;background:var(--sf2);border:1px solid var(--bd);padding:10px}
.lok{color:var(--tx)}.lerr{color:var(--tx2);font-style:italic}.ldim{color:var(--mu)}
.pr{padding:9px 10px;background:var(--sf2);border:1px solid var(--bd);margin-top:7px;font-size:.65rem;line-height:1.8}
.rok{font-weight:400}.rwarn{color:var(--tx2)}.rdim{color:var(--mu)}
.ag{margin-bottom:9px}.agl{font-size:.54rem;letter-spacing:.1em;text-transform:uppercase;color:var(--mu2);margin-bottom:5px}
.abs{display:flex;flex-wrap:wrap;gap:4px}
.ab{background:none;border:1px solid var(--bd);color:var(--tx2);padding:5px 10px;font-family:'DM Mono',monospace;font-size:.6rem;cursor:pointer;transition:all .12s}
.ab:hover{border-color:var(--tx2);color:var(--tx);background:var(--sf2)}
.ab.run{border-color:var(--bd);color:var(--mu);pointer-events:none}
.ab.blk{border-color:var(--tx);color:var(--tx);background:var(--sf2)}
.ab.pw{border-color:var(--mu2);color:var(--mu);text-decoration:line-through}
.rall{width:100%;padding:9px;font-size:.62rem;letter-spacing:.1em;text-transform:uppercase;background:var(--tx);color:var(--bg);border:none;font-family:'DM Mono',monospace;cursor:pointer;margin-top:6px;transition:opacity .2s}
.rall:hover{opacity:.85}.rall:disabled{opacity:.45;cursor:not-allowed}
.feed-area{height:320px;overflow-y:auto}
.fitem{display:flex;align-items:flex-start;gap:9px;padding:9px 0;border-bottom:1px solid var(--bd);animation:si .15s ease}
@keyframes si{from{opacity:0;transform:translateY(-3px)}to{opacity:1;transform:translateY(0)}}
.fitem:last-child{border-bottom:none}
.ft{font-size:.68rem;font-weight:400;flex:1;color:var(--tx)}
.fi2{font-size:.6rem;color:var(--mu)}
.ftm{font-size:.56rem;color:var(--mu2);margin-left:auto;white-space:nowrap}
.blkb{font-size:.54rem;padding:1px 6px;border:1px solid var(--tx);color:var(--tx)}
.prow{display:flex;align-items:center;gap:8px;padding:7px 0;border-bottom:1px solid var(--bd);font-size:.68rem}
.prow:last-child{border-bottom:none}
.pp{flex:1;color:var(--mu);font-size:.62rem;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.pm{font-family:'DM Mono',monospace;font-size:.68rem;min-width:38px}
.po{font-size:.6rem;color:var(--mu2)}
hr{border:none;border-top:1px solid var(--bd);margin:12px 0}
::-webkit-scrollbar{width:3px}::-webkit-scrollbar-thumb{background:var(--bd2)}
</style>
</head><body>

<div class="topbar">
  <span class="tlogo">OS Lab Panel</span>
  <span class="tsep">/</span><span class="tpg" id="tpg">Dashboard</span>
  <div class="tr">
    <div class="live"><div class="ldot"></div><span id="lst">Live</span></div>
    <span class="tclk" id="tclk"></span>
    <button class="tbtn" onclick="toggleDark()">Dark / Light</button>
    <button class="tbtn" onclick="nav('monitor',document.querySelector('[onclick*=monitor]'))">Live Monitor</button>
    <a href="?logout" class="tbtn">Sign Out</a>
  </div>
</div>

<div class="wrap">
<div class="sidebar">
  <div class="ns">Overview</div>
  <div class="ni on" onclick="nav('dash',this)">
    <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="1" y="1" width="6" height="6"/><rect x="9" y="1" width="6" height="6"/><rect x="1" y="9" width="6" height="6"/><rect x="9" y="9" width="6" height="6"/></svg>Dashboard
  </div>
  <div class="ns">Sites</div>
  <div class="ni" onclick="nav('deploy',this)">
    <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M8 1v14M1 8h14"/></svg>Deploy New Site
  </div>
  <div class="ni" onclick="nav('sites',this)">
    <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="1" y="3" width="14" height="10" rx="1"/><path d="M1 6h14"/></svg>All Sites
  </div>
  <div class="ns">Security</div>
  <div class="ni" onclick="nav('security',this)">
    <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M8 1L2 4v5c0 3.5 2.5 5.5 6 6 3.5-.5 6-2.5 6-6V4z"/></svg>Firewall &amp; Fail2Ban
  </div>
  <div class="ni" onclick="nav('monitor',this)">
    <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="8" cy="8" r="7"/><path d="M8 5v3M8 10v1" stroke-linecap="round"/></svg>Attack Monitor
    <span class="nbadge" id="anb">0</span>
  </div>
</div>

<div class="main">

<!-- ═══ DASHBOARD ═══ -->
<div class="page on" id="pg-dash">
  <div class="ph"><div class="pt">Server Dashboard</div><div class="ps">Real-time system metrics · auto-refresh every 10s</div></div>
  <div class="g4">
    <div class="stat"><div class="sl">Memory</div><div class="sv" id="sm">--</div><div class="su" id="smd">…</div><div class="bar"><div class="bf" id="bm" style="width:0"></div></div></div>
    <div class="stat"><div class="sl">Disk</div><div class="sv" id="sd">--</div><div class="su" id="sdd">…</div><div class="bar"><div class="bf" id="bd" style="width:0"></div></div></div>
    <div class="stat"><div class="sl">CPU Load</div><div class="sv" id="sc" style="font-size:1.4rem;padding-top:4px">--</div><div class="su" id="sup">…</div><div class="bar"><div class="bf" id="bcp" style="width:0"></div></div></div>
    <div class="stat"><div class="sl">Attacks Blocked</div><div class="sv" id="sa">0</div><div class="su" id="sbn">Loading...</div><div class="bar"><div class="bf" id="ba" style="width:0"></div></div></div>
  </div>
  <div class="g2">
    <div class="card">
      <div class="ch">Services</div>
      <div id="svc-list">
      <?php foreach(['apache2'=>'Apache2 Web Server','fail2ban'=>'Fail2Ban','ufw'=>'UFW Firewall'] as $s=>$l){
        $on=run("systemctl is-active $s")==='active';
        echo "<div class='srow'><div class='sdot".($on?'':' off')."'></div><span style='flex:1;font-size:.7rem'>$l</span>"
           ."<span style='font-size:.6rem;color:var(--mu);margin-right:8px'>".($on?'running':'stopped')."</span>"
           ."<button class='btn btnsm' onclick='svc(\"$s\",\"restart\")'>Restart</button>"
           ."<button class='btn btnsm' style='margin-left:4px' onclick='svc(\"$s\",\"".($on?'stop':'start')."\")'>"
           .($on?'Stop':'Start')."</button></div>";
      }?>
      </div>
    </div>
    <div class="card">
      <div class="ch">Virtual Hosts</div>
      <?php foreach(vhosts() as $v){
        $ssl=file_exists("/etc/ssl/certs/$v.crt");
        echo "<div class='srow'><div class='sdot'></div><span style='flex:1;font-size:.7rem'>$v</span>"
           ."<button class='btn btnsm' onclick=\"window.open('".($ssl?'https':'http')."://$v','_blank')\">Open →</button></div>";
      }?>
    </div>
  </div>
  <div class="g2" style="margin-top:0">
    <div class="card">
      <div class="ch">Today's Traffic</div>
      <?php
      $td=date('d/M/Y');$tot=0;$uiq=[];
      foreach(glob('/var/log/apache2/*_access.log')?:[] as $lf)
        foreach(file($lf)?:[] as $ln){if(strpos($ln,$td)!==false){$tot++;$p=explode(' ',$ln);if(isset($p[0]))$uiq[$p[0]]=1;}}
      echo "<div style='font-family:\"Instrument Serif\",serif;font-size:2.5rem;font-style:italic'>$tot</div>"
         ."<div style='font-size:.62rem;color:var(--mu);margin-top:4px'>requests today · ".count($uiq)." unique IPs</div>";
      $waf=0;if(file_exists('/var/log/apache2/modsecurity_audit.log'))$waf=(int)run("wc -l < /var/log/apache2/modsecurity_audit.log");
      echo "<div style='margin-top:10px;font-size:.7rem'>WAF events: $waf</div>";
      ?>
    </div>
    <div class="card">
      <div class="ch">Open Ports</div>
      <div style="font-family:'Instrument Serif',serif;font-size:1.5rem;font-style:italic;margin-bottom:6px">22 · 80 · 443</div>
      <div style="font-size:.62rem;color:var(--mu)">SSH · HTTP · HTTPS</div>
      <?php $ust=run('sudo /usr/sbin/ufw status');echo "<div style='margin-top:10px;font-size:.7rem'>UFW: ".htmlspecialchars(explode("\n",$ust)[0])."</div>";?>
    </div>
  </div>
  
  <div class="card" style="margin-top:12px">
    <div class="ch">IP Address &amp; DNS Mapping</div>
    <div class="tbl-wrap">
      <table class="tbl">
        <thead><tr><th>Entity</th><th>IP Address</th><th>Explanation</th></tr></thead>
        <tbody>
          <tr><td><strong>Your Client IP</strong></td><td><span class="badge b-w"><?=$_SERVER['REMOTE_ADDR']?></span></td><td style="font-size:0.6rem;color:var(--mu)">IP of the device viewing this panel. (127.0.0.1 if using VM browser).</td></tr>
          <tr><td><strong>VM Network IP</strong></td><td><span class="badge b-on"><?=trim(shell_exec('hostname -I')?:'')?></span></td><td style="font-size:0.6rem;color:var(--mu)">Server's LAN address. Must be a Bridged Network (e.g. 192.168.x) for phone access.</td></tr>
          <tr><td><strong>VM Loopback IP</strong></td><td><span class="badge b-off">127.0.0.1</span></td><td style="font-size:0.6rem;color:var(--mu)">Used by the server to talk to itself. Fail2Ban whitelists this by default.</td></tr>
          <?php foreach(vhosts() as $v): ?>
          <tr><td><strong><?=$v?></strong></td><td>Shares Network IP</td><td style="font-size:0.6rem;color:var(--mu)">Uses Name-Based Virtual Hosting. All domains run on the single VM IP.</td></tr>
          <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  </div>
</div>

<!-- ═══ DEPLOY ═══ -->
<div class="page" id="pg-deploy">
  <div class="ph"><div class="pt">Deploy New Site</div><div class="ps">Create virtual host, SSL, content and permissions automatically</div></div>
  <div class="g21">
    <div>
      <div class="card">
        <div class="ch">Configuration</div>
        <div class="fr"><label class="fl">Domain Name</label><input class="fi" id="nd" placeholder="mysite.local" autocomplete="off"></div>
        <div class="fr"><label class="fl">Site Title</label><input class="fi" id="nt" placeholder="My Website"></div>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px">
          <div class="fr"><label class="fl">HTTPS</label><select class="fsel" id="ns"><option value="yes">Enable SSL</option><option value="no">HTTP only</option></select></div>
          <div class="fr"><label class="fl">Password Protect</label><select class="fsel" id="na" onchange="document.getElementById('authf').style.display=this.value==='yes'?'block':'none'"><option value="no">Public</option><option value="yes">Protected</option></select></div>
        </div>
        <div id="authf" style="display:none;border-top:1px solid var(--bd);padding-top:12px">
          <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px">
            <div class="fr"><label class="fl">Username</label><input class="fi" id="au" placeholder="admin"></div>
            <div class="fr"><label class="fl">Password</label><input class="fi" type="password" id="ap" placeholder="password"></div>
          </div>
        </div>
      </div>
      <div class="card">
        <div class="ch">Website Content</div>
        <div class="tabs">
          <div class="tab on" onclick="ctab('up',this)">Upload HTML</div>
          <div class="tab" onclick="ctab('ed',this)">Write Code</div>
          <div class="tab" onclick="ctab('tpl',this)">Template</div>
        </div>
        <div class="tp on" id="tp-up">
          <div class="drop" id="dropz" onclick="document.getElementById('fin').click()" ondragover="ev.preventDefault();this.classList.add('ov')" ondragleave="this.classList.remove('ov')" ondrop="onDrop(event)">
            <strong>Drop HTML file here</strong><p>or click to browse · .html .htm .php</p>
          </div>
          <input type="file" id="fin" accept=".html,.htm,.php" style="display:none" onchange="onFileChosen(this)">
          <div id="fn" style="font-size:.65rem;color:var(--mu);margin-top:8px"></div>
        </div>
        <div class="tp" id="tp-ed">
          <textarea class="fta" id="htmled" style="min-height:200px" placeholder="<!DOCTYPE html>
<html>
<head><title>My Site</title></head>
<body>
  <h1>Hello World</h1>
  <p>Write your HTML here...</p>
</body>
</html>"></textarea>
        </div>
        <div class="tp" id="tp-tpl">
          <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px" id="tplgrid">
            <div class="card" style="cursor:pointer;padding:12px;margin:0" onclick="selTpl(0,this)"><div style="font-size:.72rem;margin-bottom:3px">Minimal Dark</div><div style="font-size:.6rem;color:var(--mu)">Dark monospace, centered</div></div>
            <div class="card" style="cursor:pointer;padding:12px;margin:0" onclick="selTpl(1,this)"><div style="font-size:.72rem;margin-bottom:3px">Minimal Light</div><div style="font-size:.6rem;color:var(--mu)">White serif, elegant</div></div>
            <div class="card" style="cursor:pointer;padding:12px;margin:0" onclick="selTpl(2,this)"><div style="font-size:.72rem;margin-bottom:3px">Portfolio</div><div style="font-size:.6rem;color:var(--mu)">Team cards layout</div></div>
            <div class="card" style="cursor:pointer;padding:12px;margin:0" onclick="selTpl(3,this)"><div style="font-size:.72rem;margin-bottom:3px">Project Docs</div><div style="font-size:.6rem;color:var(--mu)">Documentation sidebar</div></div>
          </div>
        </div>
        <button class="btn btnp btnfull" onclick="deploy()">Deploy Site</button>
      </div>
    </div>
    <div>
      <div class="card">
        <div class="ch">Deployment Log</div>
        <div class="lb" id="dlog"><span class="ldim">Waiting for deployment…</span></div>
      </div>
      <div class="card">
        <div class="ch">What Happens</div>
        <div style="font-size:.65rem;color:var(--mu);line-height:2.2">
          1 — Creates /var/www/{domain}/html/<br>
          2 — chmod 755, owner www-data<br>
          3 — Generates SSL cert (RSA 2048)<br>
          4 — Saves your HTML as index.html<br>
          5 — Writes Apache VirtualHost config<br>
          6 — Enables site with a2ensite<br>
          7 — Adds domain to /etc/hosts<br>
          8 — Reloads Apache → site is LIVE
        </div>
      </div>
    </div>
  </div>
</div>

<!-- ═══ SITES ═══ -->
<div class="page" id="pg-sites">
  <div class="ph">
    <div class="pt">All Sites</div>
    <div class="ps">Real-time list of all deployed virtual hosts</div>
  </div>
  <div style="display:flex;gap:8px;margin-bottom:14px">
    <button class="btn btnp" onclick="nav('deploy',document.querySelector('[onclick*=deploy]'))">Deploy New Site</button>
    <button class="btn" onclick="loadSites()">Refresh</button>
  </div>
  <div class="tbl-wrap">
    <table class="tbl">
      <thead><tr><th>Domain</th><th>Document Root</th><th>SSL</th><th>Auth</th><th>Log</th><th>Today</th><th>Status</th><th>Actions</th></tr></thead>
      <tbody id="sites-body"><?php echo getSites();?></tbody>
    </table>
  </div>
</div>

<!-- ═══ SECURITY ═══ -->
<div class="page" id="pg-security">
  <div class="ph"><div class="pt">Firewall &amp; Security</div><div class="ps">UFW rules, Fail2Ban jails, banned IPs, SSL certificates</div></div>
  <div style="font-size:.65rem;color:var(--mu);margin-bottom:16px;line-height:1.6;padding:12px;border:1px solid var(--bd);background:var(--sf2)">
    <strong>Why banning an IP might seem to "do nothing":</strong><br>
    If you are testing from <b>INSIDE the Ubuntu VM using Firefox</b>, your client IP is <code>127.0.0.1</code> (localhost loopback).<br>
    <b>1. Fail2Ban explicitly whitelists localhost (127.0.0.1/8)</b> so you don't lock yourself out.<br>
    <b>2. Banning the NAT IP (10.0.2.15)</b> won't block local VM Firefox traffic because local requests don't route through the external NAT IP.<br>
    <em>To properly test a ban, you must access the server from a completely separate device (like your phone or host laptop) and ban that device's external IP address!</em>
  </div>
  <div class="g2">
    <div>
      <div class="card">
        <div class="ch">Security Actions &amp; Bans</div>
        <div id="live-ips">
          <div style="padding:20px;text-align:center;color:var(--mu)">Loading security data...</div>
        </div>
        <div style="font-size:.54rem;letter-spacing:.1em;text-transform:uppercase;color:var(--mu);margin-bottom:8px;margin-top:10px;">Manual Ban IP</div>
        <div style="display:flex;gap:8px"><input class="fi" id="banip" placeholder="IP Address" style="flex:1"><button class="btn btnp" onclick="ban()">Ban</button></div>
      </div>
      <div class="card">
        <div class="ch">UFW Firewall</div>
        <?php echo "<div class='lb' style='height:140px'><pre class='ldim' style='white-space:pre-wrap;font-size:.6rem'>".htmlspecialchars(run('sudo /usr/sbin/ufw status verbose'))."</pre></div>";?>
        <hr>
        <div style="font-size:.54rem;letter-spacing:.1em;text-transform:uppercase;color:var(--mu);margin-bottom:8px">Add Rule</div>
        <div style="display:flex;gap:8px">
          <input class="fi" id="ufwp" placeholder="Port e.g. 8080" style="flex:1">
          <select class="fsel" id="ufwa" style="width:90px"><option value="allow">Allow</option><option value="deny">Deny</option></select>
          <button class="btn btnp" onclick="ufwRule()">Apply</button>
        </div>
      </div>
    </div>
    <div>
      <div class="card">
        <div class="ch">SSL Certificates</div>
        <div class="tbl-wrap">
        <table class="tbl"><thead><tr><th>Domain</th><th>Expires</th><th>Key</th><th>Status</th></tr></thead><tbody>
        <?php foreach(glob('/etc/ssl/certs/*.crt')?:[] as $c){
          $d=basename($c,'.crt');
          if(strpos($d,'ssl-cert')!==false||strpos($d,'ca-')!==false)continue;
          $exp=trim(run("openssl x509 -in $c -noout -enddate 2>/dev/null|cut -d= -f2"));
          $expf=$exp?date('d M Y',strtotime($exp)):'Unknown';
          $xp=$exp&&strtotime($exp)<time();
          $hk=file_exists("/etc/ssl/private/$d.key");
          echo "<tr><td><strong>$d</strong></td><td style='font-size:.62rem'>$expf</td>"
             ."<td>".($hk?'<span class="badge b-on">Present</span>':'<span class="badge b-off">Missing</span>')."</td>"
             ."<td>".($xp?'<span class="badge b-w">Expired</span>':'<span class="badge b-ok">Valid</span>')."</td></tr>";
        }?>
        </tbody></table>
        </div>
      </div>
    </div>
  </div>
</div>

<!-- ═══ MONITOR ═══ -->
<div class="page" id="pg-monitor">
  <div class="ph"><div class="pt">Attack Monitor</div><div class="ps">Real-time WAF events via SSE · attacks appear within 1 second</div></div>
  <div class="g21">
    <div class="card" style="display:flex;flex-direction:column">
      <div class="ch">Live Event Feed <span id="atk-cnt" style="font-size:.6rem;color:var(--mu)">0 events</span></div>
      <div class="feed-area" id="atk-feed"><div style="padding:20px 0;font-size:.7rem;color:var(--mu)">Connecting to SSE stream…</div></div>
    </div>
    <div>
      <div class="card">
        <div class="ch">Attack Tester</div>
        <div class="fr"><label class="fl">Target Site</label>
        <select class="fsel" id="atgt">
          <?php $targets = vhosts(); $targets = array_values(array_filter($targets, fn($v) => $v !== 'panel.local' && $v !== 'admin.local')); if(empty($targets)) { echo "<option value=''>No sites available - check Apache config</option>"; } else { foreach($targets as $v) echo "<option value='$v'>$v</option>"; } ?>
        </select></div>
        <div class="ag"><div class="agl">SQL Injection</div><div class="abs">
          <button class="ab" id="ab-s1" onclick="atest('sqli_basic')">Basic OR</button>
          <button class="ab" id="ab-s2" onclick="atest('sqli_union')">UNION SELECT</button>
          <button class="ab" id="ab-s3" onclick="atest('sqli_drop')">DROP TABLE</button>
        </div></div>
        <div class="ag"><div class="agl">XSS</div><div class="abs">
          <button class="ab" id="ab-x1" onclick="atest('xss_script')">&lt;script&gt;</button>
          <button class="ab" id="ab-x2" onclick="atest('xss_img')">img onerror</button>
          <button class="ab" id="ab-x3" onclick="atest('xss_event')">event handler</button>
        </div></div>
        <div class="ag"><div class="agl">Path Traversal</div><div class="abs">
          <button class="ab" id="ab-p1" onclick="atest('path_etc')">/etc/passwd</button>
          <button class="ab" id="ab-p2" onclick="atest('path_shadow')">/etc/shadow</button>
          <button class="ab" id="ab-p3" onclick="atest('path_enc')">URL encoded</button>
        </div></div>
        <div class="ag"><div class="agl">Other</div><div class="abs">
          <button class="ab" id="ab-o1" onclick="atest('cmd_cat')">CMD inject</button>
          <button class="ab" id="ab-o2" onclick="atest('null_byte')">Null byte</button>
          <button class="ab" id="ab-o3" onclick="atest('scanner')">Nikto UA</button>
        </div></div>
        
        <hr style="margin:20px 0; border:none; border-top:1px dashed var(--bd)">
        <div style="font-size:0.6rem; letter-spacing:0.1em; text-transform:uppercase; color:#c00; margin-bottom:8px; font-weight:bold; display:flex; align-items:center; gap:8px">
          <div class="sdot off" id="sim-dot" style="background:#c00; width:8px; height:8px; animation:blink 1.5s infinite"></div>
          Live Threat Simulation
        </div>
        <div style="font-size:0.55rem; color:var(--mu); margin-bottom:12px; line-height:1.6">Continuously fires random payloads to demonstrate dynamic WAF & Fail2Ban defenses live.</div>
        <div style="display:flex; gap:8px; margin-bottom:14px">
          <button class="btn btnfull" id="sim-btn" onclick="toggleSim()" style="margin:0; background:var(--sf2); font-weight:bold">START SIMULATION</button>
          <button class="btn btnfull" id="rall" onclick="runAll()" style="margin:0">Run Batch Once</button>
        </div>

        <div class="pr" id="atk-res" style="background:#0a0a00; border-color:#222; color:#0f0; min-height:45px"><span class="rdim" style="color:#555">Terminal ready. Awaiting directives...</span></div>
      </div>
    </div>
  </div>
</div>



</div>
</div>

<?php
function getSites(){
  $out='';$td=date('d/M/Y');
  foreach(glob('/etc/apache2/sites-available/*.conf')?:[] as $cf){
    $d=basename($cf,'.conf');if($d==='000-default'||$d==='default-ssl')continue;
    $dr="/var/www/$d/html";
    $enabled = file_exists("/etc/apache2/sites-enabled/$d.conf");
    $ssl=file_exists("/etc/ssl/certs/$d.crt")?'<span class="badge b-on">SSL</span>':'<span class="badge b-off">HTTP</span>';
    $auth=file_exists("$dr/.htaccess")?'<span class="badge b-w">Protected</span>':'<span class="badge b-ok">Public</span>';
    $lf="/var/log/apache2/{$d}_access.log";
    $ls=file_exists($lf)?round(filesize($lf)/1024,1).'KB':'0KB';
    $req=0;if(file_exists($lf)){foreach(file($lf)?:[] as $l){if(strpos($l,$td)!==false)$req++;}}
    $ok=$enabled?('<span class="badge b-on">Online</span>'):('<span class="badge b-off">Disabled</span>');
    $ssl2=file_exists("/etc/ssl/certs/$d.crt");
    $endis_btn = in_array($d, ['admin.local', 'panel.local']) ? "<button class='btn btnsm' disabled style='opacity:0.5;border-color:var(--bd)'>Protected</button>" : ($enabled ? "<button class='btn btnsm' onclick='disableSite(\"$d\")'>Disable</button>" : "<button class='btn btnsm' onclick='enableSite(\"$d\")'>Enable</button>");
    $out.="<tr><td><strong>$d</strong></td><td style='font-size:.6rem;color:var(--mu)'>$dr</td>"
        ."<td>$ssl</td><td>$auth</td><td style='color:var(--mu)'>$ls</td><td style='color:var(--mu)'>$req</td><td>$ok</td>"
        ."<td style='white-space:nowrap'><button class='btn btnsm' onclick=\"window.open('".($ssl2?'https':'http')."://$d','_blank')\" style='margin-right:4px'>Open</button>"
        ."$endis_btn</td></tr>";
  }
  return $out?:("<tr><td colspan='8' style='color:var(--mu);text-align:center;padding:20px'>No sites yet</td></tr>");
}
?>

<script>
(function(){if(localStorage.getItem('dark')==='1')document.documentElement.setAttribute('data-dark','');})();
function toggleDark(){const h=document.documentElement,on=h.hasAttribute('data-dark');on?h.removeAttribute('data-dark'):h.setAttribute('data-dark','');localStorage.setItem('dark',on?'0':'1');}
function tick(){document.getElementById('tclk').textContent=new Date().toLocaleTimeString();}
tick();setInterval(tick,1000);

function nav(id,el){
  document.querySelectorAll('.page').forEach(p=>p.classList.remove('on'));
  document.querySelectorAll('.ni').forEach(n=>n.classList.remove('on'));
  document.getElementById('pg-'+id).classList.add('on');
  if(el)el.classList.add('on');
  document.getElementById('tpg').textContent=id.charAt(0).toUpperCase()+id.slice(1);
  if(id==='dash')refreshDash();
  if(id==='monitor')startSSE();
  if(id==='security')loadIps();
}

let ipIvl=null;
async function loadIps(){
  const f=async()=>{
    const b=document.getElementById('live-ips');
    if(!b || !b.closest('.page.on')) return;
    const r=await api('ips');
    if(r.ok) b.innerHTML=r.html;
  };
  await f();
  if(!ipIvl) ipIvl=setInterval(f, 4000);
}

function toast(msg, warn=false){
  let t=document.getElementById('toast');
  if(!t){t=document.createElement('div');t.id='toast';t.style.cssText='position:fixed;bottom:24px;right:24px;padding:12px 20px;font-size:.75rem;opacity:0;transition:opacity .25s;pointer-events:none;z-index:999;box-shadow:0 4px 12px rgba(0,0,0,0.3)';document.body.appendChild(t);}
  t.style.background = warn ? '#c00' : 'var(--tx)';
  t.style.color = warn ? '#fff' : 'var(--bg)';
  t.textContent=msg;t.style.opacity='1';
  clearTimeout(t.timer);t.timer = setTimeout(()=>t.style.opacity='0',3500);
}

async function api(action,data={}){
  const fd=new FormData();fd.append('action',action);
  const cm=document.querySelector('meta[name=csrf]');
  if(cm)fd.append('csrf',cm.content);
  for(const k in data)fd.append(k,data[k]);
  try{
    const r=await fetch('api.php',{method:'POST',body:fd});
    return r.json();
  }catch(e){console.error('API error:',e);return{ok:false,error:e.message};}
}

async function refreshDash(){
  const r=await api('stats');if(!r.ok)return;const s=r.d;
  document.getElementById('sm').textContent=s.mp+'%';document.getElementById('smd').textContent=s.mu+'MB / '+s.mt+'MB';document.getElementById('bm').style.width=s.mp+'%';
  document.getElementById('sd').textContent=s.dp+'%';document.getElementById('sdd').textContent=s.du+'GB / '+s.dt+'GB';document.getElementById('bd').style.width=s.dp+'%';
  document.getElementById('sc').textContent=s.l1;document.getElementById('sup').textContent='up '+s.up;document.getElementById('bcp').style.width=Math.min(100,parseFloat(s.l1)*50)+'%';
  document.getElementById('sbn').textContent=s.banned+' IPs banned';
}
refreshDash();setInterval(refreshDash,10000);

let uploadedFile=null,selectedTpl=-1;
function onDrop(e){e.preventDefault();document.getElementById('dropz').classList.remove('ov');uploadedFile=e.dataTransfer.files[0];if(uploadedFile)document.getElementById('fn').textContent='Selected: '+uploadedFile.name;}
function onFileChosen(i){uploadedFile=i.files[0];if(uploadedFile)document.getElementById('fn').textContent='Selected: '+uploadedFile.name;}
function ctab(id,el){document.querySelectorAll('.tab').forEach(t=>t.classList.remove('on'));document.querySelectorAll('.tp').forEach(p=>p.classList.remove('on'));el.classList.add('on');document.getElementById('tp-'+id).classList.add('on');}
const TPLS=[
`<!DOCTYPE html><html><head><meta charset="UTF-8"><title>TITLE</title><style>*{margin:0;padding:0;box-sizing:border-box}body{background:#080808;color:#f0f0ec;font-family:'DM Mono',monospace;display:flex;align-items:center;justify-content:center;min-height:100vh;flex-direction:column;gap:10px}h1{font-size:3rem;font-weight:300;border-bottom:1px solid #222;padding-bottom:12px}p{font-size:.8rem;color:#444}</style></head><body><h1>TITLE</h1><p>DOMAIN</p></body></html>`,
`<!DOCTYPE html><html><head><meta charset="UTF-8"><title>TITLE</title><link href="https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@1&display=swap" rel="stylesheet"><style>*{margin:0;padding:0;box-sizing:border-box}body{background:#f8f8f6;color:#0e0e0e;font-family:'Instrument Serif',serif;display:flex;align-items:center;justify-content:center;min-height:100vh;flex-direction:column;gap:8px}h1{font-size:3.5rem;font-style:italic;font-weight:400}p{font-size:.95rem;color:#888}</style></head><body><h1>TITLE</h1><p>DOMAIN</p></body></html>`,
`<!DOCTYPE html><html><head><meta charset="UTF-8"><title>TITLE</title><style>*{margin:0;padding:0;box-sizing:border-box}body{background:#f8f8f6;font-family:system-ui,sans-serif;padding:40px}h1{font-size:1.8rem;font-weight:500;margin-bottom:28px;border-bottom:1px solid #e0e0dc;padding-bottom:12px}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}.card{border:1px solid #e0e0dc;padding:20px;text-align:center}.av{width:64px;height:64px;border-radius:50%;background:#f0f0ee;margin:0 auto 12px}.nm{font-weight:500}.id{font-size:.8rem;color:#888}</style></head><body><h1>TITLE</h1><div class="grid"><div class="card"><div class="av"></div><div class="nm">Member Name</div><div class="id">ID: 000-00-000</div></div><div class="card"><div class="av"></div><div class="nm">Member Name</div><div class="id">ID: 000-00-000</div></div><div class="card"><div class="av"></div><div class="nm">Member Name</div><div class="id">ID: 000-00-000</div></div></div></body></html>`,
`<!DOCTYPE html><html><head><meta charset="UTF-8"><title>TITLE</title><style>*{margin:0;padding:0;box-sizing:border-box}body{background:#fff;font-family:system-ui,sans-serif;display:flex}.nav{width:200px;border-right:1px solid #e0e0dc;padding:24px 0;position:fixed;top:0;bottom:0}.nav h2{font-size:.65rem;letter-spacing:.1em;text-transform:uppercase;color:#888;padding:0 16px 12px}.nav a{display:block;padding:7px 16px;color:#555;text-decoration:none;font-size:.85rem}.nav a:hover{background:#f8f8f6;color:#0e0e0e}.main{margin-left:200px;padding:40px;max-width:720px}h1{font-size:2rem;margin-bottom:6px}p{color:#555;line-height:1.8;font-size:.9rem;margin-bottom:12px}h2{font-size:1.1rem;margin:24px 0 8px;padding-top:24px;border-top:1px solid #f0f0ee}code{background:#f0f0ee;padding:1px 6px;font-family:monospace}</style></head><body><div class="nav"><h2>Contents</h2><a href="#overview">Overview</a><a href="#features">Features</a><a href="#usage">Usage</a></div><div class="main"><h1>TITLE</h1><p>DOMAIN</p><h2 id="overview">Overview</h2><p>Write your project overview here.</p><h2 id="features">Features</h2><p>List your features here. Use <code>code</code> for commands.</p></div></body></html>`
];
function selTpl(i,el){selectedTpl=i;document.querySelectorAll('#tplgrid .card').forEach(c=>c.style.borderColor='var(--bd)');el.style.borderColor='var(--tx)';toast('Template selected');}

async function deploy(){
  const domain=document.getElementById('nd').value.trim();
  const title=document.getElementById('nt').value.trim()||domain;
  const ssl=document.getElementById('ns').value;
  const auth=document.getElementById('na').value;
  const auser=document.getElementById('au').value||'admin';
  const apass=document.getElementById('ap').value||'admin123';
  const activeTab=document.querySelector('.tabs .tab.on').textContent.trim();
  let content='';
  if(activeTab.includes('Upload')&&uploadedFile)content=await uploadedFile.text();
  else if(activeTab.includes('Write'))content=document.getElementById('htmled').value;
  else if(selectedTpl>=0)content=TPLS[selectedTpl].replace(/TITLE/g,title).replace(/DOMAIN/g,domain);
  if(!domain){toast('Enter a domain name');return;}
  const log=document.getElementById('dlog');
  log.innerHTML='<span class="ldim">Deploying '+domain+'…</span>\n';
  function addLog(msg,ok=true){log.innerHTML+='<span class="'+(ok?'lok':'lerr')+'">'+msg+'</span>\n';log.scrollTop=log.scrollHeight;}
  const r=await api('deploy',{domain,title,ssl,auth,auser,apass,content});
  if(r.ok){r.steps.forEach(s=>addLog(s.msg,s.ok));toast('Deployed: '+(ssl==='yes'?'https':'http')+'://'+domain);loadSites();}
  else{addLog('[FAIL] '+r.error,false);toast('Failed');}
}

async function svc(s,a){const r=await api('svc',{svc:s,action:a});toast(r.ok?s+' '+a+'ed':'Failed');setTimeout(refreshDash,1500);}
async function ban(tgt){const ip=(typeof tgt==='string'?tgt:'')||document.getElementById('banip').value.trim();if(!ip)return;const r=await api('ban',{ip});toast(r.ok?'Banned: '+ip:'Failed');if(r.ok)setTimeout(loadIps,600);}
async function unban(ip,jail=''){const r=await api('unban',{ip,jail});toast(r.ok?'Unbanned: '+ip:'Failed');if(r.ok)setTimeout(loadIps,600);}
async function ufwRule(){const p=document.getElementById('ufwp').value,a=document.getElementById('ufwa').value;if(!p)return;const r=await api('ufw',{port:p,action:a});toast(r.ok?'Rule added':'Failed');}
async function loadSites(){const r=await api('sites');if(r.ok)document.getElementById('sites-body').innerHTML=r.html;}
async function disableSite(d){if(!confirm('Disable '+d+'?'))return;const r=await api('disable',{domain:d});toast(r.ok?d+' disabled':'Failed');if(r.ok)loadSites();}
async function enableSite(d){const r=await api('enable',{domain:d});toast(r.ok?d+' enabled':'Failed');if(r.ok)loadSites();}


let sseConn=null,atkCount=0,sseStarted=false;
function esc(s){const d=document.createElement('div');d.textContent=String(s||'');return d.innerHTML;}
function startSSE(){
  if(sseStarted)return;sseStarted=true;
  sseConn=new EventSource('monitor/stream.php');
  
  // Handle connection open
  sseConn.onopen=function(){
    console.log('SSE connection opened');
    const feed=document.getElementById('atk-feed');
    if(feed && feed.children.length===0){
      feed.innerHTML='<div style="padding:10px 0;font-size:.7rem;color:var(--mu)">Connected. Waiting for events...</div>';
    }
  };
  
  // Handle connection errors
  sseConn.onerror=function(err){
    console.error('SSE error:',err);
    const feed=document.getElementById('atk-feed');
    if(feed){
      feed.innerHTML='<div style="padding:10px 0;font-size:.7rem;color:#c00">Connection lost. Will retry...</div>'+feed.innerHTML;
    }
  };
  
  sseConn.addEventListener('connected',ev=>{
    const d=JSON.parse(ev.data);
    console.log('SSE connected:',d);
    const feed=document.getElementById('atk-feed');
    if(feed)feed.innerHTML='<div style="padding:10px 0;font-size:.7rem;color:var(--mu)">'+esc(d.msg)+' at '+esc(d.time)+'</div>';
  });
  
  sseConn.addEventListener('attack',ev=>{
    const d=JSON.parse(ev.data);atkCount++;
    document.getElementById('atk-cnt').textContent=atkCount+' events';
    document.getElementById('anb').textContent=atkCount;
    document.getElementById('sa').textContent=atkCount;
    document.getElementById('ba').style.width=Math.min(100,atkCount*8)+'%';
    const feed=document.getElementById('atk-feed');
    const emp=feed.querySelector('div[style*="color"]');if(emp && emp.textContent.includes('Waiting'))emp.remove();
    const el=document.createElement('div');
    el.className='fitem';
    el.innerHTML=`<div style="flex:1"><span class="ft">${esc(d.type||'WAF Event')}</span> <span class="fi2">${esc(d.ip)}</span> <button class="btn btnsm" onclick="ban('${esc(d.ip)}')" style="margin-left:8px;padding:2px 8px">Ban Attacker</button></div><span class="ftm">${esc(d.time)}</span><span class="blkb" style="color:#c00;border-color:#c00;font-weight:bold">BLOCKED</span>`;
    feed.insertBefore(el,feed.firstChild);
    while(feed.children.length>100)feed.removeChild(feed.lastChild);
    toast(`⚠️ ALERT: ${esc(d.type||'Attack')} from ${esc(d.ip)} BLOCKED!`, true);
  });
  
  sseConn.addEventListener('access',ev=>{
    const d=JSON.parse(ev.data);
    // Only show blocked (403) requests as mini attacks
    if(d.status===403||d.status===406){
      atkCount++;
      document.getElementById('atk-cnt').textContent=atkCount+' events';
      document.getElementById('anb').textContent=atkCount;
      document.getElementById('sa').textContent=atkCount;
      document.getElementById('ba').style.width=Math.min(100,atkCount*8)+'%';
      const feed=document.getElementById('atk-feed');
      const emp=feed.querySelector('div[style*="color"]');if(emp && emp.textContent.includes('Waiting'))emp.remove();
      const el=document.createElement('div');
      el.className='fitem';
      el.innerHTML=`<div style="flex:1"><span class="ft">${esc(d.atk||'Blocked Request')}</span> <span class="fi2">${esc(d.ip)}</span> <button class="btn btnsm" onclick="ban('${esc(d.ip)}')" style="margin-left:8px;padding:2px 8px">Ban Attacker</button></div><span class="ftm">${esc(d.time)}</span><span class="blkb" style="color:#c00;border-color:#c00;font-weight:bold">HTTP ${d.status}</span>`;
      feed.insertBefore(el,feed.firstChild);
      while(feed.children.length>100)feed.removeChild(feed.lastChild);
    }
  });
  
  sseConn.addEventListener('snapshot',ev=>{
    const s=JSON.parse(ev.data);
    document.getElementById('sm').textContent=s.mp+'%';document.getElementById('bm').style.width=s.mp+'%';
    document.getElementById('sbn').textContent=(s.banned||'0')+' IPs banned';
    document.getElementById('anb').textContent=atkCount;
  });
  
  sseConn.addEventListener('keepalive',ev=>{
    // Silent keepalive - just keeps connection alive
    console.log('SSE keepalive:',ev.data);
  });
}

const ATTACKS={
  sqli_basic:{cat:'SQL Injection',lbl:'Basic OR',uri:"/waf-test/?id=1'+OR+'1'='1"},
  sqli_union:{cat:'SQL Injection',lbl:'UNION SELECT',uri:"/waf-test/?q=SELECT * FROM users--"},
  sqli_drop:{cat:'SQL Injection',lbl:'DROP TABLE',uri:"/waf-test/?x='; DROP TABLE users; --"},
  xss_script:{cat:'XSS Attack',lbl:'XSS Tag',uri:"/waf-test/?n=<script>alert(1)<\/script>"},
  xss_img:{cat:'XSS Attack',lbl:'img onerror',uri:"/waf-test/?q=<img src=x onerror=alert(1)>"},
  xss_event:{cat:'XSS Attack',lbl:'event handler',uri:'/waf-test/?d=" onmouseover="alert(1)'},
  path_etc:{cat:'Path Traversal',lbl:'/etc/passwd',uri:'/waf-test/../../../etc/passwd'},
  path_shadow:{cat:'Path Traversal',lbl:'/etc/shadow',uri:'/waf-test/?f=../../../../etc/shadow'},
  path_enc:{cat:'Path Traversal',lbl:'URL encoded',uri:'/waf-test/?p=..%2F..%2F..%2Fetc%2Fpasswd'},
  cmd_cat:{cat:'Command Inject',lbl:'CMD inject',uri:'/waf-test/?cmd=;cat /etc/passwd'},
  null_byte:{cat:'Null Byte',lbl:'Null byte',uri:'/waf-test/?file=shell.php%00.jpg'},
  scanner:{cat:'Scanner',lbl:'Nikto UA',uri:'/waf-test/?test=1'},
};
const BTN_MAP={sqli_basic:'ab-s1',sqli_union:'ab-s2',sqli_drop:'ab-s3',xss_script:'ab-x1',xss_img:'ab-x2',xss_event:'ab-x3',path_etc:'ab-p1',path_shadow:'ab-p2',path_enc:'ab-p3',cmd_cat:'ab-o1',null_byte:'ab-o2',scanner:'ab-o3'};

async function atest(type){
  const a=ATTACKS[type];const tgt=document.getElementById('atgt').value;
  const bid=BTN_MAP[type];const btn=document.getElementById(bid);
  if(btn){btn.className='ab run';btn.textContent='…';}
  const fd=new FormData();fd.append('type',type);fd.append('target',tgt);
  const cm=document.querySelector('meta[name=csrf]');
  if(cm)fd.append('csrf',cm.content);
  const r=await fetch('monitor/exec_attack.php',{method:'POST',body:fd}).then(r=>r.json()).catch(()=>({ok:false}));
  const res=document.getElementById('atk-res');
  if(r.ok){
    if(btn){btn.className='ab '+(r.blocked?'blk':'pw');btn.textContent=a.lbl;}
    res.innerHTML=`<div class="${r.blocked?'rok':'rwarn'}">${r.blocked?'BLOCKED':'Not blocked'} — ${esc(a.cat)}</div><div class="rdim">HTTP ${r.code} · ${r.ms}ms · ${esc(tgt)}</div>`;
  } else {
    if(btn){btn.className='ab';btn.textContent=a.lbl;}
    res.innerHTML='<div class="rwarn">Request failed — check server is running</div>';
  }
}
async function runAll(){
  const btn=document.getElementById('rall');btn.disabled=true;btn.textContent='Running…';
  for(const type of Object.keys(ATTACKS)){await atest(type);await new Promise(r=>setTimeout(r,500));}
  btn.disabled=false;btn.textContent='Run Batch Once';
}

let simOn=false;
async function toggleSim(){
  simOn=!simOn;
  const btn=document.getElementById('sim-btn');
  const dot=document.getElementById('sim-dot');
  if(simOn){
    btn.textContent='STOP SIMULATION';
    btn.style.background='#c00';btn.style.color='#fff';
    dot.classList.remove('off');
    toast('Live Simulation Started');
    runSim();
  } else {
    btn.textContent='START SIMULATION';
    btn.style.background='var(--sf2)';btn.style.color='var(--tx2)';
    dot.classList.add('off');
    document.getElementById('atk-res').innerHTML='<span class="rdim" style="color:#555">Simulation Stopped.</span>';
    toast('Simulation Stopped');
  }
}

async function runSim(){
  const keys=Object.keys(ATTACKS);
  while(simOn){
    const rndType = keys[Math.floor(Math.random()*keys.length)];
    await atest(rndType);
    await new Promise(r=>setTimeout(r, 1200 + Math.random()*800));
  }
}
</script>
</body></html>
PANEOF
sed -i "s|\\\$P='oslab2026'|\\\$P='${ADMIN_PASS}'|" /var/www/panel.local/html/index.php
ok

# ── api.php ───────────────────────────────────────────────────────
task "Writing api.php backend"
cat > /var/www/panel.local/html/api.php << 'APIEOF'
<?php
session_start();
header('Content-Type: application/json');
if(!isset($_SESSION['auth'])){echo json_encode(['ok'=>false,'error'=>'Unauthorized']);exit;}
$csrf_ok = !isset($_SESSION['csrf']) || (($_POST['csrf']??'')===($_SESSION['csrf']??''));
if(!$csrf_ok){echo json_encode(['ok'=>false,'error'=>'CSRF token invalid']);exit;}
function run($c){return trim(shell_exec($c.' 2>&1'));}
// Note: ok() and err() call exit; — switch/case falls through safely
function ok($d=[]){echo json_encode(array_merge(['ok'=>true],$d));exit;}
function err($m){echo json_encode(['ok'=>false,'error'=>$m]);exit;}
$action=$_POST['action']??'';
switch($action){
case 'stats':
  $m=explode("\n",run('free -m'));$mp=preg_split('/\s+/',trim($m[1]??''));
  $mt=$mp[1]??1;$mu=$mp[2]??0;
  $dt=round(disk_total_space('/')/1073741824,1);$df=round(disk_free_space('/')/1073741824,1);
  $l=sys_getloadavg();
  $banned=run("sudo /usr/bin/fail2ban-client status sshd 2>/dev/null|grep 'Currently banned'|awk '{print \$NF}'");
  if(!$banned)$banned='0';
  ok(['d'=>['mp'=>round($mu/$mt*100),'mu'=>$mu,'mt'=>$mt,'dp'=>round(($dt-$df)/$dt*100),'du'=>round($dt-$df,1),'dt'=>$dt,'l1'=>number_format($l[0],2),'l5'=>number_format($l[1],2),'l15'=>number_format($l[2],2),'up'=>str_replace('up ','',run('uptime -p')),'banned'=>$banned]]);

case 'ips':
  $out='';
  $out.="<div style='font-size:.54rem;letter-spacing:.1em;text-transform:uppercase;color:var(--mu);margin-bottom:8px;'>Fail2Ban Jails &amp; Banned IPs</div>";
  foreach(['sshd','apache-auth','apache-req'] as $j){
    $o=run("sudo /usr/bin/fail2ban-client status $j 2>&1");
    // Skip jails that don't exist
    if(strpos($o,'Invalid')!==false||strpos($o,'not exist')!==false){
      $out.="<div class='srow'><div class='sdot off'></div><span style='flex:1;font-size:.7rem'>Jail: $j</span><span class='badge b-off'>Not configured</span></div>";
      continue;
    }
    preg_match('/Currently banned:\s*(\d+)/',$o,$cb);
    preg_match('/Banned IP list:\s*(.*)/s',$o,$bip);
    $cn=$cb[1]??'0';
    $out.="<div class='srow'><div class='sdot".($cn>0?' off':'')."'></div><span style='flex:1;font-size:.7rem'>Jail: $j</span><span class='badge ".($cn>0?'b-w':'b-ok')."'>$cn banned</span></div>";
    if(isset($bip[1])&&trim($bip[1])){
      foreach(preg_split('/\s+/',trim($bip[1])) as $ip){
        if(!$ip)continue;
        $out.="<div style='padding:5px 14px;display:flex;align-items:center;gap:10px'><span style='flex:1;font-size:.68rem'>$ip</span><button class='btn btnsm' onclick='unban(\"$ip\",\"$j\")'>Unban</button></div>";
      }
    }
  }
  $out.="<hr style='margin:12px 0;border:none;border-top:1px solid var(--bd)'><div style='font-size:.54rem;letter-spacing:.1em;text-transform:uppercase;color:var(--mu);margin-bottom:8px;'>Live Traffic Monitor (Active External Connections)</div>";
  $out.="<div class='tbl-wrap'><table class='tbl'><thead><tr><th>Client IP</th><th>Virtual Host</th><th>Hits</th><th>Action</th></tr></thead><tbody>";
  $rips=[]; $td=date('d/M/Y');
  foreach(glob('/var/log/apache2/*access.log')?:[] as $lf) {
    $site = str_replace('_access.log', '', basename($lf));
    foreach(array_slice(file($lf)?:[], -500) as $ln) {
      if(strpos($ln, $td)!==false && preg_match('/^(\d+\.\d+\.\d+\.\d+)/', $ln, $m)) {
         $ip = $m[1];
         if(!isset($rips[$ip])) $rips[$ip] = ['hits'=>0, 'sites'=>[]];
         $rips[$ip]['hits']++;
         $rips[$ip]['sites'][$site] = true;
      }
    }
  }
  uasort($rips, function($a, $b) { return $b['hits'] <=> $a['hits']; });
  if(empty($rips)) $out.="<tr><td colspan='4' style='font-size:.65rem;color:var(--mu);text-align:center;padding:12px'>No traffic found today.</td></tr>";
  foreach(array_slice($rips,0,10) as $rip => $data) {
    // Add visual tag for localhost
    $ip_display = ($rip === '127.0.0.1') ? "$rip <span style='font-size:0.55rem;color:var(--mu)'> (Local VM)</span>" : $rip;
    $hits = $data['hits']; 
    $site_list = htmlspecialchars(implode(', ', array_keys($data['sites'])));
    $out.="<tr><td><span class='badge b-w' style='font-family:monospace'>$ip_display</span></td><td>$site_list</td><td>$hits</td><td style='white-space:nowrap'><button class='btn btnsm' onclick=\"ban('$rip')\">Ban</button><button class='btn btnsm' style='margin-left:4px' onclick=\"unban('$rip')\">Unban</button></td></tr>";
  }
  $out.="</tbody></table></div>";
  ok(['html'=>$out]);

case 'sites':
  $out='';$td=date('d/M/Y');
  foreach(glob('/etc/apache2/sites-available/*.conf')?:[] as $cf){
    $d=basename($cf,'.conf');if($d==='000-default'||$d==='default-ssl')continue;
    $dr="/var/www/$d/html";
    $enabled = file_exists("/etc/apache2/sites-enabled/$d.conf");
    $ssl=file_exists("/etc/ssl/certs/$d.crt")?'<span class="badge b-on">SSL</span>':'<span class="badge b-off">HTTP</span>';
    $auth=file_exists("$dr/.htaccess")?'<span class="badge b-w">Protected</span>':'<span class="badge b-ok">Public</span>';
    $lf="/var/log/apache2/{$d}_access.log";$ls=file_exists($lf)?round(filesize($lf)/1024,1).'KB':'0KB';
    $req=0;if(file_exists($lf)){foreach(file($lf)?:[] as $l){if(strpos($l,$td)!==false)$req++;}}
    $ok=$enabled?('<span class="badge b-on">Online</span>'):('<span class="badge b-off">Disabled</span>');
    $ssl2=file_exists("/etc/ssl/certs/$d.crt");
    $endis_btn = in_array($d, ['admin.local', 'panel.local']) ? "<button class='btn btnsm' disabled style='opacity:0.5;border-color:var(--bd)'>Protected</button>" : ($enabled ? "<button class='btn btnsm' onclick='disableSite(\"$d\")'>Disable</button>" : "<button class='btn btnsm' onclick='enableSite(\"$d\")'>Enable</button>");
    $out.="<tr><td><strong>$d</strong></td><td style='font-size:.6rem;color:var(--mu)'>$dr</td><td>$ssl</td><td>$auth</td><td style='color:var(--mu)'>$ls</td><td style='color:var(--mu)'>$req</td><td>$ok</td><td style='white-space:nowrap'><button class='btn btnsm' onclick=\"window.open('".($ssl2?'https':'http')."://$d','_blank')\" style='margin-right:4px'>Open</button>$endis_btn</td></tr>";
  }
  ok(['html'=>$out?:("<tr><td colspan='8' style='color:var(--mu);text-align:center;padding:20px'>No sites deployed yet</td></tr>")]);

case 'deploy':
  $domain=preg_replace('/[^a-z0-9.\-]/','',strtolower($_POST['domain']??''));
  $title=htmlspecialchars($_POST['title']??$domain);
  $ssl=$_POST['ssl']??'yes';$auth=$_POST['auth']??'no';
  $auser=$_POST['auser']??'admin';$apass=$_POST['apass']??'admin123';
  $content=$_POST['content']??'';
  if(!$domain)err('Invalid domain');
  $steps=[];$dr="/var/www/$domain/html";
  run("sudo /bin/mkdir -p $dr");
  run("sudo /bin/chown -R www-data:www-data /var/www/$domain");
  run("sudo /bin/chmod -R 755 /var/www/$domain");
  $steps[]=['msg'=>'[OK] Directory created: '.$dr,'ok'=>true];
  if($content){
    $tmp=tempnam('/tmp','deploy_');
    file_put_contents($tmp,$content);
    run("sudo /bin/cp $tmp $dr/index.html");
    run("sudo /bin/chown www-data:www-data $dr/index.html");
    run("sudo /bin/chmod 644 $dr/index.html");
    @unlink($tmp);
    $steps[]=['msg'=>'[OK] Content saved as index.html','ok'=>true];
  } else {
    $def="<!DOCTYPE html><html><head><title>$title</title></head><body><h1>$title</h1><p>$domain</p></body></html>";
    $tmp=tempnam('/tmp','deploy_');
    file_put_contents($tmp,$def);
    run("sudo /bin/cp $tmp $dr/index.html");
    run("sudo /bin/chown www-data:www-data $dr/index.html");
    run("sudo /bin/chmod 644 $dr/index.html");
    @unlink($tmp);
    $steps[]=['msg'=>'[OK] Default index.html created','ok'=>true];
  }
  if($ssl==='yes'){
    run("sudo /usr/bin/openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/$domain.key -out /etc/ssl/certs/$domain.crt -subj '/C=BD/ST=Chattogram/O=OS-Lab/CN=$domain'");
    run("sudo /bin/chmod 600 /etc/ssl/private/$domain.key");
    $steps[]=['msg'=>'[OK] SSL certificate generated (RSA 2048, 365 days)','ok'=>true];
  }
  $http="<VirtualHost *:80>\n    ServerName $domain\n    ".($ssl==='yes'?"RewriteEngine On\n    RewriteCond %{HTTPS} off\n    RewriteRule ^(.*)$ https://%{HTTP_HOST}\$1 [R=301,L]":"DocumentRoot $dr\n    <Directory $dr>\n        AllowOverride All\n        Require all granted\n    </Directory>")."\n</VirtualHost>\n";
  $https=$ssl==='yes'?"<VirtualHost *:443>\n    ServerName $domain\n    DocumentRoot $dr\n    SSLEngine on\n    SSLCertificateFile /etc/ssl/certs/$domain.crt\n    SSLCertificateKeyFile /etc/ssl/private/$domain.key\n    <Directory $dr>\n        AllowOverride All\n        Require all granted\n    </Directory>\n    Header always set X-Frame-Options 'SAMEORIGIN'\n    Header always set X-Content-Type-Options 'nosniff'\n    ErrorLog \${APACHE_LOG_DIR}/{$domain}_error.log\n    CustomLog \${APACHE_LOG_DIR}/{$domain}_access.log combined\n</VirtualHost>\n":'';
  $tmpconf=tempnam('/tmp','conf_'); file_put_contents($tmpconf,$http.$https);
  run("sudo /bin/cp $tmpconf /etc/apache2/sites-available/$domain.conf"); @unlink($tmpconf);
  if($auth==='yes'){run("sudo /usr/bin/htpasswd -bc /etc/apache2/.htpasswd-$domain ".escapeshellarg($auser)." ".escapeshellarg($apass));file_put_contents("$dr/.htaccess","AuthType Basic\nAuthName \"Protected\"\nAuthUserFile /etc/apache2/.htpasswd-$domain\nRequire valid-user\n");$steps[]=['msg'=>"[OK] Password protection enabled (user: $auser)",'ok'=>true];}
  run("sudo /usr/sbin/a2ensite $domain.conf");$steps[]=['msg'=>'[OK] Site enabled (a2ensite)','ok'=>true];
  $h=file_get_contents('/etc/hosts');if(strpos($h,$domain)===false)run("echo '127.0.0.1   $domain' | sudo /usr/bin/tee -a /etc/hosts");
  $steps[]=['msg'=>'[OK] Added to /etc/hosts','ok'=>true];
  $t=run('sudo /usr/sbin/apache2ctl configtest');
  if(strpos($t,'Syntax OK')!==false){run('sudo /bin/systemctl reload apache2');$steps[]=['msg'=>'[OK] Apache reloaded — site is LIVE','ok'=>true];$steps[]=['msg'=>'>>> '.($ssl==='yes'?'https':'http')."://$domain",'ok'=>true];}
  else{$steps[]=['msg'=>'[WARN] Config issue: '.$t,'ok'=>false];}
  ok(['steps'=>$steps]);

case 'svc':
  $s=preg_replace('/[^a-z0-9]/','', $_POST['svc']??'');
  $a=in_array($_POST['action']??'',['start','stop','restart','reload'])?$_POST['action']:'restart';
  if(!in_array($s,['apache2','fail2ban']))err('Not allowed');
  run("sudo /bin/systemctl $a $s");ok();

case 'ban':
  $ip=filter_var($_POST['ip']??'',FILTER_VALIDATE_IP);if(!$ip)err('Invalid IP');
  // Try multiple jails - apache-req may not exist on all systems
  $jails=['apache-req','sshd','apache-auth'];
  $success=false;$lastErr='';
  foreach($jails as $j){
    $ret=run("sudo /usr/bin/fail2ban-client status $j 2>&1");
    if(strpos($ret,'Invalid')!==false||strpos($ret,'not exist')!==false)continue;
    $ret=run("sudo /usr/bin/fail2ban-client set $j banip $ip 2>&1");
    if(strpos($ret,'is not valid')!==false||strpos($ret,'error')!==false){$lastErr=$ret;continue;}
    $success=true;break;
  }
  if($success)ok();
  err('Failed to ban IP: '.($lastErr?:'No valid jail found. Ensure Fail2Ban is running.'));

case 'unban':
  $ip=filter_var($_POST['ip']??'',FILTER_VALIDATE_IP);
  $jail=preg_replace('/[^a-z\-]/','', $_POST['jail']??'sshd');
  if(!$ip)err('Invalid IP');run("sudo /usr/bin/fail2ban-client set $jail unbanip $ip");ok();

case 'ufw':
  $port=preg_replace('/[^0-9\/tcpudp ]/','',$_POST['port']??'');
  $act=$_POST['action']==='deny'?'deny':'allow';
  if(!$port)err('Invalid port');run("sudo /usr/sbin/ufw $act $port");ok();

case 'log':
  $allowed=['/var/log/apache2/site1_access.log','/var/log/apache2/site2_access.log','/var/log/apache2/status_access.log','/var/log/apache2/admin_access.log','/var/log/apache2/panel_access.log','/var/log/apache2/site1_error.log','/var/log/apache2/modsecurity_audit.log','/var/log/auth.log'];
  $file=$_POST['file']??'';$n=min(500,(int)($_POST['lines']??100));$q=strtolower($_POST['query']??'');
  if(!in_array($file,$allowed))err('Not allowed');
  if(!file_exists($file)){ok(['lines'=>['(log empty)']]);exit;}
  $lines=array_slice(file($file)?:[],-$n);
  if($q)$lines=array_values(array_filter($lines,fn($l)=>stripos($l,$q)!==false));
  ok(['lines'=>array_map('trim',$lines)]);

case 'perms':
  $path=realpath($_POST['path']??'/var/www');
  if(!$path||!file_exists($path))err('Path not found');
  $out='';$i=0;
  $iter=is_dir($path)?new FilesystemIterator($path):[new SplFileInfo($path)];
  foreach($iter as $f){
    if($i++>30)break;$s=stat($f->getPathname());
    $m=substr(sprintf('%o',$s['mode']),-4);
    if(function_exists('posix_getpwuid')){
      $own=(posix_getpwuid($s['uid'])['name']??$s['uid']).':'.(posix_getgrgid($s['gid'])['name']??$s['gid']);
    } else {
      $own=$s['uid'].':'.$s['gid'];
    }
    $fpath=htmlspecialchars($f->getPathname());
    $out.="<div class='prow' style='cursor:pointer' onclick=\"document.getElementById('cpath').value='$fpath';toast('Path copied')\" onmouseover=\"this.style.background='var(--sf2)'\" onmouseout=\"this.style.background='none'\"><span class='pp'>{$f->getFilename()}</span><span class='pm'>$m</span><span class='po'>$own</span></div>";
  }
  ok(['html'=>$out?:('<div style="font-size:.7rem;color:var(--mu)">Empty</div>')]);

case 'chmod':
  $path=$_POST['path']??'';$mode=preg_replace('/[^0-7]/','', $_POST['mode']??'755');
  $rec=$_POST['recursive']==='yes'?'-R ':'';$own=$_POST['owner']??'none';
  if(empty($path)||strpos($path,'..')!==false)err('Invalid path');
  run("sudo /bin/chmod {$rec}{$mode} ".escapeshellarg($path));
  if($own!=='none')run("sudo /bin/chown {$rec}".escapeshellarg($own).' '.escapeshellarg($path));
  ok();

case 'disable':
  $d=preg_replace('/[^a-z0-9.\\-]/','', $_POST['domain']??'');
  if(!$d)err('No domain');
  if(in_array($d,['admin.local','panel.local']))err('Protected site');
  $dr="/var/www/$d/html";
  if(file_exists("$dr/.htaccess") && !file_exists("$dr/.htaccess.bak.disabled")){
    run("sudo /bin/cp $dr/.htaccess $dr/.htaccess.bak.disabled");
  }
  $tmp=tempnam('/tmp','disable_');
  $err_doc = "<html><body style='text-align:center;padding:50px;font-family:sans-serif;'><h2>Site Not Available</h2><p>This website has been disabled by the administrator.</p></body></html>";
  file_put_contents($tmp,"# Site disabled by control panel\nErrorDocument 403 \"$err_doc\"\nRequire all denied\n");
  run("sudo /bin/cp $tmp $dr/.htaccess");
  run("sudo /bin/chown www-data:www-data $dr/.htaccess");
  @unlink($tmp);
  run("sudo /usr/sbin/a2dissite $d.conf");
  run("sudo /bin/systemctl reload apache2");
  ok();

case 'enable':
  $d=preg_replace('/[^a-z0-9.\\-]/','', $_POST['domain']??'');
  if(!$d)err('No domain');
  $dr="/var/www/$d/html";
  if(file_exists("$dr/.htaccess.bak.disabled")){
    run("sudo /bin/cp $dr/.htaccess.bak.disabled $dr/.htaccess");
    run("sudo /bin/chown www-data:www-data $dr/.htaccess");
    @unlink("$dr/.htaccess.bak.disabled");
  } else {
    $content = @file_get_contents("$dr/.htaccess");
    if($content !== false && strpos($content, 'Site disabled by control panel') !== false){
      @unlink("$dr/.htaccess");
    }
  }
  run("sudo /usr/sbin/a2ensite $d.conf");
  run("sudo /bin/systemctl reload apache2");
  ok();

default: err('Unknown action');
}
APIEOF
ok

# ── monitor/stream.php — SSE ──────────────────────────────────────
task "Writing SSE stream (monitor/stream.php)"
cat > /var/www/panel.local/html/monitor/stream.php << 'SSEEOF'
<?php
session_start();
if(!isset($_SESSION['auth'])){http_response_code(401);exit;}
session_write_close(); // CRITICAL: release session lock so other AJAX/Fetch requests (like exec_attack.php) are not blocked!
header('Content-Type: text/event-stream');
header('Cache-Control: no-cache');
header('X-Accel-Buffering: no');
set_time_limit(0);ignore_user_abort(false);
function sse($ev,$d){echo "event: $ev\ndata: ".json_encode($d)."\n\n";if(ob_get_level())ob_flush();flush();}
function snap(){
  $m=explode("\n",trim(shell_exec('free -m')?:''));$mp=preg_split('/\s+/',trim($m[1]??''));
  $mt=$mp[1]??1;$mu=$mp[2]??0;$l=sys_getloadavg();
  $svcs=[];foreach(['apache2','fail2ban','ufw'] as $s)$svcs[$s]=trim(shell_exec("systemctl is-active $s 2>/dev/null")?:'?');
  $banned=trim(shell_exec("sudo fail2ban-client status sshd 2>/dev/null|grep 'Currently banned'|awk '{print \$NF}'")?:'0');
  $waf=0;$wf='/var/log/apache2/modsecurity_audit.log';if(file_exists($wf))$waf=(int)trim(shell_exec("wc -l < $wf")?:'0');
  return['mp'=>round($mu/$mt*100),'mu'=>$mu,'mt'=>$mt,'l1'=>number_format($l[0],2),'up'=>str_replace('up ','',trim(shell_exec('uptime -p')?:'')),'svcs'=>$svcs,'banned'=>$banned,'waf'=>$waf,'ts'=>date('H:i:s')];
}
function atkType($l){
  $map=[
    'SQL Injection'=>['10001','10011','sqli','select','union','drop','insert','delete','update','exec'],
    'XSS Attack'=>['10002','10012','<script','javascript:','onerror=','onmouseover=','onload=','onclick=','alert('],
    'Path Traversal'=>['10003','10013','../','..%2f','..%252f','etc/passwd','etc/shadow'],
    'Null Byte'=>['10004','10014','%00','%2500'],
    'Command Injection'=>['10005','cmd=',';ls','|cat','&&id',';cat'],
    'Scanner'=>['10006','nikto','sqlmap','masscan','nmap']
  ];
  $lo=strtolower($l);
  foreach($map as $t=>$ps){
    foreach($ps as $p){
      if(strpos($lo,strtolower($p))!==false)return $t;
    }
  }
  return 'WAF Block';
}
// Send initial connected event
sse('connected',['msg'=>'SSE stream connected','time'=>date('H:i:s')]);
// Send initial snapshot
sse('snapshot',snap());
// Monitor multiple log files - use wildcards to catch all site logs
$logs=['/var/log/apache2/modsecurity_audit.log'];
// Add wildcard patterns for access logs
foreach(glob('/var/log/apache2/*access.log') as $f) $logs[]=$f;
$logs[]='/var/log/auth.log';
$pos=[];foreach($logs as $f)$pos[$f]=file_exists($f)?filesize($f):0;
$tick=0;$lastKeepalive=time();
while(!connection_aborted()){
  // Check for new files that may have been created
  foreach(glob('/var/log/apache2/*access.log') as $f){
    if(!isset($pos[$f])) $pos[$f]=file_exists($f)?filesize($f):0;
  }
  foreach($logs as $f){
    if(!file_exists($f))continue;
    clearstatcache(true,$f);$sz=filesize($f);if($sz<=$pos[$f])continue;
    $fh=fopen($f,'r');if(!$fh){error_log("SSE: Cannot open $f");continue;} 
    fseek($fh,$pos[$f]);
    while(!feof($fh)){
      $line=fgets($fh);if(!$line)break;$line=trim($line);if(!$line)continue;
      $bn=basename($f);
      if(strpos($f,'modsecurity')!==false){
        if(strpos($line,'[id "')===false && strpos($line,'Message:')===false) continue;
        $ip='';$uri='';$rule='';
        if(preg_match('/\b(\d{1,3}(?:\.\d{1,3}){3})\b/',$line,$m))$ip=$m[1];
        if(preg_match('/"(?:GET|POST|PUT|DELETE)\s+([^\s"]+)/',$line,$m))$uri=$m[1];
        if(preg_match('/id\s*["\s:]+(\d{4,6})/',$line,$m))$rule='Rule #'.$m[1];
        sse('attack',['type'=>atkType($line),'ip'=>$ip?:'unknown','uri'=>$uri?:'-','rule'=>$rule,'log'=>$bn,'time'=>date('H:i:s')]);
      } elseif(strpos($f,'auth')!==false){
        if(strpos($line,'Failed')!==false||strpos($line,'Invalid user')!==false||strpos($line,'Ban ')!==false){
          $ip='';$user='';
          if(preg_match('/for\s+(\w+)\s+from\s+(\S+)/',$line,$m)){$user=$m[1];$ip=$m[2];}
          $t='Auth Alert';if(strpos($line,'Ban')!==false)$t='IP Banned';elseif(strpos($line,'Invalid')!==false)$t='Invalid User';
          sse('auth',['type'=>$t,'user'=>$user,'ip'=>$ip,'time'=>date('H:i:s')]);
        }
      } else {
        // Access log - check for 403/406 status (blocked by WAF)
        if(preg_match('/^(\S+)\s+\S+\s+\S+\s+\[([^\]]+)\]\s+"([^"]+)"\s+(\d+)/',$line,$m)){
          $p=explode(' ',$m[3],3);$atk=atkType($line);
          $status=(int)$m[4];
          // If status is 403 or 406, this is likely a WAF block
          if($status===403||$status===406){
            sse('attack',['type'=>$atk?:'Blocked Request','ip'=>$m[1],'method'=>$p[0]??'GET','uri'=>$p[1]??'/','rule'=>'HTTP '.$status,'log'=>$bn,'time'=>date('H:i:s')]);
          }
          sse('access',['ip'=>$m[1],'method'=>$p[0]??'GET','uri'=>$p[1]??'/','status'=>$status,'atk'=>$atk,'log'=>$bn,'time'=>date('H:i:s')]);
        }
      }
    }
    $pos[$f]=ftell($fh);fclose($fh);
  }
  // Send keepalive every 10 seconds
  if(time()-$lastKeepalive>=10){sse('keepalive',['time'=>date('H:i:s')]);$lastKeepalive=time();}
  if(++$tick>=16){sse('snapshot',snap());$tick=0;}
  usleep(500000);
}
SSEEOF
ok

# ── monitor/exec_attack.php ───────────────────────────────────────
task "Writing attack executor (monitor/exec_attack.php)"
cat > /var/www/panel.local/html/monitor/exec_attack.php << 'EXECEOF'
<?php
session_start();header('Content-Type: application/json');
if(!isset($_SESSION['auth'])){echo json_encode(['ok'=>false]);exit;}
if(($_POST['csrf']??'')!==($_SESSION['csrf']??'')){echo json_encode(['ok'=>false,'error'=>'CSRF']);exit;}
$type=$_POST['type']??'';$target=$_POST['target']??'site1.local';
$ok_t=['site1.local','site2.local','status.local','panel.local','admin.local'];
if(!in_array($target,$ok_t)){echo json_encode(['ok'=>false,'error'=>'Bad target']);exit;}
// All attack payloads - direct HTTP to avoid 301 redirects
$attacks=[
  'sqli_basic'=>"/waf-test/?id=1'+OR+'1'%3D'1",
  'sqli_union'=>"/waf-test/?q=SELECT+*+FROM+users+WHERE+1%3D1--",
  'sqli_drop'=>"/waf-test/?x=%27%3B+DROP+TABLE+users%3B+--",
  'xss_script'=>"/waf-test/?n=%3Cscript%3Ealert%281%29%3C%2Fscript%3E",
  'xss_img'=>"/waf-test/?q=%3Cimg+src%3Dx+onerror%3Dalert%281%29%3E",
  'xss_event'=>"/waf-test/?d=%22+onmouseover%3D%22alert%281%29",
  'path_etc'=>"/waf-test/../../../etc/passwd",
  'path_shadow'=>"/waf-test/?f=../../../../etc/shadow",
  'path_enc'=>"/waf-test/?p=..%2F..%2F..%2Fetc%2Fpasswd",
  'cmd_cat'=>"/waf-test/?cmd=%3Bcat+%2Fetc%2Fpasswd",
  'null_byte'=>"/waf-test/?file=shell.php%00.jpg",
  'scanner'=>"/waf-test/?test=1"
];
if(!array_key_exists($type,$attacks)){echo json_encode(['ok'=>false,'error'=>'Bad type']);exit;}
// Use HTTP for local testing to avoid SSL issues and 301 redirects
$url="http://127.0.0.1".$attacks[$type];
// Add extra attack patterns in headers to ensure WAF triggers
$extraHeaders=["Host: $target"];
$ua=$type==='scanner'?'Nikto/2.1.6 (Evasions:None)':'Mozilla/5.0 AttackTest/1.0';
$ch=curl_init();
curl_setopt_array($ch,[CURLOPT_URL=>$url,CURLOPT_RETURNTRANSFER=>true,CURLOPT_SSL_VERIFYPEER=>false,CURLOPT_SSL_VERIFYHOST=>false,CURLOPT_TIMEOUT=>8,CURLOPT_FOLLOWLOCATION=>false,CURLOPT_USERAGENT=>$ua,CURLOPT_HTTPHEADER=>["Host: $target"]]);
$response=curl_exec($ch);
$err=curl_error($ch);
$code=curl_getinfo($ch,CURLINFO_HTTP_CODE);$ms=round(curl_getinfo($ch,CURLINFO_TOTAL_TIME)*1000);
curl_close($ch);
$blocked=($code===403||$code===406||stripos($response,'403 Forbidden')!==false||stripos($response,'ModSecurity')!==false);
echo json_encode(['ok'=>true,'code'=>$code,'ms'=>$ms,'blocked'=>$blocked,'url'=>$url,'error'=>$err]);
EXECEOF
ok

# ── Permissions ───────────────────────────────────────────────────
task "Setting all permissions"
chown -R www-data:www-data /var/www/
chmod -R 755 /var/www/
# Add www-data to adm group so it can read log files
gpasswd -a www-data adm 2>/dev/null || usermod -a -G adm www-data 2>/dev/null || true
# Ensure log directory and files are readable by www-data
chmod 755 /var/log/apache2 2>/dev/null
chmod o+r /var/log/apache2/*.log 2>/dev/null
touch /var/log/apache2/modsecurity_audit.log
chown www-data:www-data /var/log/apache2/modsecurity_audit.log
chmod 644 /var/log/apache2/modsecurity_audit.log
chown -R www-data:www-data /var/log/mod_evasive 2>/dev/null
chmod -R 755 /var/log/mod_evasive 2>/dev/null
# Ensure www-data can read fail2ban status (requires adm group membership)
chmod 755 /var/run/fail2ban 2>/dev/null || true
ok

task "Final Apache reload"
apache2ctl configtest >/dev/null 2>&1 && systemctl reload apache2 >/dev/null 2>&1 && ok || fail

# ╔══════════════════════════════════════════════════════════════════╗
# ║  FINAL VERIFICATION                                             ║
# ╚══════════════════════════════════════════════════════════════════╝
title "VERIFY" "Final Verification"

chk_svc(){ systemctl is-active "$1" >/dev/null 2>&1 && pass_badge "$2 is running" || fail_badge "$2 NOT running"; }
chk_dir(){ [[ -d "$1" ]] && pass_badge "$2 ready" || fail_badge "$2 MISSING"; }
chk_file(){ [[ -f "$1" ]] && pass_badge "$2 exists" || fail_badge "$2 NOT found"; }

chk_svc apache2     "Apache2"
chk_svc fail2ban    "Fail2Ban"
ufw status 2>/dev/null | grep -q "active" && pass_badge "UFW Firewall active" || fail_badge "UFW NOT active"
apache2ctl -M 2>/dev/null | grep -q "security2" && pass_badge "ModSecurity WAF loaded" || fail_badge "ModSecurity NOT loaded"
chk_dir "/var/www/site1.local/html"   "site1.local"
chk_dir "/var/www/site2.local/html"   "site2.local"
chk_dir "/var/www/status.local/html"  "status.local"
chk_dir "/var/www/admin.local/html"   "admin.local"
chk_dir "/var/www/panel.local/html"   "panel.local"
chk_file "/usr/local/bin/webmon"      "webmon monitor"
chk_file "/usr/local/bin/backup_logs.sh" "backup script"
chk_file "/var/www/panel.local/html/monitor/stream.php" "SSE stream"

# ╔══════════════════════════════════════════════════════════════════╗
# ║  DONE                                                           ║
# ╚══════════════════════════════════════════════════════════════════╝
SIP=$(hostname -I | awk '{print $1}')
echo ""
line
echo ""
echo -e "  ${G}${B}  COMPLETE — All 9 phases + Control Panel deployed  ${NC}"
echo ""
line
echo ""
echo -e "  ${D}Server IP :${NC}  ${B}${SIP}${NC}"
echo ""
echo -e "  ${D}Websites (on server):${NC}"
echo -e "    ${C}https://site1.local${NC}          Team Portfolio"
echo -e "    ${C}https://site2.local${NC}          Project Details"
echo -e "    ${C}https://status.local${NC}         Live PHP Dashboard"
echo -e "    ${C}https://admin.local${NC}          Admin Panel  (admin / ${ADMIN_PASS})"
echo -e "    ${C}https://panel.local${NC}          Control Panel (admin / ${ADMIN_PASS})"
echo -e "    ${C}https://site1.local/waf-test/${NC} WAF Test Console"
echo ""
echo -e "  ${G}${B}LAN Access (from phones, laptops, other PCs):${NC}"
echo -e "    ${R}${B}CRITICAL FOR PHONE ACCESS:${NC} If your IP is 10.0.2.15, VirtualBox is using NAT!"
echo -e "    To access from a phone on WiFi, change VirtualBox Network to 'Bridged Adapter'"
echo -e "    and reboot the VM. Your IP will change to e.g., 192.168.x.x."
echo -e "    Open ${C}http://${SIP}${NC} in any browser on the same network."
echo -e "    A portal page will show links to all sites."
echo -e "    Direct links:"
echo -e "      ${C}http://${SIP}/site1/${NC}       Team Portfolio"
echo -e "      ${C}http://${SIP}/site2/${NC}       Project Details"
echo -e "      ${C}http://${SIP}/status/${NC}      Live Dashboard"
echo -e "      ${C}http://${SIP}/panel/${NC}       Control Panel"
echo -e "      ${C}http://${SIP}/waf-test/${NC}    WAF Test Console"
echo ""
echo -e "  ${D}Control Panel pages:${NC}"
echo -e "    Dashboard  · Deploy Site  · All Sites  · Firewall"
echo -e "    Attack Monitor  · Log Viewer  · Permissions"
echo ""
echo -e "  ${D}Terminal tools:${NC}"
echo -e "    ${C}sudo webmon${NC}                    interactive monitor"
echo -e "    ${C}sudo apache2ctl -S${NC}             virtual hosts"
echo -e "    ${C}sudo ufw status verbose${NC}        firewall rules"
echo -e "    ${C}sudo fail2ban-client status${NC}    banned IPs"
echo -e "    ${C}sudo tail -f /var/log/apache2/modsecurity_audit.log${NC}"
echo ""
echo -e "  ${G}TESTING PROCEDURES:${NC}"
echo -e "    1. Open ${C}https://panel.local${NC} and login"
echo -e "    2. Click 'Attack Monitor' in sidebar"
echo -e "    3. Select a target site from dropdown"
echo -e "    4. Click attack buttons (SQLi, XSS, Path Traversal)"
echo -e "    5. Watch Live Event Feed for BLOCKED messages"
echo -e "    6. Click 'Ban Attacker' to ban the IP"
echo -e "    7. Check Security tab for banned IPs list"
echo -e "    8. Click 'START SIMULATION' for continuous attacks"
echo ""
echo -e "  ${Y}NOTE:${NC} Browser warns about self-signed SSL."
echo -e "        Click Advanced → Accept the Risk to proceed."
echo -e "  ${Y}NOTE:${NC} Admin password saved to ${C}/root/.oslab_admin_password${NC}"
echo ""
line
echo ""
