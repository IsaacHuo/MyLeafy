#!/usr/bin/env bash
set -euo pipefail
[[ $(id -u) == 0 ]]
cd "$(dirname "$0")"
id myleafy-monitor >/dev/null 2>&1 || useradd --system --home-dir /var/lib/myleafy-monitor --shell /usr/sbin/nologin myleafy-monitor
install -d -m 710 -o caddy -g caddy /var/lib/caddy
install -d -m 755 /var/lib/myleafy-monitor /var/lib/caddy/myleafy-access /run/myleafy-monitor
install -d -m 755 /var/lib/myleafy-monitor/backup
install -d -m 700 -o myleafy-monitor -g myleafy-monitor /var/lib/myleafy-monitor/prometheus
for myleafy_environment in production staging; do
  install -d -m 700 -o myleafy-monitor -g myleafy-monitor "/var/lib/myleafy-monitor/$myleafy_environment"
  install -d -m 750 -o caddy -g caddy "/var/lib/caddy/myleafy-access/$myleafy_environment"
  find "/var/lib/caddy/myleafy-access/$myleafy_environment" -maxdepth 1 -type f -name 'access*.log' -exec chown caddy:caddy {} +
done
myleafy_temp=$(mktemp -d)
trap 'rm -rf "$myleafy_temp"' EXIT
install_binary() {
  local myleafy_name=$1 myleafy_version=$2 myleafy_sha=$3 myleafy_binary=$4
  if [[ -x "/usr/local/bin/myleafy-$myleafy_binary" ]]; then
    "/usr/local/bin/myleafy-$myleafy_binary" --version 2>&1 | grep -F "$myleafy_version" >/dev/null
    return
  fi
  local myleafy_archive="$myleafy_name-$myleafy_version.linux-amd64.tar.gz"
  curl -fSL --connect-timeout 15 --max-time 600 --retry 3 -o "$myleafy_temp/$myleafy_archive" "https://github.com/prometheus/$myleafy_name/releases/download/v$myleafy_version/$myleafy_archive"
  echo "$myleafy_sha  $myleafy_temp/$myleafy_archive" | sha256sum --check
  tar -xzf "$myleafy_temp/$myleafy_archive" -C "$myleafy_temp" "$myleafy_name-$myleafy_version.linux-amd64/$myleafy_binary"
  install -m 755 "$myleafy_temp/$myleafy_name-$myleafy_version.linux-amd64/$myleafy_binary" "/usr/local/bin/myleafy-$myleafy_binary"
}
install_binary prometheus 3.15.1 6a726885328ad9efebbf36e876ce2fb6225468a71fd1e7ce3ba666d5f4d97a84 prometheus
install_binary node_exporter 1.12.1 b51d8a76aa2a9156a55d501aca6276fae09e262259a5e4e831d2c2222f084e63 node_exporter
install -m 644 prometheus.yml /etc/myleafy/prometheus.yml
install -m 644 Caddyfile.monitoring-routes /etc/myleafy/Caddyfile.monitoring-routes
install -m 644 myleafy-prometheus.service myleafy-node-exporter.service myleafy-monitor@.service myleafy-monitor-report@.service myleafy-monitor-report@.timer /etc/systemd/system/
install -m 644 myleafy-monitor.tmpfiles.conf /etc/tmpfiles.d/myleafy-monitor.conf
systemd-tmpfiles --create /etc/tmpfiles.d/myleafy-monitor.conf
for myleafy_environment in production staging; do
  /usr/local/bin/node --input-type=module - "$myleafy_environment" <<'JS'
import {readFileSync,writeFileSync,existsSync,readdirSync,statSync} from 'node:fs';
import {randomBytes} from 'node:crypto';
const environment=process.argv[2],file=`/etc/myleafy/${environment}.env`,monitorFile=`/etc/myleafy/${environment}.monitor.env`;
process.loadEnvFile(file);
let token=process.env.MONITOR_TOKEN;
if(!token){token=randomBytes(32).toString('hex');writeFileSync(file,readFileSync(file,'utf8')+'\nMONITOR_TOKEN='+JSON.stringify(token)+'\n',{mode:0o600});}
if(existsSync(monitorFile)){
  const original=process.env.MONITOR_TOKEN;delete process.env.MONITOR_TOKEN;process.loadEnvFile(monitorFile);
  if(process.env.MONITOR_TOKEN!==original)throw new Error('Existing monitor token mismatch; refusing to replace configuration');
}else {
  const values={ENVIRONMENT:environment,MONITOR_DIRECTORY:`/var/lib/myleafy-monitor/${environment}`,MONITOR_TOKEN:token,MONITOR_EMAIL_ENABLED:'false',MONITOR_EMAIL_DAILY_LIMIT:'10',MONITOR_EMAIL_TO:process.env.MONITOR_EMAIL_TO??'',EMAIL_API_KEY:process.env.EMAIL_API_KEY??'',EMAIL_FROM:process.env.EMAIL_FROM??''};
  writeFileSync(monitorFile,Object.entries(values).map(([key,value])=>key+'='+JSON.stringify(value)).join('\n')+'\n',{mode:0o600,flag:'wx'});
}
const backupState=`/var/lib/myleafy-monitor/backup/${environment}.json`;
if(!existsSync(backupState)){
  const root=`/var/backups/myleafy/${environment}`,archives=existsSync(root)?readdirSync(root).filter(name=>name.endsWith('.tar')&&existsSync(root+'/'+name+'.sha256')):[];
  const successAt=archives.length?Math.max(...archives.map(name=>statSync(root+'/'+name+'.sha256').mtimeMs)):null;
  writeFileSync(backupState,JSON.stringify({successAt,failed:false})+'\n',{mode:0o600,flag:'wx'});
}
console.log(JSON.stringify({environment,monitorConfigured:true,emailEnabled:false,credentialsPrinted:false}));
JS
  chown root:myleafy-monitor "/var/lib/myleafy-monitor/backup/$myleafy_environment.json"
  chmod 640 "/var/lib/myleafy-monitor/backup/$myleafy_environment.json"
done
systemctl daemon-reload
systemctl enable --now myleafy-prometheus.service myleafy-node-exporter.service
echo 'Monitoring tools installed. Start each monitor only after deploying its matching runtime. Mail remains disabled until acceptance.'
