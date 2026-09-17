#!/bin/sh
# Device-local ED4 RX-DMA major-13 fleet volatile FPGA-load and PL driver/service rebind canary.

set -u
umask 077

PL_BINDINGS_SHA=829ec5134f04274f1aa08d689c0a48eeaf3c906462ca76a824efa69b8ddaf625
SERVICES_SHA=13700075c18ecbb6c6fab486d23dbfa080309be560b75f240763bcb0320926ff
BIND_ATTRS_SHA=bcb6368a9159f4a9b5620a777f9581dd4388f57bd54d6ae78131f35b12045dc2
EXPECTED_PRE_VERSION=0x000CDFFF
EXPECTED_POST_VERSION=0x000DDFFF
PS_FCLK3_REG=0xF80001A0
PS_FCLK3_VALUE=0x00300400
PS_IO_PLL_REG=0xF8000108
PS_IO_PLL_VALUE=0x0001E000
EXPECTED_UDC=ci_hdrc.0
NODE=ed4
NODE_UPPER=ED4
EXPECTED_SERIAL=10447318ac0f0011fcff34002b8c17c89d
EXPECTED_BOOT_ID=944f1b77-dac2-4049-9a64-f80705217b96
PAYLOAD_NAME=system_top_major13.bit.bin
PAYLOAD_SHA=b33569b289fe3c8feaa09e40f41076862e1297c46dd1f85972305593bc646b59
PAYLOAD_BYTES=2083744
CANDIDATE_REVIEW_MANIFEST_SHA=fea1580f7f1bb25ae1217753012fda2c05ecc41a84cc6539605692e4a924501b
CANDIDATE_SOURCE_MANIFEST_SHA=96e8ad4fb6af3c846ee352bdc0a66f0cda81f65d4520c103e13433be64f7d29b
CANDIDATE_XDC_SHA=db07cdfecc48587f8d0b296d2ff492adca26c3cb9d409195696326e68f2381cb
CANDIDATE_ROUTED_DCP_SHA=314f34062da8fd736a40906a5cb178b53a1b3ca08c0899cdb39b6f7fa1f8ac8c
CANDIDATE_SIGNOFF_MANIFEST_SHA=dc5ad5009c7272b8d506dda074b7d47f730ab1ab69c99a5d86b8901a9de54e02
CANDIDATE_BIT_SHA=495034db17d4ca93ac15074212bc7f2d0f38390b2062899c3d040c7c13d69193
TRANSITION_INVENTORY_SHA=b30715841a1f13dd71162d37765a7f91f1297a4ab19be68310eb7045f8e94eb6
TRANSITION_SNAPSHOT_SHA=55b8f1f2bac2e9f790eecf77f9aa8c6d27fef5012c9b2878cb75cf7c280f2013

MODE=
INPUT=
WATCHDOG=
RECOVERY_ACK=
JOURNAL=
TOKEN=
JOURNAL_READY=0
CHANGES_STARTED=0
LOAD_WRITTEN=0
LOAD_OPERATING=0
BIND_WRITES_STARTED=0
TEST_ROOT=${ARC3_TEST_ROOT:-}

if [ -n "$TEST_ROOT" ] && [ "${ARC3_TEST_MODE:-0}" != 1 ]; then
    echo "ARC3_REBIND_REFUSE test root requires ARC3_TEST_MODE=1" >&2
    exit 90
fi

p() {
    printf '%s%s' "$TEST_ROOT" "$1"
}

usage() {
    cat <<'EOF'
Usage:
  rx12_v13_ed4_load.sh --plan
  rx12_v13_ed4_load.sh --preflight --input /tmp/INPUT --watchdog SCRIPT
  rx12_v13_ed4_load.sh --execute --input /tmp/INPUT --watchdog SCRIPT \
      --recovery-ack /tmp/ACK

--plan prints the fixed candidate-payload sequence and performs no device reads or writes.
--preflight performs read-only checks and makes no filesystem/sysfs/service writes.
--execute is the only mode that creates a RAM journal or changes USB/drivers/services.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --plan|--preflight|--execute)
            [ -z "$MODE" ] || { echo "ARC3_REBIND_REFUSE choose one mode" >&2; exit 2; }
            MODE=${1#--}
            shift
            ;;
        --input)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            INPUT=$2
            shift 2
            ;;
        --watchdog)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            WATCHDOG=$2
            shift 2
            ;;
        --recovery-ack)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            RECOVERY_ACK=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ARC3_REBIND_REFUSE unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ "$MODE" = plan ]; then
    cat <<'EOF'
RX12_MAJOR13_ED4_LOAD_PLAN_V1
scope=exact RX-DMA major-13 canary volatile FPGA load; no RF; no persistent write; payload hash-bound
preconditions=ED4 identity; reviewed hashes; backup acknowledgement; recovery artifact; VERSION 0x000CDFFF; manager operating; exact five bindings; buffers 0; SPI bound; no ED/ES or UIO/IIO users; USB links intact; exact iiod
usb_detach=clear composite_gadget/UDC; stop exact pidfile/executable iiod
unbind=UIO,DDS,ADC,RX_DMA,TX_DMA
fpga_load=verify flags 0 and manager operating; hash exact fixed payload; write only its basename to fpga0/firmware; require manager operating before any rebind
bind=RX_DMA,TX_DMA,DDS,ADC,UIO
postbind=rediscover unique IIO names; buffers 0; four DDS scales/frequencies 0; record actual sample rates without preservation claim; DMA links; unique uio0 aircomp; VERSION; five bindings; manager; SPI; retain full dmesg delta and reject only declared fatal/deferred/probe-error patterns
usb_attach=start /usr/sbin/iiod -D -n 3 -F /dev/iio_ffs with observed start-stop-daemon; prove FunctionFS descriptors; write ci_hdrc.0; require configured
terminal=PASS only after exact candidate VERSION 0x000DDFFF returns and all checks pass; any failure after detach relies on separately armed /usr/sbin/device_reboot reset watchdog; no rerun
EOF
    exit 0
fi

