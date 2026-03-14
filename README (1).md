# Web Server Deployment & Security Hardening
## OS Lab Project — VirtualBox + Ubuntu Linux

---

## What This Script Does

| Feature | Tool Used | Details |
|---|---|---|
| Web Server | Apache2 | Installed and auto-started |
| Virtual Hosting | Apache VirtualHosts | site1.local + site2.local |
| HTTPS | OpenSSL (self-signed) | RSA 2048, 365-day cert |
| Firewall | UFW | Allow 22, 80, 443 only |
| Intrusion Protection | Fail2Ban | SSH + Apache brute-force |
| Access Monitoring | Custom `webmon` tool | Logs, top IPs, banned IPs |

---

## How to Run (Inside Ubuntu VirtualBox)

### Step 1 — Open Terminal in Ubuntu
Press `Ctrl + Alt + T`

### Step 2 — Copy the script file
If you transfer the file via shared folder or USB, place it anywhere.
Or create it directly:
```bash
nano webserver_setup.sh
# paste the script content, then Ctrl+O, Enter, Ctrl+X
```

### Step 3 — Make it executable
```bash
chmod +x webserver_setup.sh
```

### Step 4 — Run with root privileges
```bash
sudo bash webserver_setup.sh
```

Wait for it to finish. It will print each step with [OK] confirmations.

---

## After Setup — How to Test Everything

### Test Virtual Hosts (open Firefox inside Ubuntu)
- Go to: `https://site1.local`
- Go to: `https://site2.local`
- Browser will warn about self-signed cert → click **Advanced → Accept the Risk**

### Test from Terminal
```bash
# Check both sites respond
curl -k https://site1.local
curl -k https://site2.local

# List all active virtual hosts
sudo apache2ctl -S
```

### Test Firewall
```bash
sudo ufw status numbered
# Should show: 22/tcp, 80/tcp, 443/tcp allowed
```

### Open the Monitoring Tool
```bash
sudo webmon
```
This opens an interactive menu with 9 options:
- Live log streaming
- Top IP addresses
- Error tracking
- Fail2Ban banned IPs
- SSL certificate details
- And more

---

## File Locations After Setup

```
/var/www/
  site1.local/html/index.html     ← Site 1 webpage
  site2.local/html/index.html     ← Site 2 webpage

/etc/apache2/sites-available/
  site1.local.conf                ← Virtual host config
  site2.local.conf

/etc/ssl/certs/
  site1.local.crt                 ← SSL certificate
  site2.local.crt

/etc/ssl/private/
  site1.local.key                 ← Private key (chmod 600)
  site2.local.key

/var/log/apache2/
  site1_access.log                ← Access logs
  site2_access.log
  site1_error.log
  site2_error.log

/etc/fail2ban/jail.local          ← Fail2Ban rules
/usr/local/bin/webmon             ← Monitoring utility
```

---

## OS Concepts Demonstrated

| Concept | Where |
|---|---|
| Process management | `systemctl` for Apache, Fail2Ban |
| File permissions | `chmod 600` on private keys, `chmod 755` on web root |
| Networking | UFW firewall rules, port management |
| OS security | Fail2Ban, security headers, HTTP→HTTPS redirect |
| Log management | Apache logs, Fail2Ban logs |
| Shell scripting | Full Bash automation, functions, conditionals |

---

## Troubleshooting

**Apache won't start:**
```bash
sudo apache2ctl configtest
sudo journalctl -xe | grep apache
```

**Site not loading:**
```bash
cat /etc/hosts        # check site1.local entry exists
sudo systemctl status apache2
```

**Port blocked:**
```bash
sudo ufw status       # verify ports 80, 443 are allowed
```

**Fail2Ban not running:**
```bash
sudo systemctl status fail2ban
sudo fail2ban-client ping
```
