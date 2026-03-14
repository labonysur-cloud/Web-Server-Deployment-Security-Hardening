#!/bin/bash

# ============================================================
#  Web Server Deployment & Security Hardening
#  OS Lab Project | Ubuntu Linux | VirtualBox
#  Language: Bash
# ============================================================
#  Features:
#    1. Apache2 Web Server Installation
#    2. Virtual Hosting (two demo sites)
#    3. HTTPS with Self-Signed Certificate
#    4. UFW Firewall Setup
#    5. Access Monitoring (log viewer + fail2ban)
# ============================================================

# ---------- Colors for pretty terminal output ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ---------- Helper Functions ----------

print_header() {
    echo ""
    echo -e "${CYAN}${BOLD}============================================================${NC}"
    echo -e "${CYAN}${BOLD}  $1${NC}"
    echo -e "${CYAN}${BOLD}============================================================${NC}"
}

print_step() {
    echo -e "\n${YELLOW}[STEP]${NC} $1"
}

print_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ---------- Root Check ----------
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root. Use: sudo bash webserver_setup.sh"
    exit 1
fi

print_header "Web Server Deployment & Security Hardening"
echo -e "  Running on: $(lsb_release -ds)"
echo -e "  Date: $(date)"
echo ""

# ============================================================
# STEP 1 — System Update & Install Packages
# ============================================================
print_header "STEP 1: System Update & Package Installation"

print_step "Updating package lists..."
apt-get update -y > /dev/null 2>&1
print_ok "Package list updated."

print_step "Installing Apache2, OpenSSL, UFW, Fail2Ban, curl..."
apt-get install -y apache2 openssl ufw fail2ban curl > /dev/null 2>&1
print_ok "All packages installed."

# Enable Apache to start on boot
systemctl enable apache2 > /dev/null 2>&1
systemctl start apache2
print_ok "Apache2 service started and enabled on boot."


# ============================================================
# STEP 2 — Virtual Hosting Setup
# ============================================================
print_header "STEP 2: Virtual Hosting Configuration"

# --- Site 1: site1.local ---
print_step "Creating virtual host: site1.local"