[ "$MODE" = preflight ] || [ "$MODE" = execute ] || { usage >&2; exit 2; }
[ -n "$INPUT" ] && [ -n "$WATCHDOG" ] || { echo "ARC3_REBIND_REFUSE --input and --watchdog required" >&2; exit 2; }
case "$INPUT" in
    /tmp/*|/run/*) ;;
    *) echo "ARC3_REBIND_REFUSE input must be staged in RAM under /tmp or /run" >&2; exit 2 ;;
esac

log() {
    message=$1
    if [ "$JOURNAL_READY" -eq 1 ]; then
        printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$message" >> "$JOURNAL/events.log" || {
            echo "ARC3_REBIND_FAIL journal_append_failed" >&2
            exit 73
        }
    fi
    printf '%s\n' "$message"
}

atomic_terminal() {
    result=$1
    code=$2
    reason=$3
    temp="$JOURNAL/.terminal_result.$$"
    rm -f "$temp"
    printf 'result=%s\ncode=%s\nreason=%s\nchanges_started=%s\nfirmware_attr_write_completed=%s\nmanager_operating_after_load=%s\nbind_writes_started=%s\ntoken=%s\nhelper_sha256=%s\nnode=ed4\ndevice_serial=10447318ac0f0011fcff34002b8c17c89d\ndevice_boot_id=944f1b77-dac2-4049-9a64-f80705217b96\nscope=rx12_major12_to_major13_volatile_fpga_load_no_rf\npre_version=%s\npost_version=%s\nps_fclk3_pre=%s\nps_fclk3_post=%s\nps_io_pll_pre=%s\nps_io_pll_post=%s\nexpected_bindings=5\nvolatile_fpga_load=YES\ncandidate_payload=YES\npayload_name=%s\npayload_sha256=%s\npayload_bytes=%s\ncandidate_review_manifest_sha256=%s\ncandidate_source_manifest_sha256=%s\ncandidate_xdc_sha256=%s\ncandidate_routed_dcp_sha256=%s\ncandidate_signoff_manifest_sha256=%s\ncandidate_bit_sha256=%s\ntransition_inventory_manifest_sha256=%s\ntransition_inventory_snapshot_sha256=%s\nno_rf=YES\n' \
        "$result" "$code" "$reason" "$CHANGES_STARTED" "$LOAD_WRITTEN" "$LOAD_OPERATING" "$BIND_WRITES_STARTED" "$TOKEN" "${HELPER_SHA:-unknown}" \
        "$EXPECTED_PRE_VERSION" "$EXPECTED_POST_VERSION" "$PS_FCLK3_VALUE" "$PS_FCLK3_VALUE" "$PS_IO_PLL_VALUE" "$PS_IO_PLL_VALUE" "$PAYLOAD_NAME" "$PAYLOAD_SHA" "$PAYLOAD_BYTES" "$CANDIDATE_REVIEW_MANIFEST_SHA" "$CANDIDATE_SOURCE_MANIFEST_SHA" "$CANDIDATE_XDC_SHA" "$CANDIDATE_ROUTED_DCP_SHA" "$CANDIDATE_SIGNOFF_MANIFEST_SHA" "$CANDIDATE_BIT_SHA" "$TRANSITION_INVENTORY_SHA" "$TRANSITION_SNAPSHOT_SHA" > "$temp" || return 1
    mv "$temp" "$JOURNAL/terminal_result" || return 1
    [ "$(sed -n '1p' "$JOURNAL/terminal_result")" = "result=$result" ] || return 1
    [ "$(grep -c '^token=' "$JOURNAL/terminal_result")" = 1 ] || return 1
    return 0
}

terminal_fail() {
    code=$1
    reason=$2
    if [ "$JOURNAL_READY" -eq 1 ] && [ ! -e "$JOURNAL/terminal_result" ]; then
        atomic_terminal FAIL "$code" "$reason" || echo "ARC3_REBIND_FAIL terminal_fail_marker_failed" >&2
        printf '%s\n' "$reason" > "$JOURNAL/failure_reason" || true
    fi
    echo "ARC3_REBIND_FAIL code=$code reason=$reason journal=${JOURNAL:-none}" >&2
    exit "$code"
}

refuse() {
    terminal_fail "$1" "$2"
}

mark() {
    number=$1
    name=$2
    printf 'stage=%s\nname=%s\nutc=%s\n' "$number" "$name" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        > "$JOURNAL/stage_${number}_${name}.done" || terminal_fail 74 "stage_marker_${number}_write_failed"
    log "STAGE_DONE $number $name"
}

kv() {
    key=$1
    file=$2
    count=$(grep -c "^${key}=" "$file" 2>/dev/null || true)
    [ "$count" = 1 ] || return 1
    grep "^${key}=" "$file" | sed -n '1s/^[^=]*=//p'
}

need_kv() {
    NK_VALUE=$(kv "$1" "$2") || refuse "$3" "input_${1}_must_appear_once"
}

is_sha() {
    case "$1" in
        *[!0-9a-f]*|'') return 1 ;;
    esac
    [ "${#1}" -eq 64 ]
}

require_tool() {
    command -v "$1" >/dev/null 2>&1 || refuse 11 "required_tool_missing_$1"
}

pid_alive() {
    pid=$1
    case "$pid" in *[!0-9]*|'') return 1 ;; esac
    if [ -n "$TEST_ROOT" ]; then
        [ -d "$(p /proc)/$pid" ]
    else
        kill -0 "$pid" 2>/dev/null
    fi
}

proc_exe() {
    readlink "$(p /proc)/$1/exe" 2>/dev/null || true
}

proc_cmdline() {
    tr '\000' ' ' < "$(p /proc)/$1/cmdline" 2>/dev/null | sed 's/[[:space:]]*$//'
}

require_exact_iiod() {
    pidfile=$(p /var/run/iiod.pid)
    [ -r "$pidfile" ] || refuse 12 "iiod_pidfile_missing"
    pid=$(cat "$pidfile")
    pid_alive "$pid" || refuse 12 "iiod_pid_not_alive"
    [ "$(proc_exe "$pid")" = /usr/sbin/iiod ] || refuse 12 "iiod_executable_mismatch"
    [ "$(proc_cmdline "$pid")" = "/usr/sbin/iiod -D -n 3 -F /dev/iio_ffs" ] || \
        refuse 12 "iiod_argv_mismatch"
}

binding_target() {
    readlink -f "$(p /sys/bus/platform/devices)/$1/driver" 2>/dev/null || true
}

require_binding() {
    dev=$1
    driver=$2
    target=$(binding_target "$dev")
    [ "${target##*/}" = "$driver" ] || refuse 13 "binding_${dev}_expected_${driver}"
}

