#!/bin/bash
set -euo pipefail

JS_FILE="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
BACKUP_FILE="${JS_FILE}.bak"
TMP_FILE="$(mktemp)"

# Create a backup only if it doesn't exist
if [[ ! -f "$BACKUP_FILE" ]]; then
    cp "$JS_FILE" "$BACKUP_FILE"
fi

# Patch the file in a temp location
sed -Ez "s/(Ext.Msg.show\(\{\s+title: gettext\('No valid sub)/void({ \/\/\1/" "$JS_FILE" > "$TMP_FILE"

# Compare patched version with original
if ! cmp -s "$JS_FILE" "$TMP_FILE"; then
    echo "Patching subscription popup message..."
    cp "$TMP_FILE" "$JS_FILE"
    systemctl restart pveproxy.service
    echo "Patch applied and pveproxy restarted."
else
    echo "No patch needed; already applied."
fi

# Clean up
rm -f "$TMP_FILE"
