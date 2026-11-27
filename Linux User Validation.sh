#!/usr/bin/env bash

printf "Enter the username: "
read -r username

if [ -z "$username" ]; then
    echo "Error: No username entered." >&2
    exit 1
fi

if entry=$(getent passwd "$username") && [ -n "$entry" ]; then
    uid=$(printf '%s\n' "$entry" | cut -d: -f3)
    gid=$(printf '%s\n' "$entry" | cut -d: -f4)
    primary_group=$(getent group "$gid" | cut -d: -f1)

    echo "User '$username' exists."
    echo "UID:           $uid"
    echo "Primary Group: ${primary_group:-$gid} (GID: $gid)"
else
    echo "Error: User '$username' does not exist." >&2
    exit 1
fi
