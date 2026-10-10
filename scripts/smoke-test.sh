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
adb logcat -d -b crash > output/crash-log.txt
if grep -q "Process: $app_id" output/crash-log.txt; then exit 1; fi
printf 'PASS: full-surface start/stop, frozen result, persisted result, background/process restart, rotation, no app crash.\n' | tee output/verification.txt
