#!/usr/bin/env bash
set -euo pipefail
[[ $(id -u) == 0 ]]
# Installs dedicated runtime tools; does not start any public listener.
for myleafy_path in /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/caddy /etc/myleafy/Caddyfile /etc/systemd/system/myleafy-caddy.service; do
  if [[ -e "$myleafy_path" ]]; then echo "Refusing to overwrite existing $myleafy_path" >&2; exit 1; fi
done
myleafy_temp=$(mktemp -d)
trap 'rm -rf "$myleafy_temp"' EXIT
cd "$myleafy_temp"
curl -fSL --connect-timeout 15 --max-time 600 --retry 3 -o node.tar.xz https://nodejs.org/dist/v24.22.1/node-v24.22.1-linux-x64.tar.xz
curl -fsSL --connect-timeout 15 --max-time 600 --retry 3 -o SHASUMS256.txt https://nodejs.org/dist/v24.22.1/SHASUMS256.txt
myleafy_node_sha=$(awk '$2=="node-v24.22.1-linux-x64.tar.xz" {print $1}' SHASUMS256.txt)
[[ "$myleafy_node_sha" =~ ^[a-f0-9]{64}$ ]]
echo "$myleafy_node_sha  node.tar.xz" | sha256sum --check
curl -fSL --connect-timeout 15 --max-time 600 --retry 3 -o caddy.tar.gz https://github.com/caddyserver/caddy/releases/download/v2.11.7/caddy_2.11.7_linux_amd64.tar.gz
curl -fsSL --connect-timeout 15 --max-time 600 --retry 3 -o caddy-checksums.txt https://github.com/caddyserver/caddy/releases/download/v2.11.7/caddy_2.11.7_checksums.txt
myleafy_caddy_sha=$(awk '$2=="caddy_2.11.7_linux_amd64.tar.gz" {print $1}' caddy-checksums.txt)
[[ "$myleafy_caddy_sha" =~ ^[a-f0-9]{128}$ ]]
echo "$myleafy_caddy_sha  caddy.tar.gz" | sha512sum --check
install -d -m 755 /opt/myleafy/toolchain
[[ ! -e /opt/myleafy/toolchain/node-v24.22.1-linux-x64 ]]
tar -xJf node.tar.xz -C /opt/myleafy/toolchain
ln -s /opt/myleafy/toolchain/node-v24.22.1-linux-x64/bin/node /usr/local/bin/node
ln -s /opt/myleafy/toolchain/node-v24.22.1-linux-x64/bin/npm /usr/local/bin/npm
tar -xzf caddy.tar.gz caddy
install -m 755 caddy /usr/local/bin/caddy
id myleafy >/dev/null 2>&1 || useradd --system --home-dir /var/lib/myleafy --shell /usr/sbin/nologin myleafy
id caddy >/dev/null 2>&1 || useradd --system --home-dir /var/lib/caddy --shell /usr/sbin/nologin caddy
install -d -m 755 /etc/myleafy
install -d -m 755 /opt/myleafy/staging/releases /opt/myleafy/production/releases
install -d -m 700 -o myleafy -g myleafy /var/lib/myleafy/staging /var/lib/myleafy/production
install -d -m 700 -o caddy -g caddy /var/lib/caddy
install -d -m 700 /var/backups/myleafy/staging /var/backups/myleafy/production
/usr/local/bin/node --version
/usr/local/bin/caddy version
