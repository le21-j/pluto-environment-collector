#!/bin/sh
# Detached recovery watchdog for the ES RX-DMA major-13 fleet volatile-load canary.

set -u
umask 077

MODE=
TOKEN=
SECONDS_LIMIT=
HELPER_SHA=
PAYLOAD_NAME=system_top_major13.bit.bin
PAYLOAD_SHA=b33569b289fe3c8feaa09e40f41076862e1297c46dd1f85972305593bc646b59
PAYLOAD_BYTES=2083744
EXPECTED_PRE_VERSION=0x000CDFFF
EXPECTED_POST_VERSION=0x000DDFFF
PS_FCLK3_VALUE=0x00300400
PS_IO_PLL_VALUE=0x0001E000
NODE=es
EXPECTED_SERIAL=1044737ac3180015f0ff3300fb12e035cb
EXPECTED_BOOT_ID=245bc026-8677-4942-9270-4ad1dc346c0a
CANDIDATE_REVIEW_MANIFEST_SHA=fea1580f7f1bb25ae1217753012fda2c05ecc41a84cc6539605692e4a924501b
CANDIDATE_SIGNOFF_MANIFEST_SHA=dc5ad5009c7272b8d506dda074b7d47f730ab1ab69c99a5d86b8901a9de54e02
TEST_ROOT=${ARC3_TEST_ROOT:-}

if [ -n "$TEST_ROOT" ] && [ "${ARC3_TEST_MODE:-0}" != 1 ]; then
    echo "ARC3_WATCHDOG_REFUSE test root requires ARC3_TEST_MODE=1" >&2
    exit 90
fi

p() { printf '%s%s' "$TEST_ROOT" "$1"; }

usage() {
    echo "Usage: $0 --plan | --execute --token TOKEN --seconds 60..300 --helper-sha256 SHA256"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --plan|--execute)
            [ -z "$MODE" ] || { echo "ARC3_WATCHDOG_REFUSE choose one mode" >&2; exit 2; }
            MODE=${1#--}; shift ;;
        --token) TOKEN=$2; shift 2 ;;
        --seconds) SECONDS_LIMIT=$2; shift 2 ;;
        --helper-sha256) HELPER_SHA=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ARC3_WATCHDOG_REFUSE unknown argument $1" >&2; exit 2 ;;
    esac
done

if [ "$MODE" = plan ]; then
    echo "RX12_MAJOR13_ES_LOAD_WATCHDOG_PLAN_V1 payload_sha256=$PAYLOAD_SHA disarm=atomic_exact_candidate_load_PASS timeout=/usr/sbin/device_reboot_reset rerun=never"
    exit 0
fi
[ "$MODE" = execute ] || { usage >&2; exit 2; }
case "$TOKEN" in *[!A-Za-z0-9_-]*|'') echo "ARC3_WATCHDOG_REFUSE invalid token" >&2; exit 2 ;; esac
[ "${#TOKEN}" -ge 12 ] && [ "${#TOKEN}" -le 64 ] || { echo "ARC3_WATCHDOG_REFUSE token length" >&2; exit 2; }
case "$SECONDS_LIMIT" in *[!0-9]*|'') echo "ARC3_WATCHDOG_REFUSE invalid seconds" >&2; exit 2 ;; esac
if [ -n "$TEST_ROOT" ]; then
    [ "$SECONDS_LIMIT" -ge 1 ] && [ "$SECONDS_LIMIT" -le 300 ] || exit 2
else
    [ "$SECONDS_LIMIT" -ge 60 ] && [ "$SECONDS_LIMIT" -le 300 ] || {
        echo "ARC3_WATCHDOG_REFUSE seconds outside 60..300" >&2; exit 2;
    }
fi
case "$HELPER_SHA" in *[!0-9a-f]*|'') echo "ARC3_WATCHDOG_REFUSE helper SHA" >&2; exit 2 ;; esac
[ "${#HELPER_SHA}" -eq 64 ] || { echo "ARC3_WATCHDOG_REFUSE helper SHA length" >&2; exit 2; }
command -v sha256sum >/dev/null 2>&1 || { echo "ARC3_WATCHDOG_REFUSE sha256sum missing" >&2; exit 3; }
command -v sleep >/dev/null 2>&1 || { echo "ARC3_WATCHDOG_REFUSE sleep missing" >&2; exit 3; }
[ -x "$(p /usr/sbin/device_reboot)" ] || { echo "ARC3_WATCHDOG_REFUSE device_reboot missing" >&2; exit 3; }
[ -w "$(p /sys/kernel/debug/zynq_rst/code)" ] || { echo "ARC3_WATCHDOG_REFUSE reset code attribute not writable" >&2; exit 3; }
[ -x "$(p /sbin/reboot)" ] || { echo "ARC3_WATCHDOG_REFUSE reboot executable missing" >&2; exit 3; }