require_no_binding() {
    dev=$1
    [ ! -L "$(p /sys/bus/platform/devices)/$dev/driver" ] || refuse 31 "unbind_${dev}_still_bound"
}

discover_iio() {
    wanted=$1
    found=
    count=0
    for path in "$(p /sys/bus/iio/devices)"/iio:device*; do
        [ -r "$path/name" ] || continue
        if [ "$(cat "$path/name")" = "$wanted" ]; then
            found=$path
            count=$((count + 1))
        fi
    done
    [ "$count" -eq 1 ] || refuse 14 "iio_${wanted}_count_${count}"
    printf '%s\n' "$found"
}

require_iio_topology() {
    PHY_IIO=$(discover_iio ad9361-phy) || exit $?
    DDS_IIO=$(discover_iio cf-ad9361-dds-core-lpc) || exit $?
    ADC_IIO=$(discover_iio cf-ad9361-lpc) || exit $?
    [ "$(cat "$DDS_IIO/buffer/enable" 2>/dev/null)" = 0 ] || refuse 14 "dds_buffer_not_zero"
    [ "$(cat "$ADC_IIO/buffer/enable" 2>/dev/null)" = 0 ] || refuse 14 "adc_buffer_not_zero"
    DDS_CHAR="$(p /dev)/${DDS_IIO##*/}"
    ADC_CHAR="$(p /dev)/${ADC_IIO##*/}"
    [ -e "$DDS_CHAR" ] && [ -e "$ADC_CHAR" ] || refuse 14 "iio_character_device_missing"
}

require_no_waveform() {
    scale_count=0
    frequency_count=0
    for attr in "$DDS_IIO"/out_altvoltage[0-9]*_scale; do
        [ -r "$attr" ] || continue
        [ "$(cat "$attr")" = 0.000000 ] || refuse 14 "dds_scale_${attr##*/}_not_zero"
        scale_count=$((scale_count + 1))
    done
    for attr in "$DDS_IIO"/out_altvoltage[0-9]*_frequency; do
        [ -r "$attr" ] || continue
        [ "$(cat "$attr")" = 0 ] || refuse 14 "dds_frequency_${attr##*/}_not_zero"
        frequency_count=$((frequency_count + 1))
    done
    [ "$scale_count" -eq 4 ] || refuse 14 "dds_zero_scale_count_${scale_count}"
    [ "$frequency_count" -eq 4 ] || refuse 14 "dds_zero_frequency_count_${frequency_count}"
}

record_iio_posthealth() {
    {
        printf 'dds_buffer_enable=%s\n' "$(cat "$DDS_IIO/buffer/enable")"
        printf 'adc_buffer_enable=%s\n' "$(cat "$ADC_IIO/buffer/enable")"
        for attr in "$DDS_IIO"/out_altvoltage[0-9]*_scale "$DDS_IIO"/out_altvoltage[0-9]*_frequency; do
            [ -r "$attr" ] || continue
            printf '%s=%s\n' "${attr##*/}" "$(cat "$attr")"
        done
        for attr in "$DDS_IIO"/out_altvoltage_sampling_frequency "$DDS_IIO"/out_voltage*_sampling_frequency "$ADC_IIO"/in_voltage*_sampling_frequency; do
            [ -r "$attr" ] || continue
            printf '%s/%s=%s\n' "${attr%/*}" "${attr##*/}" "$(cat "$attr")"
        done
        printf 'sample_rate_policy=observed_only_round_must_reapply_and_verify_5000000\n'
    } > "$JOURNAL/iio_posthealth.txt" || refuse 47 "iio_posthealth_record_failed"
}

require_dma_links() {
    rx=$(readlink -f "$(p /sys/bus/platform/devices)/79020000.cf-ad9361-lpc/dma:rx" 2>/dev/null || true)
    tx=$(readlink -f "$(p /sys/bus/platform/devices)/79024000.cf-ad9361-dds-core-lpc/dma:tx" 2>/dev/null || true)
    case "$rx" in *7c400000.dma*) ;; *) refuse 15 "rx_dma_link_mismatch" ;; esac
    case "$tx" in *7c420000.dma*) ;; *) refuse 15 "tx_dma_link_mismatch" ;; esac
}

discover_uio() {
    found=
    count=0
    for path in "$(p /sys/class/uio)"/uio*; do
        [ -r "$path/name" ] || continue
        if [ "$(cat "$path/name")" = aircomp ]; then
            found=$path
            count=$((count + 1))
        fi
    done
    [ "$count" -eq 1 ] || refuse 16 "aircomp_uio_count_${count}"
    [ "${found##*/}" = uio0 ] || refuse 16 "aircomp_not_uio0"
    target=$(readlink -f "$found/device" 2>/dev/null || true)
    case "$target" in *7c480000.aircomp*) ;; *) refuse 16 "aircomp_uio_device_mismatch" ;; esac
    UIO_CHAR=$(p /dev/uio0)
    [ -e "$UIO_CHAR" ] || refuse 16 "uio0_character_device_missing"
}

require_version() {
    expected=$1
    value=$(devmem 0x7c480000 32 2>/dev/null || true)
    [ "$value" = "$expected" ] || refuse 17 "version_${value:-unreadable}_expected_${expected}"
}

require_ps_clocks() {
    label=$1
    fclk3=$(devmem "$PS_FCLK3_REG" 32 2>/dev/null || true)
    io_pll=$(devmem "$PS_IO_PLL_REG" 32 2>/dev/null || true)
    [ "$fclk3" = "$PS_FCLK3_VALUE" ] || refuse 17 "ps_fclk3_${label}_${fclk3:-unreadable}_expected_${PS_FCLK3_VALUE}"
    [ "$io_pll" = "$PS_IO_PLL_VALUE" ] || refuse 17 "ps_io_pll_${label}_${io_pll:-unreadable}_expected_${PS_IO_PLL_VALUE}"
    if [ "$JOURNAL_READY" -eq 1 ]; then
        printf 'ps_fclk3_reg=%s
ps_fclk3_value=%s
ps_io_pll_reg=%s
ps_io_pll_value=%s
'             "$PS_FCLK3_REG" "$fclk3" "$PS_IO_PLL_REG" "$io_pll" > "$JOURNAL/ps_clocks_${label}.txt" ||             refuse 17 "ps_clock_${label}_record_failed"
    fi
}

