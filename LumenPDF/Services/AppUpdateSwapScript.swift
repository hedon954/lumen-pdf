import Foundation

/// Helper that replaces the running `.app` after this process has exited.
///
/// A running macOS app cannot overwrite its own bundle. Sparkle-style updaters
/// launch a detached helper, quit, then let the helper move the old bundle aside
/// and copy the new one in. `open` of the new bundle must wait until the old
/// pid is gone, otherwise Launch Services reactivates the still-running instance.
enum AppUpdateSwapScript {
    static let waitSeconds = 120
    static let termAfterSeconds = 60
    static let killAfterSeconds = 90

    static var contents: String {
        """
        #!/bin/bash
        set -euo pipefail
        pid="$1"
        target="$2"
        staged="$3"
        backup="${target}.previous"

        echo "waiting for ${pid}"
        deadline=$((SECONDS + \(waitSeconds)))
        while kill -0 "$pid" 2>/dev/null; do
            elapsed=$SECONDS
            if [ "$elapsed" -ge "$deadline" ]; then
                echo "timed out waiting for ${pid}"
                exit 1
            fi
            if [ "$elapsed" -ge \(killAfterSeconds) ]; then
                echo "killing ${pid}"
                kill -KILL "$pid" 2>/dev/null || true
            elif [ "$elapsed" -ge \(termAfterSeconds) ]; then
                echo "terminating ${pid}"
                kill -TERM "$pid" 2>/dev/null || true
            fi
            sleep 0.2
        done
        sleep 0.4

        rm -rf "$backup"
        if [ -d "$target" ]; then
            mv "$target" "$backup"
        fi
        if ! /usr/bin/ditto "$staged" "$target"; then
            rm -rf "$target"
            if [ -d "$backup" ]; then
                mv "$backup" "$target"
            fi
            exit 1
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$target" || true
        rm -rf "$backup"
        echo "relaunching ${target}"
        /usr/bin/open "$target"
        """
    }
}
