#!/bin/bash

set -euo pipefail

VERSION="0.4"

show_help() {
  cat <<EOF
Usage: $0 [--config FILE] [--version] [--help]

Options:
  --config FILE    Path to config file to run non-interactively
  --version        Display script and PVE host version
  --help           Show this help message

Config file format:
  BOND_NAME=bond0
  BRIDGE_NAME=vmbr1
  HOST_ID=0
  SLAVE_IFACES="eno2 eno3 eno4"
  AUTO_APPLY=yes
EOF
}

show_version() {
  echo "pve-replication-link.sh version $VERSION"
  echo -n "Proxmox VE version: "; pveversion
  exit 0
}

# Default values
CONFIG_FILE=""
AUTO_APPLY="no"
BOND_NAME=""
BRIDGE_NAME=""
HOST_ID=""
SLAVE_IFACES=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --help|-h) show_help; exit 0;;
    --version) show_version;;
    --config) CONFIG_FILE="$2"; shift 2;;
    *) echo "Unknown argument: $1"; show_help; exit 1;;
  esac
done

# List existing bonds and bridges
EXISTING_BONDS=$(grep -oP '^iface\s+\K(bond[0-9]+)' /etc/network/interfaces | sort -u)
EXISTING_BRIDGES=$(grep -oP '^iface\s+\K(vmbr[0-9]+)' /etc/network/interfaces | sort -u)

# Load config if provided
if [[ -n "$CONFIG_FILE" ]]; then
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Config file not found: $CONFIG_FILE"; exit 1
  fi
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

# List available NICs
ALL_NICS=$(ls /sys/class/net )
USED_NICS=$(grep -E '^\s*(iface|bridge_ports|slaves)\s+' /etc/network/interfaces | grep -oE '[a-zA-Z0-9]+')
AVAILABLE_NICS=()
for nic in $ALL_NICS; do
  if ! echo "$USED_NICS" | grep -qw "$nic"; then
    AVAILABLE_NICS+=("$nic")
  fi

done

if [[ ${#AVAILABLE_NICS[@]} -eq 0 ]]; then
  echo "No available NICs for bonding. Aborting."
  exit 1
fi

# Prompt functions
prompt_or_quit() {
  local prompt_msg="$1"
  local var_name="$2"
  local pattern="$3"
  local reject_list="$4"
  local input
  while true; do
    read -rp "$prompt_msg" input
    [[ "$input" =~ ^[Qq](uit)?$ ]] && echo "Quitting." && exit 0
    if [[ "$input" =~ $pattern ]]; then
      if echo "$reject_list" | grep -qw "$input"; then
        echo "$input already exists. Choose another."
      else
        eval $var_name="$input"
        break
      fi
    else
      echo "Invalid input."
    fi
  done
}

if [[ -z "$BOND_NAME" ]]; then
  echo "Existing bond interfaces: ${EXISTING_BONDS:- (none)}"
  prompt_or_quit "Enter name for new bond (e.g., bond0) [q to quit]: " BOND_NAME '^bond[0-9]+$' "$EXISTING_BONDS"
fi

if echo "$EXISTING_BONDS" | grep -qw "$BOND_NAME"; then
  echo "Error: Bond '$BOND_NAME' already exists in system configuration. Aborting."; exit 1
fi

if [[ -z "$BRIDGE_NAME" ]]; then
  echo "Existing bridge interfaces: ${EXISTING_BRIDGES:- (none)}"
  prompt_or_quit "Enter name for new bridge (e.g., vmbr1) [q to quit]: " BRIDGE_NAME '^vmbr[0-9]+$' "$EXISTING_BRIDGES"
fi

if echo "$EXISTING_BRIDGES" | grep -qw "$BRIDGE_NAME"; then
  echo "Error: Bridge '$BRIDGE_NAME' already exists in system configuration. Aborting."; exit 1
fi

if [[ -z "$HOST_ID" ]]; then
  while true; do
    read -rp "Is this host IP .0 or .1? Enter 0 or 1 [q to quit]: " input
    [[ "$input" =~ ^[Qq](uit)?$ ]] && echo "Quitting." && exit 0
    [[ "$input" =~ ^[01]$ ]] && HOST_ID="$input" && break
    echo "Invalid input. Please enter 0 or 1."
  done
fi

if [[ -z "$SLAVE_IFACES" ]]; then
  echo "Available NICs for bonding:"
  for nic in "${AVAILABLE_NICS[@]}"; do
    echo "  - $nic"
  done
  read -rp "Enter space-separated NICs to bond (e.g., eno2 eno3) [q to quit]: " SLAVE_IFACES
  [[ "$SLAVE_IFACES" =~ ^[Qq](uit)?$ ]] && echo "Quitting." && exit 0
fi

# Create bond and bridge configuration
IP_BASE="10.100.160"
HOST_IP="$IP_BASE.$HOST_ID/31"

cat <<EOF
Configuration Summary:
  Bond: $BOND_NAME with slaves: $SLAVE_IFACES
  Bridge: $BRIDGE_NAME on $BOND_NAME
  Host IP: $HOST_IP
EOF

if [[ "$AUTO_APPLY" != "yes" ]]; then
  read -rp "Apply changes and run ifreload? [y/N/q]: " CONFIRM
  [[ "$CONFIRM" =~ ^[Qq]$ ]] && echo "Aborted." && exit 0
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Not applying changes."; exit 0; }
fi

# Write to /etc/network/interfaces.d
INTERFACES_DIR="/etc/network/interfaces.d"
BOND_FILE="$INTERFACES_DIR/$BOND_NAME"
BRIDGE_FILE="$INTERFACES_DIR/$BRIDGE_NAME"

[[ -f "$BOND_FILE" ]] && echo "$BOND_FILE already exists, aborting." && exit 1
[[ -f "$BRIDGE_FILE" ]] && echo "$BRIDGE_FILE already exists, aborting." && exit 1

cat > "$BOND_FILE" <<EOF
auto $BOND_NAME
iface $BOND_NAME inet manual
  bond-slaves $SLAVE_IFACES
  bond-miimon 100
  bond-mode balance-xor
  bond-xmit-hash-policy layer2+3
EOF

cat > "$BRIDGE_FILE" <<EOF
auto $BRIDGE_NAME
iface $BRIDGE_NAME inet static
  address $HOST_IP
  bridge-ports $BOND_NAME
  bridge-stp off
  bridge-fd 0
EOF

ifreload -a && echo "Interfaces updated successfully."
