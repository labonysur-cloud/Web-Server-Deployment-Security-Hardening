# 🛡️ OS Lab Complete Web Hosting & Hardening Project

## 📌 Project Overview
This project is an automated Bash deployment script created for an Operating Systems Lab course. It provisions an Ubuntu Server from total scratch into a secure, production-ready Web Hosting Platform. It configures Apache, PHP, automatic SSL, and heavily fortifies the system using Linux OS-level firewalls (UFW), Intrusion Bans (Fail2Ban), and a robust Web Application Firewall (ModSecurity).

The crown jewel of this project is the **Custom Control Panel**, an interactive graphical interface allowing real-time deployment of new websites and live monitoring of hacking attempts against the server.

---

## 🚀 How to Run the Project
1. Open up your fresh Ubuntu Virtual Machine.
2. Ensure you have the `oslab_project.sh` script copied into your Ubuntu VM (e.g. `Desktop/oslab_project.sh`).
3. Open your Ubuntu Terminal and execute:
   ```bash
   sudo bash oslab_project.sh
   ```
4. Wait 1 or 2 minutes for the automated setup to complete. 

---

## 🔐 Accounts & Passwords
Every time you run the script, a completely secure, random password is dynamically generated for you.

*   **Username:** `admin`
*   **Where to find your Password:** Open your terminal and type:
    ```bash
    sudo cat /root/.oslab_admin_password
    ```

You will use these exact credentials to log into the Control Panel and the Protected Admin backend pages.

---

## 🌐 Deployed Websites (The Network)
By default, the script orchestrates 5 unique local domains which are immediately accessible from the Ubuntu Web Browser (Firefox):

1. **`https://site1.local`** — A Team Portfolio page showing the creators.
   * Includes **`https://site1.local/waf-test/`** — An interactive console with 11 buttons to throw real hacking payloads against the server!
2. **`https://site2.local`** — A basic informational project site.
3. **`https://status.local`** — A real-time PHP dashboard reporting total RAM usage, CPU load, and Apache uptime.
4. **`https://admin.local`** — A strictly password-protected backend to demonstrate Apache `.htpasswd` basic authorization.
5. **`https://panel.local`** — The Interactive Control Panel. (See features below).

*(Note: Because the SSL certificates are proudly "Self-Signed" by your own script, the browser will warn you the connection is not private. Just click Advanced -> Accept Risk to proceed).*

---

## 🎛️ Control Panel Features (`panel.local`)
The dashboard is an interactive frontend running as `www-data` utilizing custom *sudoers* rules to safely administer the Linux OS:

*   **Real-time Attack Monitor:** Uses HTML5 Server-Sent Events (SSE) to live-tail the ModSecurity WAF logs. If a hacker attacks, their blocked payload instantly types out on the screen in real time.
*   **Automated Website Deployment:** Upload an HTML file, type a domain name (like `demo.local`), check "Enable SSL", and the dashboard will configure a new Virtual Host, reload Apache, and put the site online instantly!
*   **Firewall IP Banning:** Read the top 10 IP addresses connecting to your Apache server and use Fail2Ban logic to manually Ban IP addresses directly from the web browser.
*   **Site Toggling:** Click "Disable" next to any deployed site in the "All Sites" tab to immediately drop it offline using `a2dissite`.

---

## 🛡️ Security Layers Analyzed
1. **Network Layer (UFW):** Firewall defaults to Deny All inbound, exclusively whitelisting ports `22` (SSH), `80` (HTTP), and `443` (HTTPS).
2. **Intrusion Prevention (Fail2Ban):** Protects SSH and Apache. If a user tries to bruteforce passwords 5 times, or spams requests abnormally fast (`mod_evasive`), their IP is firewalled out for 10 minutes at the OS/Firewall level.
3. **Web Application Firewall (ModSecurity):** Enforces 4 strict custom OWASP-style rules that scan every query string to instantly terminate and log SQL Injections, Cross-Site Scripting (XSS), Path Traversals, and Null Bytes safely without crashing memory limits.

---

## 💻 Included CLI Tools
If you want to view telemetry like a true System Administrator without using the Web Dashboard, the script builds a custom Terminal tool! Simply type:

```bash
sudo webmon
```
This opens a beautifully colored, interactive shell menu inside your terminal to tail live access logs, WAF errors, and system status!
