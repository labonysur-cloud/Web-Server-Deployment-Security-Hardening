# OS Lab Complete Project Analysis
*Deep-dive Architectural and Line-by-Line Breakdown*

This report analyzes the entirely custom-built **OS Lab Web Server Deployment Script** and its accompanying test files (`test_shop.html` and `test_dark_theme.html`). This project represents a robust, fully automated Ubuntu Server provisioning system combining Apache Virtual Hosting, a handcrafted GUI Control Panel, and enterprise-grade security hardening.

---

## 🏗️ 1. Global Architecture Summary

The complete ecosystem is built from a single monolithic bash script (`oslab_project (1).sh`), which acts as an orchestrator. Upon running `sudo bash oslab_project.sh`, the script:
1. Installs core dependencies (`apache2`, `ufw`, `fail2ban`, `modsecurity-crs`, `php`).
2. Configures Apache modules and file directory structures.
3. Automatically generates RSA-2048 Self-Signed Certificates.
4. Generates and writes raw HTML and PHP logic to disk directly from Bash *heredocs*.
5. Hardens the OS network with UFW and the Web Application Layer with ModSecurity and Fail2Ban.
6. Installs a suite of custom CLI tooling and fully functional REST APIs for the interactive Control Panel.

---

## 🔬 2. Line-by-Line Bash Script Breakdown

The deployment script spans approximately 2500 lines and is deliberately divided into 9 phases plus a Control Panel phase.

### Phase 1–3: Dependencies, Modules & Structure (Lines 1 - 143)
- **Lines 1-60**: Guard checks to ensure the user is `root`. It initializes CLI colored outputs using terminal escape codes. It uses `openssl rand` to dynamically generate a secure 16-character base64 password for the admin account, writing it to `/root/.oslab_admin_password` securely (`chmod 600`).
- **Lines 61-100**: Triggers `apt-get` to install the `LAMP`-equivalent stack. Note the inclusion of `libapache2-mod-security2` (WAF) and `modsecurity-crs` (OWASP Core Rules). It uses `sed` to edit `php.ini` dynamically, pumping `upload_max_filesize` to 64MB and re-enabling `shell_exec` and `exec` which are crucial for the Control Panel's ability to run Bash commands from PHP.
- **Lines 101-143**: Systematically creates directories for 5 isolated environments: `site1.local`, `site2.local`, `status.local`, `admin.local`, and `panel.local`. `chown -R www-data:www-data /var/www/` ensures Apache owns the web root.

### Phase 4–5: Certificates & Base Websites (Lines 144 - 571)
- **Lines 144-165**: A loop calling `openssl req -x509` to forge self-signed SAN certificates for all `.local` domains, valid for 365 days.
- **Lines 166-335**: Writes `site1.local/html/index.html` (a beautifully styled team portfolio using CSS Grid and Instrument Serif) and `site2.local/html/index.html` (the OS Lab Project Documentation) natively using bash string redirection (`cat > file << EOF`).
- **Lines 337-432**: Crafts `status.local/html/index.php`. This is a programmatic telemetry dashboard. It invokes PHP's `shell_exec('free -m')`, disk space calculators, and Apache Access Logs parser to visually display system health using modern web styling.
- **Lines 475-548**: Writes `site1.local/waf-test/index.html`. This is a frontend Javascript application utilizing the `fetch` API to actively fire payloads like `UNION SELECT`, `<script>XSS`, and Directory Traversals (`../../../etc/passwd`) against the server. It listens for HTTP 403 Forbidden responses to prove the WAF is functioning.

### Phase 6: Core LAN & Virtual Hosting (Lines 572 - 774)
- **Lines 577-638**: The `write_vhost` function writes actual Apache `<VirtualHost *:80>` and `<VirtualHost *:443>` blocks. It automatically inserts HTTPS Redirect rules, strict security headers (e.g. `X-Frame-Options SAMEORIGIN`, `X-XSS-Protection "1; mode=block"`), and implements `.htpasswd` basic authorization via `AuthType Basic` if requested.
- **Lines 639-761**: Generates the **LAN Gateway Portal**. The script dynamically identifies the server's LAN IP. By accessing `http://<SERVER_IP>/`, devices across the network hit a PHP script (`000-portal.conf`) that parses `/var/www/*/html` and dynamically generates a clickable index card for every hosted website utilizing `AliasMatch`.

### Phase 7–8: Firewall, Fail2Ban & WAF (Lines 775 - 997)
- **Lines 778-792**: Triggers `ufw default deny incoming`, opening only 22 (SSH), 80 (HTTP), and 443 (HTTPS).
- **Lines 793-834**: The script edits `/etc/fail2ban/jail.local` configuring 3 primary jails:
  - `sshd`: Bans users failing SSH passwords.
  - `apache-auth`: Bans IPs failing to guess `.htpasswd` credentials.
  - `apache-req`: A custom jail built alongside `/etc/fail2ban/filter.d/apache-req.conf` to ban IPs firing too many requests per minute to Apache.
