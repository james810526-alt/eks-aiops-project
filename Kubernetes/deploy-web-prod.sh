#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <alb-security-group-id> [apply|delete]" >&2
  exit 2
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
fi

alb_security_group_id="$1"
action="${2:-apply}"

if [[ ! "$alb_security_group_id" =~ ^sg-[0-9a-f]+$ ]]; then
  echo "Invalid ALB security group ID: $alb_security_group_id" >&2
  exit 2
fi

case "$action" in
  apply|delete) ;;
  *) usage ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template_path="$script_dir/web-prod-app.yaml"
rendered_path="$script_dir/web-prod-app.rendered.yaml"

if ! grep -q "__ALB_SECURITY_GROUP_ID__" "$template_path"; then
  echo "Template placeholder not found in $template_path" >&2
  exit 1
fi

sed "s/__ALB_SECURITY_GROUP_ID__/${alb_security_group_id}/g" \
  "$template_path" > "$rendered_path"

if grep -q "__ALB_SECURITY_GROUP_ID__" "$rendered_path"; then
  echo "Failed to render ALB security group ID" >&2
  exit 1
fi

echo "Running: kubectl $action -f $rendered_path"
kubectl "$action" -f "$rendered_path"