require_manager() {
    [ "$(cat "$(p /sys/class/fpga_manager/fpga0/state)" 2>/dev/null)" = operating ] || \
        refuse 18 "fpga_manager_not_operating"
}

require_manager_flags_zero() {
    [ "$(cat "$(p /sys/class/fpga_manager/fpga0/flags)" 2>/dev/null)" = 0 ] || \
        refuse 18 "fpga_manager_flags_not_zero"
}

require_fixed_payload() {
    rootfs_count=$(awk '$2 == "/" && $3 == "rootfs" {n++} END {print n+0}' "$(p /proc/mounts)")
    [ "$rootfs_count" -eq 1 ] || refuse 18 "root_filesystem_not_unique_rootfs"
    persistent_lib_mounts=$(awk '$2 == "/lib" || $2 == "/lib/firmware" {n++} END {print n+0}' "$(p /proc/mounts)")
    [ "$persistent_lib_mounts" -eq 0 ] || refuse 18 "lib_firmware_has_separate_mount"
    [ "$(readlink -f "$(p /lib/firmware)" 2>/dev/null)" = "$(p /lib/firmware)" ] || \
        refuse 18 "lib_firmware_resolves_elsewhere"
    PAYLOAD_PATH="$(p /lib/firmware)/$PAYLOAD_NAME"
    [ -f "$PAYLOAD_PATH" ] && [ -r "$PAYLOAD_PATH" ] || refuse 18 "fixed_candidate_payload_missing"
    [ "$(wc -c < "$PAYLOAD_PATH")" -eq "$PAYLOAD_BYTES" ] || refuse 18 "fixed_candidate_payload_size_mismatch"
    [ "$(sha256sum "$PAYLOAD_PATH" | awk '{print $1}')" = "$PAYLOAD_SHA" ] || \
        refuse 18 "fixed_candidate_payload_hash_mismatch"
    [ -w "$(p /sys/class/fpga_manager/fpga0/firmware)" ] || refuse 18 "fpga_firmware_attribute_not_writable"
    mem_available_kb=$(awk '$1 == "MemAvailable:" {print $2}' "$(p /proc/meminfo)")
    case "$mem_available_kb" in *[!0-9]*|'') refuse 18 "memavailable_unreadable" ;; esac
    [ "$mem_available_kb" -gt $((PAYLOAD_BYTES / 1024)) ] || refuse 18 "memavailable_not_above_payload"
}

wait_manager_operating_after_load() {
    n=0
    state_path=$(p /sys/class/fpga_manager/fpga0/state)
    while :; do
        manager_state=$(cat "$state_path" 2>/dev/null || true)
        case "$manager_state" in
            operating) return 0 ;;
            "write init"|write) ;;
            *) refuse 46 "fpga_manager_state_${manager_state:-unreadable}_after_load" ;;
        esac
        n=$((n + 1))
        [ "$n" -le 30 ] || refuse 46 "fpga_manager_load_timeout"
        sleep 1
    done
}

require_spi_bound() {
    path=$(p /sys/bus/spi/devices/spi0.0/driver)
    [ -L "$path" ] || refuse 19 "spi0_0_unbound"
    current=$(readlink -f "$path")
    if [ -n "${SPI_DRIVER_BASELINE:-}" ]; then
        [ "$current" = "$SPI_DRIVER_BASELINE" ] || refuse 19 "spi0_0_driver_changed"
    else
        SPI_DRIVER_BASELINE=$current
    fi
}

require_no_ed_es() {
    pidof aircomp_ed >/dev/null 2>&1 && refuse 20 "aircomp_ed_active"
    pidof aircomp_es >/dev/null 2>&1 && refuse 20 "aircomp_es_active"
}

require_no_suspend_helper() {
    [ ! -e "$(p /var/run/udc_handle_suspend.pid)" ] || refuse 21 "suspend_helper_pidfile_present"
    for cmd in "$(p /proc)"/[0-9]*/cmdline; do
        [ -r "$cmd" ] || continue
        tr '\000' ' ' < "$cmd" 2>/dev/null | grep -F '/sbin/udc_handle_suspend.sh' >/dev/null 2>&1 && \
            refuse 21 "suspend_helper_process_present"
    done
}

require_usb_layout() {
    gadget=$(p /sys/kernel/config/usb_gadget/composite_gadget)
    [ -d "$gadget/configs/c.1" ] || refuse 22 "usb_config_missing"
    [ "$(cat "$gadget/UDC" 2>/dev/null)" = "$EXPECTED_UDC" ] || refuse 22 "udc_not_ci_hdrc_0"
    [ -w "$gadget/UDC" ] || refuse 22 "udc_attribute_not_writable"
    for name in ffs.iio_ffs acm.usb0 mass_storage.0; do
        [ -L "$gadget/configs/c.1/$name" ] || refuse 22 "usb_link_${name}_missing"
    done
    net_count=0
    for name in rndis.0 ecm.usb0 ncm.usb0; do
        [ -L "$gadget/configs/c.1/$name" ] && net_count=$((net_count + 1))
    done
    [ "$net_count" -eq 1 ] || refuse 22 "usb_network_link_count_${net_count}"
    grep -q ' /dev/iio_ffs functionfs ' "$(p /proc/mounts)" || refuse 22 "iio_functionfs_not_mounted"
    [ "$(cat "$(p /sys/class/udc/ci_hdrc.0/state)" 2>/dev/null)" = configured ] || \
        refuse 22 "udc_initial_state_not_configured"
}

usb_link_snapshot() {
    gadget=$(p /sys/kernel/config/usb_gadget/composite_gadget)
    for link in "$gadget/configs/c.1"/*; do
        [ -L "$link" ] || continue
        printf '%s=%s\n' "${link##*/}" "$(readlink "$link")"
    done | sort
}

require_no_device_users() {
    targets="$UIO_CHAR $DDS_CHAR $ADC_CHAR"
    output=$("$(p /usr/bin/fuser)" $targets 2>&1 || true)
    [ -z "$output" ] || refuse 23 "fuser_reports_device_user"
    for fd in "$(p /proc)"/[0-9]*/fd/*; do
        [ -L "$fd" ] || continue
        target=$(readlink "$fd" 2>/dev/null || true)
        for dev in $targets; do
            [ "$target" != "$dev" ] || refuse 23 "open_fd_${fd}_to_${dev}"
        done
    done
    for maps in "$(p /proc)"/[0-9]*/maps; do
        [ -r "$maps" ] || continue
        grep -F "$UIO_CHAR" "$maps" >/dev/null 2>&1 && refuse 23 "uio_mapping_${maps}"
    done
}

