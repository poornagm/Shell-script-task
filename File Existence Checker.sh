#!/usr/bin/env sh

printf "Enter the filename: "
read -r filepath

if [ -z "$filepath" ]; then
    echo "Error: No filename entered."
    exit 1
fi

if [ -e "$filepath" ]; then
    echo "File '$filepath' exists."

    # Display permissions and human-readable size
    if stat -c "" /dev/null >/dev/null 2>&1; then
        # GNU/Linux stat
        perms=$(stat -c "%A (%a)" "$filepath")
        size=$(stat -c "%s bytes" "$filepath")
    else
        # macOS / BSD stat
        perms=$(stat -f "%Sp (%OLp)" "$filepath")
        size=$(stat -f "%z bytes" "$filepath")
    fi

    echo "Permissions: $perms"
    echo "Size:        $size"
else
    echo "Error: File '$filepath' does not exist."
    exit 1
fi

