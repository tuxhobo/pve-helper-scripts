#!/bin/bash
set -e

USER="admin@pam"
GROUP="admin"
COMMENT="non root administrator"
GROUP_COMMENT="System Administrators"
ROLE="Administrator"
ACL_PATH="/"

# 1. Add user if not exists
if ! pveum user list | grep -q "^$USER"; then
  echo "Creating user $USER..."
  pveum user add "$USER" -comment "$COMMENT"
else
  echo "User $USER already exists."
fi

# 2. Set password interactively
if [ -z "$SKIP_PASSWORD" ]; then
  echo "Setting password for $USER..."
  pveum passwd "$USER"
else
  echo "Skipping password prompt (SKIP_PASSWORD is set)."
fi

# 3. Create group if not exists
if ! pveum group list | grep -q "^$GROUP\s"; then
  echo "Creating group $GROUP..."
  pveum group add "$GROUP" --comment "$GROUP_COMMENT"
else
  echo "Group $GROUP already exists."
fi

# 4. Set ACL if not already set
if ! pveum acl list | awk '$1 == "/" && $2 == "group" && $3 == "'$GROUP'" && $4 == "'$ROLE'"' | grep -q .; then
  echo "Setting ACL for group $GROUP on $ACL_PATH with role $ROLE..."
  pveum acl modify "$ACL_PATH" -group "$GROUP" -role "$ROLE"
else
  echo "ACL for group $GROUP on $ACL_PATH with role $ROLE already set."
fi

# 5. Add user to group if not already added
CURRENT_GROUPS=$(pveum user list | awk -v user="$USER" '$1 == user { print $5 }')
if [[ "$CURRENT_GROUPS" != *"$GROUP"* ]]; then
  echo "Adding $USER to group $GROUP..."
  pveum user modify "$USER" -group "$GROUP"
else
  echo "$USER is already in group $GROUP."
fi
