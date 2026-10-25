#!/usr/bin/env bash
set -euo pipefail
myleafy_environment=${1:?staging or production}
[[ "$myleafy_environment" == staging || "$myleafy_environment" == production ]]
if [[ "${2:-}" != --lock-held ]]; then exec 9>"/run/lock/myleafy-${myleafy_environment}.lock"; fi
flock -n 9
myleafy_service="myleafy@${myleafy_environment}"
myleafy_running=false
if systemctl is-active --quiet "$myleafy_service"; then myleafy_running=true; fi
# A brief scheduled stop ensures DB, file cleanup, and uploads form one snapshot.
restore_service() { if [[ "$myleafy_running" == true ]]; then systemctl start "$myleafy_service"; fi; }
trap restore_service EXIT
systemctl stop "$myleafy_service"
cd "/opt/myleafy/${myleafy_environment}/current/backend"
/usr/local/bin/node --env-file="/etc/myleafy/${myleafy_environment}.backup.env" scripts/ecs/local-backup.mjs "/var/lib/myleafy/${myleafy_environment}" "/var/backups/myleafy/${myleafy_environment}" "/etc/myleafy/${myleafy_environment}.env" "$myleafy_environment"
