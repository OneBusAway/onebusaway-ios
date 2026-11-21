#!/usr/bin/env bash
#
# scripts/lib/smoke_common.sh
#
# Shared routines for iOS and watchOS release smoke testing:
#   - Preflight environment & toolchain validation
#   - Simulator boot and state readiness
#   - Resilient installation with retry on shutdown
#   - Liveness verification (process name + kill -0)
#   - Informational launchd registration checks
#   - Diagnostic report and failure log extraction
#   - Failure screenshot capture
#

# Checks whether a simulator is booted and ready
smoke_ensure_simulator_ready() {
    local udid="$1"
    local bundle_id="${2:-}"

    xcrun simctl boot "$udid" 2>/dev/null || true
    if ! xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1; then
        echo "error: simctl bootstatus failed for simulator $udid" >&2
        return 1
    fi

    if [ -n "$bundle_id" ]; then
        xcrun simctl terminate "$udid" "$bundle_id" 2>/dev/null || true
    fi
    return 0
}

# Installs app bundle onto simulator, retrying up to 3 times if simulator shuts down.
#
# Booted after the build, not before it: the build doesn't need a running
# simulator, and one booted first was found shut down by install time after a
# 4.5-minute CI build (CoreSimulator 405, "Unable to lookup in current state:
# Shutdown"). A first boot also saturates a CI runner, which slowed the build.
#
# Even booted here, a CI simulator has passed bootstatus and then been found
# shut down by install (#1591). That is the runner, not the app, so only that
# failure boots it again; any other install error fails at once.
smoke_install_with_retry() {
    local udid="$1"
    local app="$2"
    local bundle_id="$3"
    local installed=0
    local install_output=""

    for attempt in 1 2 3; do
        smoke_ensure_simulator_ready "$udid" "$bundle_id" || true

        if install_output=$(xcrun simctl install "$udid" "$app" 2>&1); then
            installed=1
            break
        fi
        echo "$install_output" >&2
        if ! grep -q "current state: Shutdown" <<<"$install_output" || [ "$attempt" -eq 3 ]; then
            break
        fi
        echo "simulator shut down before install (attempt $attempt of 3); booting it again" >&2
        sleep 2
    done

    if [ "$installed" -ne 1 ]; then
        echo "error: simctl install failed" >&2
        return 1
    fi
    return 0
}

# Verifies that a launched process stays alive after launch and matches expected name
smoke_verify_liveness() {
    local pid="$1"
    local expected_comm="$2"

    if [ -z "$pid" ]; then
        return 1
    fi

    if ! kill -0 "$pid" 2>/dev/null; then
        return 1
    fi

    local comm
    comm=$(ps -p "$pid" -o comm= 2>/dev/null || true)
    local base_comm
    base_comm=$(basename "$comm")

    if [ "$base_comm" != "$expected_comm" ]; then
        return 1
    fi

    return 0
}

# Informational check for launchd registration.
#
# `launchctl list` was measured to lag a live process by more than 18 s under
# post-install daemon load, so it cannot gate PASS/FAIL here; it is reported
# for information only. A dyld-killed app never survives the 8 s wait, so
# `kill -0` plus a check of the process's own name is what keeps the
# assertion meaningful (the name check guards against another process having
# reused the PID).
smoke_check_launchd_registration() {
    local udid="$1"
    local bundle_id="$2"
    local registered=0

    for _ in 1 2 3 4 5; do
        if xcrun simctl spawn "$udid" launchctl list 2>/dev/null | grep -q "$bundle_id"; then
            registered=1
            break
        fi
        sleep 2
    done

    if [ "$registered" -eq 1 ]; then
        echo "launchd registration: yes"
    else
        echo "launchd registration: not observed within 10 s (informational)"
    fi
}

# Captures a failure screenshot via simctl io
smoke_capture_screenshot() {
    local udid="$1"
    local dest_path="$2"
    local dest_dir
    dest_dir=$(dirname "$dest_path")
    mkdir -p "$dest_dir" 2>/dev/null || true
    if xcrun simctl io "$udid" screenshot "$dest_path" 2>/dev/null; then
        echo "$dest_path"
    fi
}

# Captures rich failure diagnostics: dyld logs, process logs, crash reports, and screenshots
smoke_capture_diagnostics() {
    local udid="$1"
    local bundle_id="$2"
    local proc_name="$3"
    local screenshot_path="${4:-}"

    echo "" >&2
    echo "================ SMOKE TEST FAILURE DIAGNOSTICS ================" >&2
    echo "Bundle ID:    $bundle_id" >&2
    echo "Process:      $proc_name" >&2
    echo "Simulator:    $udid" >&2

    echo "" >&2
    echo "--- [1/4] dyld / library-load failures ---" >&2
    xcrun simctl spawn "$udid" log show --last 2m --style compact \
      --predicate 'eventMessage CONTAINS "Library not loaded" OR eventMessage CONTAINS "OS_REASON_DYLD" OR eventMessage CONTAINS "dyld"' 2>/dev/null | head -30 >&2 || true

    echo "" >&2
    echo "--- [2/4] Recent simulator logs for $proc_name / $bundle_id ---" >&2
    xcrun simctl spawn "$udid" log show --last 2m \
      --predicate "process == '$proc_name' OR eventMessage CONTAINS '$bundle_id'" 2>/dev/null | tail -40 >&2 || true

    echo "" >&2
    echo "--- [3/4] Recent Crash Reports (~/Library/Logs/DiagnosticReports) ---" >&2
    local diag_dir="$HOME/Library/Logs/DiagnosticReports"
    if [ -d "$diag_dir" ]; then
        local crash_files
        crash_files=$(find "$diag_dir" -maxdepth 1 \( -name "${proc_name}*.ips" -o -name "${proc_name}*.crash" \) -mmin -10 2>/dev/null | sort -r | head -3 || true)
        if [ -n "$crash_files" ]; then
            for cf in $crash_files; do
                echo "Found crash report: $cf" >&2
                case "$cf" in
                    *.ips)
                        if ! python3 -c '