mkdir -p /var/www/site1.local/html
cat > /var/www/site1.local/html/index.html <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Site 1 - OS Lab Project</title>
    <style>
        body { font-family: monospace; background: #0d1117; color: #58a6ff;
               display: flex; align-items: center; justify-content: center;
               height: 100vh; margin: 0; flex-direction: column; }
        h1   { font-size: 2.5rem; border-bottom: 2px solid #58a6ff; padding-bottom: 10px; }
        p    { color: #8b949e; }
        .badge { background: #238636; color: #fff; padding: 4px 12px;
                 border-radius: 4px; font-size: 0.85rem; margin-top: 10px; }
    </style>
</head>
<body>
    <h1>site1.local</h1>
    <p>Virtual Host #1 — Apache Web Server</p>
    <div class="badge">HTTPS Enabled</div>
</body>
</html>
EOF

chown -R www-data:www-data /var/www/site1.local
chmod -R 755 /var/www/site1.local

# Virtual host config for site1
cat > /etc/apache2/sites-available/site1.local.conf <<EOF
<VirtualHost *:80>
    ServerName site1.local
    ServerAlias www.site1.local
    DocumentRoot /var/www/site1.local/html
    ErrorLog \${APACHE_LOG_DIR}/site1_error.log
    CustomLog \${APACHE_LOG_DIR}/site1_access.log combined

    # Redirect HTTP to HTTPS
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}\$1 [R=301,L]
</VirtualHost>

<VirtualHost *:443>
    ServerName site1.local
    ServerAlias www.site1.local
    DocumentRoot /var/www/site1.local/html
    ErrorLog \${APACHE_LOG_DIR}/site1_error.log
    CustomLog \${APACHE_LOG_DIR}/site1_access.log combined

    SSLEngine on
    SSLCertificateFile    /etc/ssl/certs/site1.local.crt
    SSLCertificateKeyFile /etc/ssl/private/site1.local.key

    # Security Headers
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains"
    Header always set X-XSS-Protection "1; mode=block"
</VirtualHost>
EOF

print_ok "site1.local virtual host configured."

# --- Site 2: site2.local ---
print_step "Creating virtual host: site2.local"

mkdir -p /var/www/site2.local/html
cat > /var/www/site2.local/html/index.html <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Site 2 - OS Lab Project</title>
    <style>
        body { font-family: monospace; background: #1a0a2e; color: #c084fc;
               display: flex; align-items: center; justify-content: center;
               height: 100vh; margin: 0; flex-direction: column; }
        h1   { font-size: 2.5rem; border-bottom: 2px solid #c084fc; padding-bottom: 10px; }
        p    { color: #9ca3af; }
        .badge { background: #7c3aed; color: #fff; padding: 4px 12px;
                 border-radius: 4px; font-size: 0.85rem; margin-top: 10px; }
    </style>
</head>
<body>
    <h1>site2.local</h1>
    <p>Virtual Host #2 — Apache Web Server</p>
    <div class="badge">HTTPS Enabled</div>
</body>
</html>
EOF

chown -R www-data:www-data /var/www/site2.local
chmod -R 755 /var/www/site2.local

# Virtual host config for site2
cat > /etc/apache2/sites-available/site2.local.conf <<EOF
<VirtualHost *:80>
    ServerName site2.local
    ServerAlias www.site2.local
    DocumentRoot /var/www/site2.local/html
    ErrorLog \${APACHE_LOG_DIR}/site2_error.log
    CustomLog \${APACHE_LOG_DIR}/site2_access.log combined

    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}\$1 [R=301,L]
</VirtualHost>

<VirtualHost *:443>
    ServerName site2.local
    ServerAlias www.site2.local
    DocumentRoot /var/www/site2.local/html
    ErrorLog \${APACHE_LOG_DIR}/site2_error.log
    CustomLog \${APACHE_LOG_DIR}/site2_access.log combined

    SSLEngine on
    SSLCertificateFile    /etc/ssl/certs/site2.local.crt
    SSLCertificateKeyFile /etc/ssl/private/site2.local.key

    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains"
    Header always set X-XSS-Protection "1; mode=block"
</VirtualHost>
EOF

print_ok "site2.local virtual host configured."


# ============================================================
# STEP 3 — HTTPS: Self-Signed SSL Certificates
# ============================================================
print_header "STEP 3: HTTPS — Generating Self-Signed SSL Certificates"

# Enable required Apache modules
a2enmod ssl rewrite headers > /dev/null 2>&1
print_ok "Apache modules enabled: ssl, rewrite, headers."

generate_cert() {
    local DOMAIN=$1
    print_step "Generating SSL certificate for $DOMAIN..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/${DOMAIN}.key \
        -out    /etc/ssl/certs/${DOMAIN}.crt \
        -subj   "/C=BD/ST=Chattogram/L=Chittagong/O=OS-Lab/OU=Student/CN=${DOMAIN}" \
        > /dev/null 2>&1
    chmod 600 /etc/ssl/private/${DOMAIN}.key
    print_ok "Certificate created: /etc/ssl/certs/${DOMAIN}.crt"
}

generate_cert "site1.local"
generate_cert "site2.local"


# ============================================================
# STEP 4 — Enable Sites & Reload Apache
# ============================================================
print_header "STEP 4: Enabling Virtual Hosts"

# Disable default site, enable ours
a2dissite 000-default.conf > /dev/null 2>&1
a2ensite site1.local.conf site2.local.conf > /dev/null 2>&1

# Test config before reloading
apache2ctl configtest 2>&1 | grep -E "Syntax|error"
systemctl reload apache2
print_ok "Apache reloaded. Both virtual hosts are live."

# Add to /etc/hosts so the names resolve locally
print_step "Adding site1.local and site2.local to /etc/hosts..."
if ! grep -q "site1.local" /etc/hosts; then
    echo "127.0.0.1   site1.local www.site1.local" >> /etc/hosts
fi
if ! grep -q "site2.local" /etc/hosts; then
    echo "127.0.0.1   site2.local www.site2.local" >> /etc/hosts
fi
print_ok "/etc/hosts updated."


# ============================================================
# STEP 5 — Firewall Setup (UFW)
# ============================================================
print_header "STEP 5: Firewall Configuration (UFW)"

print_step "Setting UFW default policies..."
ufw default deny incoming > /dev/null 2>&1
ufw default allow outgoing > /dev/null 2>&1
print_ok "Default: DENY incoming, ALLOW outgoing."

print_step "Allowing SSH (port 22)..."
ufw allow 22/tcp > /dev/null 2>&1
print_ok "SSH allowed."

print_step "Allowing HTTP (port 80)..."
ufw allow 80/tcp > /dev/null 2>&1
print_ok "HTTP (port 80) allowed."

print_step "Allowing HTTPS (port 443)..."
ufw allow 443/tcp > /dev/null 2>&1
print_ok "HTTPS (port 443) allowed."

print_step "Enabling UFW firewall..."
ufw --force enable > /dev/null 2>&1
print_ok "UFW enabled and active."

echo ""
echo -e "${BOLD}UFW Status:${NC}"
ufw status numbered


# ============================================================
# STEP 6 — Access Monitoring (Fail2Ban + Log Monitor Script)
# ============================================================
print_header "STEP 6: Access Monitoring"

# --- Fail2Ban: protect SSH and Apache ---
print_step "Configuring Fail2Ban (SSH + Apache protection)..."

cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime  = 600
findtime = 300
maxretry = 5
backend  = auto

# --- SSH Protection ---
[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s

# --- Apache: Too Many Requests ---
[apache-req]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/*access.log
maxretry = 300
findtime = 60
bantime  = 600

# --- Apache: Auth Brute Force ---
[apache-auth]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/*error.log
maxretry = 5
EOF

systemctl enable fail2ban > /dev/null 2>&1
systemctl restart fail2ban
print_ok "Fail2Ban configured and running."

# --- Log Monitor Script ---
print_step "Creating log monitor utility: /usr/local/bin/webmon"

cat > /usr/local/bin/webmon <<'MONEOF'
#!/bin/bash

# =====================================================
#  webmon — Web Server Access Monitor
#  Usage: webmon [option]
# =====================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════╗"
    echo "  ║     Web Server Monitor — webmon      ║"
    echo "  ╚══════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  ${BOLD}1.${NC} Live Apache access log (all sites)"
    echo -e "  ${BOLD}2.${NC} Last 20 access entries"
    echo -e "  ${BOLD}3.${NC} Top 10 IP addresses"
    echo -e "  ${BOLD}4.${NC} Top 10 requested pages"
    echo -e "  ${BOLD}5.${NC} HTTP 4xx/5xx errors today"
    echo -e "  ${BOLD}6.${NC} Fail2Ban banned IPs"
    echo -e "  ${BOLD}7.${NC} UFW firewall status"
    echo -e "  ${BOLD}8.${NC} Apache service status"
    echo -e "  ${BOLD}9.${NC} SSL certificate info (site1.local)"
    echo -e "  ${BOLD}0.${NC} Exit"
    echo ""
    echo -n "  Choose option: "
}

while true; do
    show_menu
    read -r choice
    echo ""
    case $choice in
        1)
            echo -e "${YELLOW}Live access log — press Ctrl+C to stop${NC}"
            tail -f /var/log/apache2/site1_access.log /var/log/apache2/site2_access.log 2>/dev/null
            ;;
        2)
            echo -e "${YELLOW}Last 20 access entries:${NC}"
            tail -n 20 /var/log/apache2/site1_access.log /var/log/apache2/site2_access.log 2>/dev/null
            ;;
        3)
            echo -e "${YELLOW}Top 10 IP addresses:${NC}"
            cat /var/log/apache2/*access.log 2>/dev/null | \
                awk '{print $1}' | sort | uniq -c | sort -rn | head -10
            ;;
        4)
            echo -e "${YELLOW}Top 10 requested pages:${NC}"
            cat /var/log/apache2/*access.log 2>/dev/null | \
                awk '{print $7}' | sort | uniq -c | sort -rn | head -10
            ;;
        5)
            echo -e "${YELLOW}HTTP 4xx/5xx errors:${NC}"
            grep -E '" [45][0-9]{2} ' /var/log/apache2/*access.log 2>/dev/null | tail -30
            ;;
        6)
            echo -e "${YELLOW}Fail2Ban banned IPs:${NC}"
            fail2ban-client status sshd 2>/dev/null
            fail2ban-client status apache-req 2>/dev/null
            fail2ban-client status apache-auth 2>/dev/null
            ;;
        7)
            echo -e "${YELLOW}UFW Firewall Status:${NC}"
            ufw status verbose
            ;;
        8)
            echo -e "${YELLOW}Apache Service Status:${NC}"
            systemctl status apache2 --no-pager
            ;;
        9)
            echo -e "${YELLOW}SSL Certificate Info (site1.local):${NC}"
            openssl x509 -in /etc/ssl/certs/site1.local.crt -noout \
                -subject -issuer -dates 2>/dev/null
            ;;
        0)
            echo "Goodbye."
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option.${NC}"
            ;;
    esac
    echo ""
    echo -n "  Press Enter to return to menu..."
    read -r
done
MONEOF

chmod +x /usr/local/bin/webmon
print_ok "Monitor utility installed. Run: sudo webmon"


# ============================================================
# FINAL SUMMARY
# ============================================================
print_header "SETUP COMPLETE — Summary"

SERVER_IP=$(hostname -I | awk '{print $1}')

echo -e "  ${BOLD}Server IP:${NC}         $SERVER_IP"
echo ""
echo -e "  ${BOLD}Virtual Hosts:${NC}"
echo -e "    ${GREEN}https://site1.local${NC}  →  /var/www/site1.local/html"
echo -e "    ${GREEN}https://site2.local${NC}  →  /var/www/site2.local/html"
echo ""
echo -e "  ${BOLD}HTTPS:${NC}             Self-signed SSL (365 days, RSA 2048)"
echo -e "  ${BOLD}Firewall (UFW):${NC}    Ports 22, 80, 443 open — all else blocked"
echo -e "  ${BOLD}Fail2Ban:${NC}          Active — SSH + Apache brute-force protection"
echo ""
echo -e "  ${BOLD}Log Files:${NC}"
echo -e "    /var/log/apache2/site1_access.log"
echo -e "    /var/log/apache2/site2_access.log"
echo -e "    /var/log/apache2/site1_error.log"
echo -e "    /var/log/apache2/site2_error.log"
echo ""
echo -e "  ${BOLD}Commands to know:${NC}"
echo -e "    ${CYAN}sudo webmon${NC}                    — interactive monitoring menu"
echo -e "    ${CYAN}sudo ufw status${NC}                — firewall rules"
echo -e "    ${CYAN}sudo fail2ban-client status${NC}    — banned IPs"
echo -e "    ${CYAN}sudo systemctl status apache2${NC}  — web server status"
echo -e "    ${CYAN}sudo apache2ctl -S${NC}             — virtual host list"
echo ""
echo -e "  ${YELLOW}NOTE:${NC} Browsers will warn about the self-signed cert."
echo -e "        Click 'Advanced > Proceed' to continue. This is expected"
echo -e "        in a lab environment (no CA-signed cert needed)."
echo ""
echo -e "${GREEN}${BOLD}  All done! Your hardened web server is ready.${NC}"
echo ""
