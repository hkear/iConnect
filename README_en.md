# README\_EN\.md

\# iConnect — Cross\-Site Intranet Networking System

A pure centralized relay\-based virtual LAN tool for cross\-site networking\. All device traffic is relayed through the Core server without P2P hole punching, adapting to multi\-layer NAT, weak network, and port\-blocked environments\.

## Architecture

```Plain Text
Core Server (Public IP, Single TCP Port)
   │
   ├── Client A (OpenWrt Router, Remote Intranet)
   ├── Client B (Linux Server, Remote Intranet)
   └── Client C (OpenWrt Router, Remote Intranet)

Traffic Rule: Client A → Core → Client B, direct connections between clients are prohibited

```

## Installation Guide

### 1\. Server \& Web Dashboard \(x86\_64\)

**Compatibility**: Ubuntu 20\.04\+ / Debian 11\+, servers with public IP

**Firewall Requirements**: Open TCP port 1993 \(Networking\) and 1994 \(Web Panel\)

```Plain Text
# 1. Download and extract the server installation package
tar xzf iconnect-server-v1.1.1.tar.gz

# 2. Interactive installation (customizable network name, secret key and port)
sudo bash install.sh

# 3. The service starts automatically after installation and outputs connection information

```

**Post\-installation Services**

|Service|Port|systemd Command|
|---|---|---|
|iconnectd \(Core\)|1993|`systemctl start/stop iconnectd`|
|iconnect\-web|1996 \(Internal\)|`systemctl start/stop iconnect-web`|
|iconnect\-proxy|1994 \(Frontend\)|`systemctl start/stop iconnect-proxy`|

**Web Dashboard Access**

```Plain Text
URL: http://ServerIP:1994
Username: admin
Password: admin888

```

Please change the default password after your first login\. User registration is disabled\. Run the following command to reset password:`python3 /opt/iconnect/reset-pwd.py`\.

**Manual Web Deployment \(If not included in install\.sh\)**

```Plain Text
# Upload proxy.py and reset-pwd.py to /opt/iconnect/
# Install Python dependencies
pip3 install argon2-cffi --break-system-packages

# Create systemd service file
cat > /etc/systemd/system/iconnect-proxy.service << 'EOF'
[Unit]
Description=iConnect Web Proxy
After=network.target iconnect-web.service
[Service]
Type=simple
ExecStart=python3 /opt/iconnect/proxy.py 1994
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now iconnect-proxy

```

### 2\. x86\_64 Client \(Linux Server / Virtual Machine\)

```Plain Text
# 1. Download and extract the client installation package
tar xzf iconnect-client-v1.1.1-x86_64.tar.gz

# 2. Non-interactive command line installation
sudo bash install.sh ServerIP 1993 NetworkName NetworkKey

# Or interactive installation
sudo bash install.sh

```

Manage client service via `systemctl start/stop iconnectd`\. Virtual IP is automatically assigned by built\-in DHCP\.

### 3\. aarch64 Client \(OpenWrt Router\)

Execute all commands on your OpenWrt device

```Plain Text
# 1. Download and extract the client installation package
tar xzf iconnect-client-v1.1.1-aarch64.tar.gz

# 2. Command line installation
sh install.sh ServerIP 1993 NetworkName NetworkKey

# Or interactive installation
sh install.sh

```

Manage client service via `/etc/init.d/iconnect start/stop`\.

### 4\. Firewall Configuration

|Port|Protocol|Direction|Description|
|---|---|---|---|
|1993|TCP|Inbound|Core network service for client connection|
|1994|TCP|Inbound|Web management panel|

```Plain Text
# UFW Firewall
sudo ufw allow 1993/tcp
sudo ufw allow 1994/tcp

# firewalld
sudo firewall-cmd --add-port=1993/tcp --permanent
sudo firewall-cmd --add-port=1994/tcp --permanent
sudo firewall-cmd --reload

```

## Web Dashboard

```Plain Text
URL: http://ServerIP:1994
Username: admin
Password: admin888

```

- Change the default password immediately after first login

- User registration is closed, only admin accounts are allowed

- To reset password, execute via SSH: `python3 /opt/iconnect/reset-pwd.py`

## Port Description

|Port|Service|Description|
|---|---|---|
|1993|Core Network|Client connection port|
|1994|Web Frontend|Management panel port|

## Directory Structure

```Plain Text
iconnect/
├── README.md
├── deploy/                  # Deployment scripts and configurations
│   ├── install-server.sh     # One-click server installation script
│   ├── install-client.sh     # One-click client installation script
│   ├── build-all.sh          # Source build script
│   ├── proxy.py              # Web proxy (device data injection)
│   ├── reset-pwd.py          # Password reset script
│   └── iconnect.db           # Database template
├── dist/packages/            # Compiled installation packages
├── iconnectd/                # Core source code (Rust)
└── iconnect-web/             # Web dashboard source code (Rust + Vue)

```

## Core Features

- **Pure Centralized Relay**: 100% of traffic relayed via Core server, no P2P transmission

- **Single Port Operation**: Only one TCP port \(1993\) needs to be opened

- **Weak Network Compatibility**: No NAT hole punching required, supports multi\-layer route penetration

- **Automatic DHCP IP Allocation**: Virtual IP assigned automatically once clients connect

- **Cross\-Platform**: Supports Linux x86\_64 / OpenWrt aarch64

- **Web Dashboard**: Displays device quantity and online status list

- **Real Device Data Injection**: Web panel synchronizes real CLI peer list data

- **Lightweight**: Adaptable to low\-spec OpenWrt routers

## Platform Support

|Platform|Architecture|Support Status|
|---|---|---|
|Ubuntu / Debian|x86\_64|Server \+ Client|
|OpenWrt|aarch64|Client Only|
|Other Linux|x86\_64|Client Only|

## Management Commands

```Plain Text
# Service management
systemctl start/stop/status iconnectd
systemctl start/stop/status iconnect-web

# View logs
journalctl -u iconnectd -f
tail -f /var/log/iconnectd.log

# Reset password
python3 /opt/iconnect/reset-pwd.py

# Device status query
iconnect-cli peer list
iconnect-cli route list

```

## Documentation

- [CLI Command Manual](https://www.doubao.cn)

- [Web Dashboard Manual](https://www.doubao.cn)

## License

Secondary development based on EasyTier v2\.6\.4, inheriting the upstream MPL\-2\.0 license\.