import json, sys
path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()
    payload = None
    try:
        payload = json.loads(content)
    except Exception:
        first_newline = content.find("\n")
        if first_newline != -1:
            payload = json.loads(content[first_newline + 1:])
    if not isinstance(payload, dict):
        sys.exit(1)

    term = payload.get("termination")
    if term:
        ind = term.get("indicator") or term.get("code") or ""
        ns = term.get("namespace") or ""
        print(f"Termination Reason: {ns} ({ind})")

    exc = payload.get("exception")
    if exc:
        exc_type = exc.get("type", "")
        signal = exc.get("signal", "")
        codes = exc.get("codes", "")
        print(f"Exception Type: {exc_type} ({signal})")
        if codes:
            print(f"Exception Codes: {codes}")

    faulting_idx = payload.get("faultingThread")
    threads = payload.get("threads", [])
    crashed_thread = None
    if faulting_idx is not None and 0 <= faulting_idx < len(threads):
        crashed_thread = threads[faulting_idx]
    else:
        for t in threads:
            if t.get("triggered"):
                crashed_thread = t
                break

    if crashed_thread:
        name = crashed_thread.get("name", "")
        thread_label = f"Thread {faulting_idx}" if faulting_idx is not None else "Crashed Thread"
        if name:
            thread_label += f" ({name})"
        print(f"--- Crashed Thread Backtrace ({thread_label}) ---")
        used_images = payload.get("usedImages", [])
        for i, frame in enumerate(crashed_thread.get("frames", [])[:25]):
            img_name = ""
            img_idx = frame.get("imageIndex")
            if img_idx is not None and 0 <= img_idx < len(used_images):
                img_name = used_images[img_idx].get("name", "")
            symbol = frame.get("symbol", "")
            offset = frame.get("symbolLocation", "")
            line = f"{i:<3} {img_name:<20} {symbol}"
            if offset:
                line += f" + {offset}"
            print(line)
except Exception:
    sys.exit(1)
' "$cf" >&2; then
                            grep -E "Termination Reason|Termination Signal|Exception Type|Exception Codes|Dyld Error Message|Application Specific Information" "$cf" >&2 || true
                            echo "--- Crashed Thread Backtrace (sample) ---" >&2
                            awk '/Thread [0-9]+ Crashed:/,/^$/' "$cf" 2>/dev/null | head -25 >&2 || true
                        fi
                        ;;
                    *)
                        grep -E "Termination Reason|Termination Signal|Exception Type|Exception Codes|Dyld Error Message|Application Specific Information" "$cf" >&2 || true
                        echo "--- Crashed Thread Backtrace (sample) ---" >&2
                        awk '/Thread [0-9]+ Crashed:/,/^$/' "$cf" 2>/dev/null | head -25 >&2 || true
                        ;;
                esac
            done
        else
            echo "No recent crash reports matching '${proc_name}' in DiagnosticReports." >&2
        fi
    fi

    if [ -n "$screenshot_path" ]; then
        echo "" >&2
        echo "--- [4/4] Failure Screenshot ---" >&2
        local screen_dest
        screen_dest=$(smoke_capture_screenshot "$udid" "$screenshot_path")
        if [ -n "$screen_dest" ] && [ -f "$screen_dest" ]; then
            echo "Saved failure screenshot to: $screen_dest" >&2
        fi
    fi
    echo "=================================================================" >&2
}

# Validates toolchain, simulator presence, and prebuilt paths for --dry-run
smoke_validate_preflight() {
    local udid="$1"
    local expected_product="$2"
    local skip_build="$3"

    echo "==> Validating preflight requirements..."
    if ! command -v xcrun >/dev/null 2>&1; then
        echo "error: xcrun command not found." >&2
        return 1
    fi

    if ! xcrun simctl list devices available -j >/dev/null 2>&1; then
        echo "error: xcrun simctl is not responding or no devices available." >&2
        return 1
    fi

    if ! xcrun simctl list devices available | grep -q "$udid"; then
        echo "error: simulator UDID '$udid' not found in available device list." >&2
        return 1
    fi
    echo "  ✔ Simulator '$udid' is present and available."

    if [ "$skip_build" -eq 1 ]; then
        if [ ! -d "$expected_product" ]; then
            echo "error: --skip-build specified but product does not exist at '$expected_product'." >&2
            return 1
        fi
        echo "  ✔ Prebuilt product found at '$expected_product'."
    fi

    echo "  ✔ Preflight validation checks passed."
    return 0
}