require_driver_attrs() {
    for driver in uio_pdrv_genirq cf_axi_dds cf_axi_adc dma-axi-dmac; do
        [ -w "$(p /sys/bus/platform/drivers)/$driver/bind" ] || refuse 24 "${driver}_bind_not_writable"
        [ -w "$(p /sys/bus/platform/drivers)/$driver/unbind" ] || refuse 24 "${driver}_unbind_not_writable"
    done
}

write_driver() {
    action=$1
    driver=$2
    dev=$3
    attr="$(p /sys/bus/platform/drivers)/$driver/$action"
    printf '%s\n' "$dev" > "$attr" || refuse 30 "${action}_${dev}_write_failed"
    if [ -n "$TEST_ROOT" ]; then
        devdir="$(p /sys/bus/platform/devices)/$dev"
        if [ "$action" = unbind ]; then
            rm -f "$devdir/driver" "$devdir/dma:rx" "$devdir/dma:tx"
        else
            ln -s "$(p /sys/bus/platform/drivers)/$driver" "$devdir/driver" || refuse 30 "mock_bind_${dev}_failed"
            if [ "$dev" = 79020000.cf-ad9361-lpc ]; then
                ln -s "$(p /sys/devices/7c400000.dma/dma0chan0)" "$devdir/dma:rx" || refuse 30 "mock_rx_dma_link_failed"
            elif [ "$dev" = 79024000.cf-ad9361-dds-core-lpc ]; then
                ln -s "$(p /sys/devices/7c420000.dma/dma0chan0)" "$devdir/dma:tx" || refuse 30 "mock_tx_dma_link_failed"
            fi
        fi
    fi
}

wait_pid_gone() {
    pid=$1
    n=0
    while pid_alive "$pid"; do
        n=$((n + 1))
        [ "$n" -le 10 ] || refuse 32 "iiod_did_not_exit"
        sleep 1
    done
}

