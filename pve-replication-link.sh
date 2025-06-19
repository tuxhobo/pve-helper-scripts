#!/bin/bash
set -euo pipefail

SCRIPT_VERSION="0.2"
TMP_FILE="/tmp/ifcfg-bond-temp.$$"

show_help() {
cat << EOF
Replication Link Bond Setup Script (version $SCRIPT_VERSION)

Usage: $0 [CONFIG_FILE]

Configure a bonded interface and bridge for Proxmox point-to-point links.

Options:
  CONFIG_FILE      Optional path to a configuration file (bash key=value format).
  -h, --help       Show this help message and exit.
  -v, --version    Show Proxmox host version and script version.

Config File Format (bash-style):
  HOST_ID=0
  SLAVES="eno2 eno3 eno4"
  BOND_NAME="bond0"
  BRIDGE_NAME="vmbr1"
  SUBNET_PREFIX="10.100.160"
  AUTO_APPLY=true     # Optional, skip confirmation and apply automatically
EOF
}

show_version() {
    echo "pve-replication-link.sh version: $SCRIPT_VERSION"
    if [[ -f /etc/pve/.version ]]; then
        echo "Proxmox version:"
        pveversion
    else
        echo "Proxmox version: Not detected"
    fi
    exit 0
}

# Handle flags
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -v|--version)
        show_version
        ;;
esac

# Load config if passed
CONFIG_FILE="${1:-}"
if [[ -n "$CONFIG_FILE" ]]; then
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "Loading configuration from $CONFIG_FILE..."
        source "$CONFIG_FILE"
    else
        echo "Error: Config file '$CONFIG_FILE' not found."
        exit 1
    fi
fi

# === Prompt/Defaults ===
HOST_ID="${HOST_ID:-}"
if [[ -z "$HOST_ID" ]]; then
    read -p "Is this host IP .0 or .1? Enter 0 or 1: " HOST_ID
fi
if [[ "$HOST_ID" != "0" && "$HOST_ID" != "1" ]]; then
    echo "Invalid HOST_ID: must be 0 or 1."
    exit 1
fi

detect_unused_ifaces() {
    for iface in $(ls /sys/class/net); do
        [[ "$iface" =~ ^(lo|vmbr|bond|eno1)$ ]] && continue
        ip link show "$iface" | grep -q "state UP" && continue
        echo -n "$iface "
    done
}

SLAVES="${SLAVES:-}"
if [[ -z "$SLAVES" ]]; then
    echo "Detected unused interfaces: $(detect_unused_ifaces)"
    read -p "Enter space-separated interfaces to bond: " SLAVES
fi

BOND_NAME="${BOND_NAME:-bond0}"
BRIDGE_NAME="${BRIDGE_NAME:-vmbr1}"
SUBNET_PREFIX="${SUBNET_PREFIX:-10.100.160}"
IP="$SUBNET_PREFIX.$HOST_ID/31"
AUTO_APPLY="${AUTO_APPLY:-false}"

# === Idempotency Checks ===
grep -q "iface $BOND_NAME" /etc/network/interfaces && {
    echo "Bond interface '$BOND_NAME' already exists in /etc/network/interfaces."
    exit 1
}
grep -q "iface $BRIDGE_NAME" /etc/network/interfaces && {
    echo "Bridge '$BRIDGE_NAME' already exists in /etc/network/interfaces."
    exit 1
}

# === Append Configuration to TEMP file ===
cat << EOF > "$TMP_FILE"

auto $BOND_NAME
iface $BOND_NAME inet manual
    bond-slaves $SLAVES
    bond-miimon 100
    bond-mode balance-xor
    bond-xmit-hash-policy layer3+4

auto $BRIDGE_NAME
iface $BRIDGE_NAME inet static
    address $IP
    netmask 255.255.255.254
    bridge-ports $BOND_NAME
    bridge-stp off
    bridge-fd 0
EOF

# === Confirm and Apply ===
echo
echo "Planned configuration:"
cat "$TMP_FILE"

if [[ "$AUTO_APPLY" == "true" ]]; then
    echo "AUTO_APPLY=true: Applying changes without confirmation..."
    cat "$TMP_FILE" >> /etc/network/interfaces
    ifreload -a
    echo "Done."
    rm -f "$TMP_FILE"
    exit 0
fi

echo
read -p "Apply changes and run 'ifreload -a'? [y]es / [n]o / [a]bandon: " confirm
case "$confirm" in
    y|Y)
        cat "$TMP_FILE" >> /etc/network/interfaces
        echo "Reloading interfaces..."
        ifreload -a
        echo "Done."
        ;;
    n|N)
        cat "$TMP_FILE" >> /etc/network/interfaces
        echo "Changes written to /etc/network/interfaces."
        echo "Reload manually with: ifreload -a"
        ;;
    a|A)
        echo "Abandoning changes. Nothing was modified."
        ;;
    *)
        echo "Invalid option. Aborting."
        ;;
esac

rm -f "$TMP_FILE"
