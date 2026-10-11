#!/usr/bin/env bash
set -euo pipefail
app_id=com.ondrejhlavacek.cubetimer
mkdir -p output
adb install -r app/build/outputs/apk/release/app-release.apk
adb shell am start -W -n "$app_id/.MainActivity"
adb shell input keyevent KEYCODE_WAKEUP
adb shell wm dismiss-keyguard
sleep 2
snapshot() {
    adb shell uiautomator dump /sdcard/cube-timer-ui.xml >/dev/null
    adb pull /sdcard/cube-timer-ui.xml "output/$1.xml" >/dev/null
    adb exec-out screencap -p > "output/$1.png"
}
read_time() {
    grep -oE 'Last solve: [0-9]+:[0-9]{2}\.[0-9]{2}' "$1" | head -1 | cut -d ' ' -f3
}
snapshot ready
grep -q 'Start timer' output/ready.xml
adb shell input tap 30 300
snapshot running
! grep -q 'content-desc="Timer options"' output/running.xml
sleep 2
adb shell input tap 1000 1600
snapshot stopped
grep -q 'Last solve:' output/stopped.xml
first_time=$(read_time output/stopped.xml)
[[ "$first_time" != '00:00.00' ]]
sleep 1
snapshot still-stopped
[[ "$(read_time output/still-stopped.xml)" == "$first_time" ]]
adb shell am force-stop "$app_id"
adb shell am start -W -n "$app_id/.MainActivity"
snapshot reopened
[[ "$(read_time output/reopened.xml)" == "$first_time" ]]
adb shell input tap 500 700
sleep 1
adb shell input keyevent KEYCODE_HOME
sleep 2
adb shell am force-stop "$app_id"
adb shell am start -W -n "$app_id/.MainActivity"
sleep 1
adb shell input tap 30 300
snapshot resumed
grep -q 'Last solve:' output/resumed.xml
resumed_time=$(read_time output/resumed.xml)
awk -v value="$resumed_time" 'BEGIN { split(value, parts, ":"); if (parts[1] * 60 + parts[2] < 4) exit 1 }'
adb shell settings put system accelerometer_rotation 0
adb shell settings put system user_rotation 1
sleep 2
snapshot landscape
grep -q 'Last solve:' output/landscape.xml
[[ "$(read_time output/landscape.xml)" == "$resumed_time" ]]
adb shell settings put system user_rotation 0
tap_menu_item() {
    adb shell uiautomator dump /sdcard/cube-timer-ui.xml >/dev/null
    adb pull /sdcard/cube-timer-ui.xml output/current-ui.xml >/dev/null
    read -r tap_x tap_y < <(node - "$1" <<'JS'
const fs = require("fs");
const xml = fs.readFileSync("output/current-ui.xml", "utf8");
const label = process.argv[2];
const node = xml.match(/<node\b[^>]*>/g).find(entry => entry.includes(`text="${label}"`) || entry.includes(`content-desc="${label}"`));
if (!node) throw new Error(`Missing control: ${label}`);
const bounds = node.match(/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/).slice(1).map(Number);
console.log(Math.floor((bounds[0] + bounds[2]) / 2), Math.floor((bounds[1] + bounds[3]) / 2));
JS
    )
    adb shell input tap "$tap_x" "$tap_y"
}
sleep 5
tap_menu_item "Timer options"
snapshot options
tap_menu_item "Resume"
sleep 2
adb shell input tap 30 300
snapshot continued
continued_time=$(read_time output/continued.xml)
awk -v before="$resumed_time" -v after="$continued_time" 'BEGIN { split(before, a, ":"); split(after, b, ":"); delta = (b[1] - a[1]) * 60 + b[2] - a[2]; if (delta < 2 || delta > 5) exit 1 }'
adb shell am force-stop "$app_id"
adb shell am start -W -n "$app_id/.MainActivity"
snapshot continued-reopened
[[ "$(read_time output/continued-reopened.xml)" == "$continued_time" ]]
tap_menu_item "Timer options"
tap_menu_item "Reset"
snapshot reset
grep -q 'Start timer' output/reset.xml
sleep 2
snapshot still-reset
grep -q 'Start timer' output/still-reset.xml
adb shell input tap 30 300
sleep 2
adb shell input tap 1000 1600
snapshot after-reset
reset_time=$(read_time output/after-reset.xml)
awk -v value="$reset_time" 'BEGIN { split(value, parts, ":"); seconds = parts[1] * 60 + parts[2]; if (seconds < 2 || seconds > 5) exit 1 }'
adb logcat -d -b crash > output/crash-log.txt
if grep -q "Process: $app_id" output/crash-log.txt; then exit 1; fi
printf 'PASS: full-surface start/stop, frozen result, persisted result, background/process restart, rotation, resume excluding paused time, reset to zero, no app crash.\n' | tee output/verification.txt
