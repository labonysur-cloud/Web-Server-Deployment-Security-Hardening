#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  POST-OSLAB WAF FIX — Run this AFTER oslab.sh finishes          ║
# ║  Fixes: ModSecurity NOT loaded + Apache reload FAIL             ║
# ╚══════════════════════════════════════════════════════════════════╝
# USAGE:  sudo bash fix_after_oslab.sh

[[ $EUID -ne 0 ]] && { echo "Run as root: sudo bash fix_after_oslab.sh"; exit 1; }

G='\033[0;32m' R='\033[0;31m' C='\033[0;36m' B='\033[1m' NC='\033[0m'

echo ""
echo -e "${C}${B}  ╔══════════════════════════════════════════════════╗"
echo -e "  ║   Post-oslab.sh WAF Fix — OS Lab Group 1        ║"
echo -e "  ╚══════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${B}[1] Removing immutable flag on custom rules...${NC}"
chattr -i /etc/modsecurity/custom_rules/oslab_rules.conf 2>/dev/null
rm -f /etc/modsecurity/custom_rules/oslab_rules.conf
echo -e "    ${G}Done${NC}"

echo -e "${B}[2] Writing clean custom rules (no rule IDs)...${NC}"
mkdir -p /etc/modsecurity/custom_rules
cat > /etc/modsecurity/custom_rules/oslab_rules.conf << 'RULES'
SecAuditLog /var/log/apache2/modsecurity_audit.log
SecAuditLogParts ABCFHZ
SecAuditEngine RelevantOnly
RULES
echo -e "    ${G}Done${NC}"

echo -e "${B}[3] Restoring clean modsecurity.conf...${NC}"
cp /etc/modsecurity/modsecurity.conf-recommended /etc/modsecurity/modsecurity.conf
sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/modsecurity/modsecurity.conf
echo -e "    ${G}Done${NC}"

echo -e "${B}[4] Disabling OWASP CRS (stops ID conflicts)...${NC}"
a2disconf modsecurity-crs 2>/dev/null || true
echo -e "    ${G}Done${NC}"

echo -e "${B}[5] Enabling security2 module...${NC}"
a2enmod security2 >/dev/null 2>&1
echo -e "    ${G}Done${NC}"

echo -e "${B}[6] Ensuring audit log exists...${NC}"
touch /var/log/apache2/modsecurity_audit.log
chmod 644 /var/log/apache2/modsecurity_audit.log
echo -e "    ${G}Done${NC}"

echo -e "${B}[7] Testing Apache config...${NC}"
RESULT=$(apache2ctl configtest 2>&1)
if echo "$RESULT" | grep -q "Syntax OK"; then
  echo -e "    ${G}Syntax OK${NC}"
else
  echo -e "    ${R}Config error — details:${NC}"
  echo "$RESULT" | grep -v "^$" | head -8 | sed 's/^/    /'
  echo ""
  echo -e "    Trying to fix by disabling all extra confs..."
  a2disconf modsecurity-crs 2>/dev/null || true
  a2disconf security2 2>/dev/null || true
  RESULT2=$(apache2ctl configtest 2>&1)
  if echo "$RESULT2" | grep -q "Syntax OK"; then
    echo -e "    ${G}Fixed! Syntax OK now${NC}"
  else
    echo -e "    ${R}Still failing:${NC}"
    echo "$RESULT2" | head -5 | sed 's/^/    /'
  fi
fi

echo -e "${B}[8] Restarting Apache...${NC}"
systemctl restart apache2 >/dev/null 2>&1
sleep 2

echo ""
echo "════════════════════════════════════════════════"
echo -e "${B}  Final Verification${NC}"
echo "════════════════════════════════════════════════"

# Apache
if systemctl is-active apache2 >/dev/null 2>&1; then
  echo -e "  ${G}${B}[PASS]${NC} Apache2 is running"
else
  echo -e "  ${R}${B}[FAIL]${NC} Apache2 NOT running"
fi

# WAF
if apache2ctl -M 2>/dev/null | grep -q security2; then
  echo -e "  ${G}${B}[PASS]${NC} ModSecurity WAF loaded"
else
  echo -e "  ${R}${B}[FAIL]${NC} ModSecurity NOT loaded"
fi

# Syntax
if apache2ctl configtest 2>&1 | grep -q "Syntax OK"; then
  echo -e "  ${G}${B}[PASS]${NC} Apache config Syntax OK"
else
  echo -e "  ${R}${B}[FAIL]${NC} Config syntax error"
  apache2ctl configtest 2>&1 | head -5 | sed 's/^/         /'
fi

echo "════════════════════════════════════════════════"
echo ""
echo -e "${C}All done! Your project is now fully deployed.${NC}"
echo ""