- **Lines 835-997 (Critical Security)**: Configures ModSecurity WAF. Rather than relying purely on the heavy OWASP CRS (which it includes), it crafts specific `SecRule` patterns in `/etc/modsecurity/custom_rules/oslab_rules.conf`. Phase 1 rules intercept URIs. Phase 2 rules parse POST/GET body `ARGS` looking for `@rx (union|select|drop|...)` returning a hard HTTP 403 block.

### Phase 9: CLI Automation (Lines 998 - 1194)
- **Lines 1003-1121**: Writes `/usr/local/bin/webmon`, an interactive Bash program mapping options (1-9) to standard monitoring commands (like `tail -f *access.log` and `ufw status`).
- **Lines 1122-1194**: Configures automated Cron Jobs via `/usr/local/bin/backup_logs.sh` (tars and zips apache logs daily at midnight) and `daily_report.sh` (compiles a daily overview text file at 6 AM).

### Phase 10: The Interactive Control Panel (Lines 1195 - 2400)
- **Lines 1201-1225**: Elevates the `www-data` account via `/etc/sudoers.d/panel-www-data`, granting exactly the minimum permissions required to restart Apache, query UFW, ban IPs, and run `a2ensite` WITHOUT needing a password prompt.
- **Lines 1262-1419**: Spawns `panel.local/html/index.php`. It employs a stateful PHP session mechanism overriding access via the securely generated `$ADMIN_PASS`.
- **CSS / JS Implementation**: Features a sleek, component-based dark/light mode toggleable interface (`[data-dark] { ... }`). The JS utilizes async API calls heavily `fetch('api.php')` for smooth, single-page application rendering.
- **SSE Stream (`monitor/stream.php` -> Lines 2252-2346):** This is highly advanced. Server-Sent Events open a permanent streaming connection to the client. The PHP script loops endlessly (`while(!connection_aborted())`), actively tracking the byte `filesize()` of `/var/log/apache2/modsecurity_audit.log`. When the size grows, it reads the new lines, parses them against a regex map to determine attack type (e.g., `SQL Injection`, `Null Byte`), and pushes the event instantly back to the dashboard.
- **The API System (`api.php` -> Lines 2016-2247):** A custom backend switch statement implementing an MVC model. Highlights include:
  - `case 'deploy'`: An API that accepts Domain, Title, HTML content in POST form data; creates directories, dynamically writes the SSL and Apache Config, tests syntax via `apache2ctl configtest`, and hard-reloads the daemon programmatically.
  - `case 'ban' / 'unban'`: Executes `fail2ban-client set [jail] banip [IP]` behind the scenes.
  - `case 'disable' / 'enable'`: Swaps `.htaccess` files to block access, and uses `a2dissite` programmatically to turn sites offline.

---

## 📂 3. Supplementary HTML Testing Files

The repository additionally contains two test artifacts meant to validate the Control Panel's Automated Website Deployment Engine.

### `test_shop.html`
- **Purpose**: Mimics a fully functional layout for an E-Commerce store selling physical items to prove static CSS compilation and flexbox behaviors deploy correctly without breakage.
- **Implementation**: Uses extensive internal styling `<style>` to render hover-animated `.card` elements for products named 'OS Lab Merch', 'Firewall Book', and 'WAF Token'. Its content structure is specifically designed to prove that the automatic alias matching logic in `000-portal.conf` flawlessly routes `<img src="...">` and `<a href="">` payload routing.

### `test_dark_theme.html`
- **Purpose**: Serves as a stylistic visual test, meant specifically for users testing the E2E E-Commerce Engine by physically "Dragging and Dropping" this file into the `panel.local` website deployment wizard.
- **Implementation**: Written using a specialized cyber-dark aesthetic (`background-color: #0f172a;`, `text-shadow: 0 0 10px rgba...`). Contains an explicit badge confirming `"TEST ENVIRONMENT"`. The text literally acknowledges that if it displays, the underlying `upload_tmp_dir` logic and `sudo cp` filesystem relocations executed by `www-data` succeeded flawlessly.

---

## 🎯 Architectural Assessment & Highlights 

1. **Extreme Robustness in Automation**: Creating OpenSSL certificates strictly using silent CLI flags and formatting Apache VirtualHosts via bash heredocs eliminates thousands of hours of manual labor usually required in Systems Administration classes.
2. **Real-time Event Architecture**: Utilizing PHP as a buffer-less stream (`header('X-Accel-Buffering: no')`) to parse and transport WAF logs natively bridges the divide between backend C/C++ engine auditing (`ModSecurity`) and intuitive frontend Web GUI interfaces. 
3. **Impenetrable Security Segregation**: By decoupling API privileges into a discrete `sudoers` whitelist, the overarching operating system ensures that even if the PHP Control Panel were compromised, hackers strictly cannot leverage it to execute arbitrary malicious bounds beyond the scope defined.