wait_iiod_ready() {
    n=0
    while :; do
        pidfile=$(p /var/run/iiod.pid)
        if [ -r "$pidfile" ]; then
            pid=$(cat "$pidfile")
            if pid_alive "$pid" && [ "$(proc_exe "$pid")" = /usr/sbin/iiod ] && \
               [ "$(proc_cmdline "$pid")" = "/usr/sbin/iiod -D -n 3 -F /dev/iio_ffs" ]; then
                ready=0
                for fd in "$(p /proc)/$pid"/fd/*; do
                    [ -L "$fd" ] || continue
                    case "$(readlink "$fd" 2>/dev/null || true)" in /dev/iio_ffs/*) ready=1 ;; esac
                done
                [ "$ready" -eq 1 ] && return 0
            fi
        fi
        n=$((n + 1))
        [ "$n" -le 10 ] || refuse 33 "iiod_functionfs_not_ready"
        sleep 1
    done
}

wait_udc_configured() {
    n=0
    state_path=$(p /sys/class/udc/ci_hdrc.0/state)
    while [ "$(cat "$state_path" 2>/dev/null)" != configured ]; do
        n=$((n + 1))
        [ "$n" -le 30 ] || refuse 34 "udc_not_configured_after_attach"
        sleep 1
    done
}

validate_inputs() {
    [ -r "$(p "$INPUT")" ] || refuse 10 "input_file_missing"
    INPUT=$(p "$INPUT")
    need_kv schema "$INPUT" 10; [ "$NK_VALUE" = rx12.major13-volatile-load-input.v1 ] || refuse 10 "input_schema"
    need_kv node "$INPUT" 10; [ "$NK_VALUE" = ed4 ] || refuse 10 "input_node"
    need_kv scope "$INPUT" 10; [ "$NK_VALUE" = rx12_major12_to_major13_volatile_fpga_load_no_rf ] || refuse 10 "input_scope"
    need_kv operator_reviewed "$INPUT" 10; [ "$NK_VALUE" = YES ] || refuse 10 "operator_review_missing"
    need_kv volatile_fpga_load "$INPUT" 10; [ "$NK_VALUE" = YES ] || refuse 10 "volatile_fpga_load_ack_missing"
    need_kv candidate_payload "$INPUT" 10; [ "$NK_VALUE" = YES ] || refuse 10 "candidate_payload_ack_missing"
    need_kv payload_name "$INPUT" 10; [ "$NK_VALUE" = "$PAYLOAD_NAME" ] || refuse 10 "payload_name_not_fixed_candidate"
    need_kv payload_sha256 "$INPUT" 10; [ "$NK_VALUE" = "$PAYLOAD_SHA" ] || refuse 10 "payload_hash_not_fixed_candidate"
    need_kv payload_bytes "$INPUT" 10; [ "$NK_VALUE" = "$PAYLOAD_BYTES" ] || refuse 10 "payload_size_not_fixed_candidate"
    need_kv candidate_review_manifest_sha256 "$INPUT" 10; [ "$NK_VALUE" = "$CANDIDATE_REVIEW_MANIFEST_SHA" ] || refuse 10 "candidate_review_manifest_hash"
    need_kv candidate_source_manifest_sha256 "$INPUT" 10; [ "$NK_VALUE" = "$CANDIDATE_SOURCE_MANIFEST_SHA" ] || refuse 10 "candidate_source_manifest_hash"
    need_kv candidate_xdc_sha256 "$INPUT" 10; [ "$NK_VALUE" = "$CANDIDATE_XDC_SHA" ] || refuse 10 "candidate_xdc_hash"
    need_kv candidate_routed_dcp_sha256 "$INPUT" 10; [ "$NK_VALUE" = "$CANDIDATE_ROUTED_DCP_SHA" ] || refuse 10 "candidate_routed_dcp_hash"
    need_kv candidate_signoff_manifest_sha256 "$INPUT" 10; [ "$NK_VALUE" = "$CANDIDATE_SIGNOFF_MANIFEST_SHA" ] || refuse 10 "candidate_signoff_manifest_hash"
    need_kv candidate_bit_sha256 "$INPUT" 10; [ "$NK_VALUE" = "$CANDIDATE_BIT_SHA" ] || refuse 10 "candidate_bit_hash"
    need_kv transition_inventory_manifest_sha256 "$INPUT" 10
    [ "$NK_VALUE" = "$TRANSITION_INVENTORY_SHA" ] || refuse 10 "prior_no_load_result_hash"
    need_kv transition_inventory_snapshot_sha256 "$INPUT" 10
    [ "$NK_VALUE" = "$TRANSITION_SNAPSHOT_SHA" ] || refuse 10 "prior_no_load_archive_hash"
    need_kv pl_bindings_inventory_sha256 "$INPUT" 10
    [ "$NK_VALUE" = "$PL_BINDINGS_SHA" ] || refuse 10 "pl_inventory_hash"
    need_kv services_inventory_sha256 "$INPUT" 10
    [ "$NK_VALUE" = "$SERVICES_SHA" ] || refuse 10 "services_inventory_hash"
    need_kv bind_attrs_inventory_sha256 "$INPUT" 10
    [ "$NK_VALUE" = "$BIND_ATTRS_SHA" ] || refuse 10 "bind_attrs_inventory_hash"
    need_kv backup_manifest_sha256 "$INPUT" 10; BACKUP_SHA=$NK_VALUE
    is_sha "$BACKUP_SHA" || refuse 10 "backup_ack_hash_invalid"
    need_kv load_token "$INPUT" 10; TOKEN=$NK_VALUE
    case "$TOKEN" in *[!A-Za-z0-9_-]*|'') refuse 10 "load_token_invalid" ;; esac
    [ "${#TOKEN}" -ge 12 ] && [ "${#TOKEN}" -le 64 ] || refuse 10 "load_token_length"
    need_kv device_serial "$INPUT" 10; SERIAL=$NK_VALUE
    [ "$SERIAL" = "$EXPECTED_SERIAL" ] || refuse 10 "device_serial_not_fixed_node"
    [ "$(cat "$(p /etc/serial)" 2>/dev/null)" = "$SERIAL" ] || refuse 10 "device_serial_mismatch"
    need_kv device_boot_id "$INPUT" 10; [ "$NK_VALUE" = "$EXPECTED_BOOT_ID" ] || refuse 10 "device_boot_id_not_fixed_node"
    [ "$(cat "$(p /proc/sys/kernel/random/boot_id)" 2>/dev/null)" = "$EXPECTED_BOOT_ID" ] || refuse 10 "device_boot_id_mismatch"
    need_kv helper_sha256 "$INPUT" 10; HELPER_SHA=$NK_VALUE
    need_kv watchdog_sha256 "$INPUT" 10; WATCHDOG_SHA=$NK_VALUE
    need_kv watchdog_seconds "$INPUT" 10; WATCHDOG_SECONDS=$NK_VALUE
    case "$WATCHDOG_SECONDS" in *[!0-9]*|'') refuse 10 "watchdog_seconds_invalid" ;; esac
    [ "$WATCHDOG_SECONDS" -ge 60 ] && [ "$WATCHDOG_SECONDS" -le 300 ] || \
        refuse 10 "watchdog_seconds_out_of_range"
    is_sha "$HELPER_SHA" && is_sha "$WATCHDOG_SHA" || refuse 10 "helper_hash_invalid"
    [ "$(sha256sum "$0" | awk '{print $1}')" = "$HELPER_SHA" ] || refuse 10 "helper_hash_mismatch"
    [ -r "$WATCHDOG" ] || refuse 10 "watchdog_script_missing"
    [ "$(sha256sum "$WATCHDOG" | awk '{print $1}')" = "$WATCHDOG_SHA" ] || refuse 10 "watchdog_hash_mismatch"
    JOURNAL="$(p /tmp)/rx12_v13_ed4_load_${TOKEN}"
    [ ! -e "$JOURNAL" ] || refuse 10 "journal_token_already_used"
}

validate_recovery_ack() {
    [ -n "$RECOVERY_ACK" ] || refuse 25 "live_recovery_ack_required"
    case "$RECOVERY_ACK" in /tmp/*|/run/*) ;; *) refuse 25 "recovery_ack_not_in_ram" ;; esac
    ack=$(p "$RECOVERY_ACK")
    [ -r "$ack" ] || refuse 25 "recovery_ack_missing"
    need_kv schema "$ack" 25
    [ "$NK_VALUE" = rx12.major13-volatile-load-recovery.v1 ] || refuse 25 "recovery_schema"
    need_kv token "$ack" 25; [ "$NK_VALUE" = "$TOKEN" ] || refuse 25 "recovery_token"
    need_kv node "$ack" 25; [ "$NK_VALUE" = "$NODE" ] || refuse 25 "recovery_node"
    need_kv device_serial "$ack" 25; [ "$NK_VALUE" = "$EXPECTED_SERIAL" ] || refuse 25 "recovery_serial"
    need_kv device_boot_id "$ack" 25; [ "$NK_VALUE" = "$EXPECTED_BOOT_ID" ] || refuse 25 "recovery_boot_id"
    need_kv device_reboot "$ack" 25
    [ "$NK_VALUE" = "/usr/sbin/device_reboot reset" ] || refuse 25 "recovery_command"
    need_kv success_marker "$ack" 25
    [ "$NK_VALUE" = "/tmp/rx12_v13_ed4_load_${TOKEN}/terminal_result" ] || refuse 25 "recovery_success_marker"
    need_kv deadline_seconds "$ack" 25
    [ "$NK_VALUE" = "$WATCHDOG_SECONDS" ] || refuse 25 "recovery_deadline"
    need_kv watchdog_script_sha256 "$ack" 25
    [ "$NK_VALUE" = "$WATCHDOG_SHA" ] || refuse 25 "recovery_watchdog_hash"
    need_kv helper_sha256 "$ack" 25
    [ "$NK_VALUE" = "$HELPER_SHA" ] || refuse 25 "recovery_helper_hash"
    need_kv payload_name "$ack" 25
    [ "$NK_VALUE" = "$PAYLOAD_NAME" ] || refuse 25 "recovery_payload_name"
    need_kv payload_sha256 "$ack" 25
    [ "$NK_VALUE" = "$PAYLOAD_SHA" ] || refuse 25 "recovery_payload_hash"
    need_kv payload_bytes "$ack" 25
    [ "$NK_VALUE" = "$PAYLOAD_BYTES" ] || refuse 25 "recovery_payload_size"
    need_kv candidate_review_manifest_sha256 "$ack" 25
    [ "$NK_VALUE" = "$CANDIDATE_REVIEW_MANIFEST_SHA" ] || refuse 25 "recovery_candidate_review_manifest_hash"
    need_kv candidate_signoff_manifest_sha256 "$ack" 25
    [ "$NK_VALUE" = "$CANDIDATE_SIGNOFF_MANIFEST_SHA" ] || refuse 25 "recovery_candidate_signoff_manifest_hash"
    need_kv watchdog_pid "$ack" 25; recovery_pid=$NK_VALUE
    pid_alive "$recovery_pid" || refuse 25 "recovery_watchdog_not_alive"
    recovery_exe=$(proc_exe "$recovery_pid")
    case "$recovery_exe" in /bin/sh|/bin/busybox) ;; *) refuse 25 "recovery_watchdog_executable" ;; esac
    expected_cmd="/bin/sh $WATCHDOG --execute --token $TOKEN --seconds $WATCHDOG_SECONDS --helper-sha256 $HELPER_SHA"
    [ "$(proc_cmdline "$recovery_pid")" = "$expected_cmd" ] || refuse 25 "recovery_watchdog_cmdline"
}

capture_dmesg_delta() {
    label=$1
    after="$JOURNAL/dmesg_${label}.txt"
    prefix="$JOURNAL/dmesg_${label}_prefix.txt"
    delta="$JOURNAL/dmesg_${label}_delta.txt"
    rejects="$JOURNAL/dmesg_${label}_rejects.txt"
    dmesg > "$after" || refuse 42 "dmesg_${label}_capture_failed"
    before_lines=$(wc -l < "$JOURNAL/dmesg_before.txt")
    after_lines=$(wc -l < "$after")
    [ "$after_lines" -ge "$before_lines" ] || refuse 42 "dmesg_${label}_ring_wrapped"
    head -n "$before_lines" "$after" > "$prefix" || refuse 42 "dmesg_${label}_prefix_failed"
    cmp -s "$JOURNAL/dmesg_before.txt" "$prefix" || refuse 42 "dmesg_${label}_prefix_changed"
    start=$((before_lines + 1))
    sed -n "${start},\$p" "$after" > "$delta" || refuse 42 "dmesg_${label}_delta_failed"
    grep -Ei 'deferred probe|probe.*(fail|error)|BUG:|Oops:|kernel panic|Call trace|timeout|timed out' \
        "$delta" > "$rejects"
    grep_rc=$?
    case "$grep_rc" in
        0) refuse 42 "dmesg_${label}_contains_reject_pattern" ;;
        1) ;;
        *) refuse 42 "dmesg_${label}_scan_failed" ;;
    esac
}

preflight() {
    for tool in awk cat cmp date devmem dmesg grep head mkdir mv pidof readlink rm sed sha256sum sleep sort tr wc; do
        require_tool "$tool"
    done
    [ -x "$(p /usr/bin/fuser)" ] || refuse 11 "exact_fuser_missing"
    [ -x "$(p /sbin/start-stop-daemon)" ] || refuse 11 "exact_start_stop_daemon_missing"
    [ -x "$(p /usr/sbin/device_reboot)" ] || refuse 11 "exact_device_reboot_missing"
    [ -w "$(p /sys/kernel/debug/zynq_rst/code)" ] || refuse 11 "reset_code_attribute_not_writable"
    [ -x "$(p /sbin/reboot)" ] || refuse 11 "exact_reboot_missing"
    validate_inputs
    require_manager
    require_manager_flags_zero
    require_fixed_payload
    require_version "$EXPECTED_PRE_VERSION"
    require_ps_clocks preflight
    require_no_ed_es
    require_no_suspend_helper
    require_driver_attrs
    require_binding 7c480000.aircomp uio_pdrv_genirq
    require_binding 79024000.cf-ad9361-dds-core-lpc cf_axi_dds
    require_binding 79020000.cf-ad9361-lpc cf_axi_adc
    require_binding 7c400000.dma dma-axi-dmac
    require_binding 7c420000.dma dma-axi-dmac
    require_spi_bound
    require_iio_topology
    require_no_waveform
    require_dma_links
    discover_uio
    require_no_device_users
    require_exact_iiod
    require_usb_layout
}

if [ "$MODE" = preflight ]; then
    preflight
    echo "ARC3_REBIND_PREFLIGHT_PASS read_only=1 node=ed4 pre_version=$EXPECTED_PRE_VERSION ps_fclk3=$PS_FCLK3_VALUE ps_io_pll=$PS_IO_PLL_VALUE token=$TOKEN"
    exit 0
fi

preflight
validate_recovery_ack
mkdir "$JOURNAL" || { echo "ARC3_REBIND_REFUSE cannot create RAM journal" >&2; exit 26; }
JOURNAL_READY=1
printf 'schema=rx12.major13-volatile-load-journal.v1\ntoken=%s\nbackup_manifest_sha256=%s\ninput_sha256=%s\nhelper_sha256=%s\nwatchdog_sha256=%s\npayload_name=%s\npayload_sha256=%s\n' \
    "$TOKEN" "$BACKUP_SHA" "$(sha256sum "$INPUT" | awk '{print $1}')" "$HELPER_SHA" "$WATCHDOG_SHA" \
    "$PAYLOAD_NAME" "$PAYLOAD_SHA" > "$JOURNAL/identity.txt" || refuse 27 "journal_identity_write_failed"
dmesg > "$JOURNAL/dmesg_before.txt" || refuse 27 "dmesg_before_failed"
usb_link_snapshot > "$JOURNAL/usb_links_before.txt" || refuse 27 "usb_link_snapshot_failed"
require_ps_clocks pre
mark 010 preflight_complete

trap 'terminal_fail 70 signal_HUP' HUP
trap 'terminal_fail 71 signal_INT' INT
trap 'terminal_fail 72 signal_TERM' TERM

CHANGES_STARTED=1
gadget=$(p /sys/kernel/config/usb_gadget/composite_gadget)
printf '\n' > "$gadget/UDC" || refuse 40 "udc_detach_failed"
[ -z "$(cat "$gadget/UDC" 2>/dev/null)" ] || refuse 40 "udc_detach_not_observed"
mark 020 usb_detached

iiod_pid=$(cat "$(p /var/run/iiod.pid)")
"$(p /sbin/start-stop-daemon)" -K -q -p "$(p /var/run/iiod.pid)" -x /usr/sbin/iiod || \
    refuse 41 "iiod_stop_request_failed"
wait_pid_gone "$iiod_pid"
rm -f "$(p /var/run/iiod.pid)"
require_no_device_users
mark 030 iiod_stopped

write_driver unbind uio_pdrv_genirq 7c480000.aircomp
require_no_binding 7c480000.aircomp
mark 041 unbind_uio
write_driver unbind cf_axi_dds 79024000.cf-ad9361-dds-core-lpc
require_no_binding 79024000.cf-ad9361-dds-core-lpc
mark 042 unbind_dds
write_driver unbind cf_axi_adc 79020000.cf-ad9361-lpc
require_no_binding 79020000.cf-ad9361-lpc
mark 043 unbind_adc
write_driver unbind dma-axi-dmac 7c400000.dma
require_no_binding 7c400000.dma
mark 044 unbind_rx_dma
write_driver unbind dma-axi-dmac 7c420000.dma
require_no_binding 7c420000.dma
mark 045 unbind_tx_dma

require_spi_bound
require_manager
require_manager_flags_zero
require_fixed_payload
sha256sum "$PAYLOAD_PATH" > "$JOURNAL/payload_immediate_preload.sha256" || refuse 46 "payload_preload_hash_record_failed"
mark 046 candidate_load_ready
printf '%s\n' "$PAYLOAD_NAME" > "$(p /sys/class/fpga_manager/fpga0/firmware)" || \
    refuse 46 "fpga_manager_firmware_write_failed"
LOAD_WRITTEN=1
if [ -n "$TEST_ROOT" ] && [ "${ARC3_TEST_LOAD_OUTCOME:-operating}" != operating ]; then
    printf '%s\n' "${ARC3_TEST_LOAD_OUTCOME}" > "$(p /sys/class/fpga_manager/fpga0/state)"
fi
if [ -n "$TEST_ROOT" ] && [ "${ARC3_TEST_LOAD_DIAGNOSTIC:-0}" = 1 ]; then
    cat >> "$(p /mock_dmesg)" <<'EOF'
ad9361 spi0.0: ad9361_validate_trx_clock_chain: Failed RX max rate check (160000000 > 122880000)
ad9361 spi0.0: ad9361_validate_trx_clock_chain: Failed RX max rate check (245760000 > 122880000)
EOF
fi
wait_manager_operating_after_load
require_manager_flags_zero
LOAD_OPERATING=1
require_version "$EXPECTED_POST_VERSION"
require_ps_clocks post
printf 'payload_name=%s\npayload_sha256=%s\nmanager_state=operating\nflags=0\n' \
    "$PAYLOAD_NAME" "$PAYLOAD_SHA" > "$JOURNAL/volatile_load_witness.txt" || refuse 46 "load_witness_write_failed"
mark 047 candidate_loaded_operating
capture_dmesg_delta postload
mark 048 postload_verified

# No bind write occurs before the manager has returned to operating above.
BIND_WRITES_STARTED=1
write_driver bind dma-axi-dmac 7c400000.dma
require_binding 7c400000.dma dma-axi-dmac
mark 051 bind_rx_dma
write_driver bind dma-axi-dmac 7c420000.dma
require_binding 7c420000.dma dma-axi-dmac
mark 052 bind_tx_dma
write_driver bind cf_axi_dds 79024000.cf-ad9361-dds-core-lpc
require_binding 79024000.cf-ad9361-dds-core-lpc cf_axi_dds
mark 053 bind_dds
write_driver bind cf_axi_adc 79020000.cf-ad9361-lpc
require_binding 79020000.cf-ad9361-lpc cf_axi_adc
mark 054 bind_adc
write_driver bind uio_pdrv_genirq 7c480000.aircomp
require_binding 7c480000.aircomp uio_pdrv_genirq
mark 055 bind_uio

require_spi_bound
require_iio_topology
require_no_waveform
require_dma_links
discover_uio
require_manager
require_version "$EXPECTED_POST_VERSION"
require_no_ed_es
capture_dmesg_delta postbind
mark 060 postbind_verified

"$(p /sbin/start-stop-daemon)" -S -b -q -m -p "$(p /var/run/iiod.pid)" -x /usr/sbin/iiod -- \
    -D -n 3 -F /dev/iio_ffs || refuse 43 "iiod_start_failed"
wait_iiod_ready
mark 070 iiod_ready

usb_link_snapshot > "$JOURNAL/usb_links_after.txt" || refuse 44 "usb_link_snapshot_after_failed"
cmp -s "$JOURNAL/usb_links_before.txt" "$JOURNAL/usb_links_after.txt" || refuse 44 "usb_configfs_links_changed"
printf '%s\n' "$EXPECTED_UDC" > "$gadget/UDC" || refuse 44 "udc_attach_failed"
[ "$(cat "$gadget/UDC" 2>/dev/null)" = "$EXPECTED_UDC" ] || refuse 44 "udc_attach_not_observed"
wait_udc_configured
mark 080 usb_configured

require_exact_iiod
require_no_ed_es
require_manager
require_manager_flags_zero
require_version "$EXPECTED_POST_VERSION"
require_spi_bound
require_binding 7c480000.aircomp uio_pdrv_genirq
require_binding 79024000.cf-ad9361-dds-core-lpc cf_axi_dds
require_binding 79020000.cf-ad9361-lpc cf_axi_adc
require_binding 7c400000.dma dma-axi-dmac
require_binding 7c420000.dma dma-axi-dmac
require_iio_topology
require_no_waveform
require_dma_links
discover_uio
require_fixed_payload
record_iio_posthealth
require_ps_clocks final
capture_dmesg_delta final
mark 090 final_health_verified
trap - HUP INT TERM
atomic_terminal PASS 0 all_checks_passed || terminal_fail 75 "terminal_pass_atomic_write_failed"
echo "RX12_MAJOR13_ED4_VOLATILE_LOAD_PASS journal=$JOURNAL host_must_retrieve_transcript=1"
exit 0
