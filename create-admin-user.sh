#!/bin/bash
set -e

USERNAME="admin"
USER_UID=950
GROUPNAME="admin"
GROUP_GID=950
HOMEDIR="/home/$USERNAME"
SHELL="/bin/bash"

# 1. Create group if it doesn't exist
if ! getent group "$GROUPNAME" >/dev/null; then
  echo "Creating group $GROUPNAME with GID $GROUP_GID..."
  groupadd -g "$GROUP_GID" "$GROUPNAME"
else
  echo "Group $GROUPNAME already exists."
fi

# 2. Create home directory if it doesn't exist
if [ ! -d "$HOMEDIR" ]; then
  echo "Creating home directory $HOMEDIR..."
  mkdir -p "$HOMEDIR"
else
  echo "Home directory $HOMEDIR already exists."
fi

# 3. Create user if it doesn't exist
if ! id "$USERNAME" &>/dev/null; then
  echo "Creating user $USERNAME..."
  useradd -d "$HOMEDIR" -u "$USER_UID" -g "$GROUP_GID" "$USERNAME"
else
  echo "User $USERNAME already exists."
fi

# 4. Add user to sudo group if not already a member
if ! id -nG "$USERNAME" | grep -qw "sudo"; then
  echo "Adding $USERNAME to sudo group..."
  usermod -aG sudo "$USERNAME"
else
  echo "$USERNAME is already in the sudo group."
fi

# 5. Set password interactively
if [ -z "$SKIP_PASSWORD" ]; then
  echo "Setting password for $USERNAME..."
  passwd "$USERNAME"
else
  echo "Skipping password prompt (SKIP_PASSWORD is set)."
fi

# 6. Set ownership of home directory
CURRENT_OWNER=$(stat -c "%U:%G" "$HOMEDIR")
if [ "$CURRENT_OWNER" != "$USERNAME:$GROUPNAME" ]; then
  echo "Setting ownership of $HOMEDIR to $USERNAME:$GROUPNAME..."
  chown "$USERNAME:$GROUPNAME" "$HOMEDIR"
else
  echo "Ownership of $HOMEDIR is already correct."
fi

# 7. Set shell if incorrect
CURRENT_SHELL=$(getent passwd "$USERNAME" | cut -d: -f7)
if [ "$CURRENT_SHELL" != "$SHELL" ]; then
  echo "Setting shell for $USERNAME to $SHELL..."
  usermod -s "$SHELL" "$USERNAME"
else
  echo "Shell for $USERNAME is already $SHELL."
fi

# 8. Show user info
echo
echo "User info for $USERNAME:"
id "$USERNAME"
