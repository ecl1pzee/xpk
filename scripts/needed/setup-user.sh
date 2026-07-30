#!/bin/sh

set -eu

buildusr="xpk"
tmpdir="/tmp/xpk"
xpkbin="/opt/xpk/bin"

if [ "$(id -u)" -ne 0 ]; then
    echo "[x] must be run as root (use sudo)" >&2
    exit 1
fi

osname="$(uname -s)"

userexist() {
    id -u "$buildusr" >/dev/null 2>&1
}

echo "[*] checking for existing '$buildusr' user..."

if userexist; then
    echo "[+] user '$buildusr' already exists, skipping creation"
else
    case "$osname" in
    Linux)
        echo "[*] creating system user '$buildusr' (linux)..."
        useradd \
            --system \
            --no-create-home \
            --shell /bin/sh \
            "$buildusr"
        ;;

    FreeBSD) # here is ur freebsd support
        echo "[*] creating system user '$buildusr' (freebsd)..."
        pw useradd "$buildusr" \
            -r \
            -M \
            -s /bin/sh \
            -d /nonexistent

        echo "[+] created '$buildusr'"
        ;;

    Darwin)
        echo "[*] creating system user '$buildusr' (darwin based systems)..."

        newuid=""
        for candidate in $(seq 499 -1 200); do
            if ! dscl . -list /Users UniqueID | awk '{print $2}' | grep -qx "$candidate"; then
                newuid="$candidate"
                break
            fi
        done

        if [ -z "$newuid" ]; then
            echo "[x] no free system uid found in range 200-499, so i cannot do anythin" >&2
            exit 1
        fi

        dscl . -create "/Users/$buildusr"
        dscl . -create "/Users/$buildusr" UserShell /bin/sh
        dscl . -create "/Users/$buildusr" UniqueID "$newuid"
        dscl . -create "/Users/$buildusr" PrimaryGroupID 20
        dscl . -create "/Users/$buildusr" NFSHomeDirectory /var/empty

        echo "[+] created '$buildusr' with UID $newuid"
        ;;

    *)
        echo "[x] unsupported os: $osname" >&2
        exit 1
        ;;
    esac
fi

echo "[*] ensuring $tmpdir exists and is owned by '$buildusr'..."
mkdir -p "$tmpdir"
chown -R "$buildusr" "$tmpdir"
chmod 700 "$tmpdir"

echo "[*] ensuring $xpkbin exists for future path use..."
mkdir -p "$xpkbin"

case "$osname" in
Darwin)
    chown "$buildusr:staff" "$xpkbin"
    ;;
Linux|FreeBSD)
    chown "$buildusr" "$xpkbin"
    ;;
esac

chmod 755 "$xpkbin"

echo "[+] setup complete: '$buildusr' owns $tmpdir, and can use $xpkbin"