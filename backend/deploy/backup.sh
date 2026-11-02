#!/usr/bin/env bash
set -euo pipefail
myleafy_environment=${1:?staging or production}
myleafy_backup_lock_mode=${2:-}
[[ "$myleafy_environment" == staging || "$myleafy_environment" == production ]]
if [[ "${2:-}" != --lock-held ]]; then exec 9>"/run/lock/myleafy-${myleafy_environment}.lock"; fi
flock -n 9
myleafy_service="myleafy@${myleafy_environment}"
myleafy_running=false
if systemctl is-active --quiet "$myleafy_service"; then myleafy_running=true; fi
monitor_event() {
  if [[ -f "/etc/myleafy/${myleafy_environment}.monitor.env" ]]; then
    /usr/local/bin/node "/opt/myleafy/${myleafy_environment}/current/backend/deploy/monitor-maintenance.mjs" "$myleafy_environment" "$1"
  fi
}
monitor_event begin
# A brief scheduled stop ensures DB, file cleanup, and uploads form one snapshot.
restore_service() {
  myleafy_result=$?
  if [[ "$myleafy_running" == true ]]; then systemctl start "$myleafy_service"; fi
  if [[ "$myleafy_result" == 0 ]]; then monitor_event backup-success; else monitor_event backup-failed; fi
  if [[ "$myleafy_backup_lock_mode" != --lock-held ]]; then monitor_event end; fi
}
trap restore_service EXIT
systemctl stop "$myleafy_service"
cd "/opt/myleafy/${myleafy_environment}/current/backend"
/usr/local/bin/node --env-file="/etc/myleafy/${myleafy_environment}.backup.env" scripts/ecs/local-backup.mjs "/var/lib/myleafy/${myleafy_environment}" "/var/backups/myleafy/${myleafy_environment}" "/etc/myleafy/${myleafy_environment}.env" "$myleafy_environment"