ack="$(p /tmp)/rx12_v13_es_load_recovery_${TOKEN}.ack"
ack_tmp="${ack}.$$"
journal="$(p /tmp)/rx12_v13_es_load_${TOKEN}"
terminal="$journal/terminal_result"
result="$(p /tmp)/rx12_v13_es_load_recovery_${TOKEN}.result"
[ ! -e "$ack" ] && [ ! -e "$journal" ] && [ ! -e "$result" ] || {
    echo "ARC3_WATCHDOG_REFUSE token paths already exist" >&2; exit 4;
}
watchdog_sha=$(sha256sum "$0" | awk '{print $1}')
printf 'schema=rx12.major13-volatile-load-recovery.v1\nnode=%s\ndevice_serial=%s\ndevice_boot_id=%s\ntoken=%s\nwatchdog_pid=%s\ndevice_reboot=/usr/sbin/device_reboot reset\nsuccess_marker=/tmp/rx12_v13_es_load_%s/terminal_result\ndeadline_seconds=%s\nwatchdog_script_sha256=%s\nhelper_sha256=%s\npayload_name=%s\npayload_sha256=%s\npayload_bytes=%s\ncandidate_review_manifest_sha256=%s\ncandidate_signoff_manifest_sha256=%s\n' \
    "$NODE" "$EXPECTED_SERIAL" "$EXPECTED_BOOT_ID" "$TOKEN" "$$" "$TOKEN" "$SECONDS_LIMIT" "$watchdog_sha" "$HELPER_SHA" "$PAYLOAD_NAME" "$PAYLOAD_SHA" "$PAYLOAD_BYTES" "$CANDIDATE_REVIEW_MANIFEST_SHA" "$CANDIDATE_SIGNOFF_MANIFEST_SHA" > "$ack_tmp" || exit 5
mv "$ack_tmp" "$ack" || exit 5
[ "$(sed -n '1p' "$ack")" = schema=rx12.major13-volatile-load-recovery.v1 ] || exit 5

elapsed=0
while [ "$elapsed" -lt "$SECONDS_LIMIT" ]; do
    if [ -r "$terminal" ] && \
       [ "$(sed -n '1p' "$terminal")" = result=PASS ] && \
       [ "$(grep -c "^token=${TOKEN}$" "$terminal" 2>/dev/null)" = 1 ] && \
       [ "$(grep -c "^helper_sha256=${HELPER_SHA}$" "$terminal" 2>/dev/null)" = 1 ] && \
       [ "$(grep -c "^node=${NODE}$" "$terminal" 2>/dev/null)" = 1 ] && \
       [ "$(grep -c "^device_serial=${EXPECTED_SERIAL}$" "$terminal" 2>/dev/null)" = 1 ] && \
       [ "$(grep -c "^device_boot_id=${EXPECTED_BOOT_ID}$" "$terminal" 2>/dev/null)" = 1 ] && \
       [ "$(grep -c '^volatile_fpga_load=YES$' "$terminal" 2>/dev/null)" = 1 ] && \
       [ "$(grep -c '^candidate_payload=YES$' "$terminal" 2>/dev/null)" = 1 ] && \
       [ "$(grep -c '^firmware_attr_write_completed=1$' "$terminal" 2>/dev/null)" = 1 ] && \
       [ "$(grep -c '^manager_operating_after_load=1$' "$terminal" 2>/dev/null)" = 1 ] && \
       [ "$(grep -c '^bind_writes_started=1$' "$terminal" 2>/dev/null)" = 1 ] && \
       [ "$(grep -c "^pre_version=${EXPECTED_PRE_VERSION}$" "$terminal" 2>/dev/null)" = 1 ] && \
       [ "$(grep -c "^post_version=${EXPECTED_POST_VERSION}$" "$terminal" 2>/dev/null)" = 1 ] && \
       [ "$(grep -c "^ps_fclk3_pre=${PS_FCLK3_VALUE}$" "$terminal" 2>/dev/null)" = 1 ] && \
       [ "$(grep -c "^ps_fclk3_post=${PS_FCLK3_VALUE}$" "$terminal" 2>/dev/null)" = 1 ] && \
       [ "$(grep -c "^ps_io_pll_pre=${PS_IO_PLL_VALUE}$" "$terminal" 2>/dev/null)" = 1 ] && \
       [ "$(grep -c "^ps_io_pll_post=${PS_IO_PLL_VALUE}$" "$terminal" 2>/dev/null)" = 1 ] && \
       [ "$(grep -c "^payload_name=${PAYLOAD_NAME}$" "$terminal" 2>/dev/null)" = 1 ] && \
       [ "$(grep -c "^payload_sha256=${PAYLOAD_SHA}$" "$terminal" 2>/dev/null)" = 1 ] && \
       [ "$(grep -c "^payload_bytes=${PAYLOAD_BYTES}$" "$terminal" 2>/dev/null)" = 1 ] && \
       [ "$(grep -c "^candidate_review_manifest_sha256=${CANDIDATE_REVIEW_MANIFEST_SHA}$" "$terminal" 2>/dev/null)" = 1 ] && \
       [ "$(grep -c "^candidate_signoff_manifest_sha256=${CANDIDATE_SIGNOFF_MANIFEST_SHA}$" "$terminal" 2>/dev/null)" = 1 ] && \
       [ "$(grep -c '^no_rf=YES$' "$terminal" 2>/dev/null)" = 1 ]; then
        result_tmp="${result}.$$"
        printf 'result=DISARMED_ON_EXACT_PASS\ntoken=%s\nelapsed_seconds=%s\n' "$TOKEN" "$elapsed" > "$result_tmp" || exit 6
        mv "$result_tmp" "$result" || exit 6
        exit 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

result_tmp="${result}.$$"
printf 'result=TIMEOUT_REBOOT_REQUESTED\ntoken=%s\nelapsed_seconds=%s\ndevice_reboot=/usr/sbin/device_reboot reset\n' \
    "$TOKEN" "$elapsed" > "$result_tmp" 2>/dev/null && mv "$result_tmp" "$result" 2>/dev/null || true
"$(p /usr/sbin/device_reboot)" reset
reboot_rc=$?
printf 'result=DEVICE_REBOOT_RETURNED\ntoken=%s\nexit_code=%s\n' "$TOKEN" "$reboot_rc" > "${result}.returned" || true
exit 8
