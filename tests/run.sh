#!/bin/bash
# Green battery for artmrn.pip-video. Every check prints PASS/SKIP/FAIL and the
# script exits non-zero if anything fails. Live-window checks use a throwaway
# mpv window titled like a PiP and always clean up after themselves.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
SKIP=0

pass() { PASS=$((PASS + 1)); echo "PASS  $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL  $1"; }
skip() { SKIP=$((SKIP + 1)); echo "SKIP  $1"; }

echo "== manifest =="
if omarchy plugin validate "$REPO" >/dev/null 2>&1; then pass "manifest validates"; else fail "manifest validates"; fi

echo "== syntax =="
if luac -p "$REPO/hypr/pip-video.lua" "$REPO/hypr/pip-video-bindings.lua" 2>/dev/null; then
  pass "hypr lua parses"
else
  fail "hypr lua parses"
fi
if command -v qmllint >/dev/null 2>&1 || [[ -x /usr/lib/qt6/bin/qmllint ]]; then
  qmlint_bin=$(command -v qmllint 2>/dev/null || echo /usr/lib/qt6/bin/qmllint)
  if "$qmlint_bin" "$REPO/PiPVideo.qml" "$REPO/Service.qml" 2>&1 | grep -q "^Error"; then
    fail "qml parses"
  else
    pass "qml parses"
  fi
else
  skip "qmllint (not installed)"
fi
echo "== shipped files load in live Hyprland =="
rule_out=$(hyprctl eval "dofile(\"$REPO/hypr/pip-video.lua\")" 2>&1)
if [[ -z "$rule_out" || "$rule_out" == "ok" ]]; then
  pass "pip-video.lua live (fresh registration)"
elif grep -qi "overshadow" <<<"$rule_out"; then
  pass "pip-video.lua live (matches loaded gesture)"
else
  fail "pip-video.lua live ($rule_out)"
fi
if hyprctl eval "dofile(\"$REPO/hypr/pip-video-bindings.lua\")" >/dev/null 2>&1; then
  pass "bindings live"
else
  fail "bindings live"
fi
hyprctl reload >/dev/null 2>&1
sleep 1
syntax_ok=1
for f in "$REPO"/bin/* "$REPO"/install "$REPO"/uninstall "$REPO"/tests/run.sh; do
  bash -n "$f" 2>/dev/null || { fail "bash -n $(basename "$f")"; syntax_ok=0; }
done
(( syntax_ok )) && pass "bash syntax"
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning "$REPO"/bin/* "$REPO"/install "$REPO"/uninstall 2>/dev/null; then pass "shellcheck"; else fail "shellcheck"; fi
else
  skip "shellcheck (not installed)"
fi

echo "== hyprland =="
if [[ -z "$(hyprctl configerrors 2>/dev/null)" ]]; then pass "configerrors clean"; else fail "configerrors clean"; fi
keys_tmp=$(mktemp)
for _ in 1 2 3; do
  omarchy menu keybindings --print >"$keys_tmp" 2>/dev/null || true
  [[ -s "$keys_tmp" ]] && break
  sleep 1
done
for desc in "YouTube PiP smaller" "YouTube PiP bigger" "YouTube PiP shorter" "YouTube PiP taller" "Video wallpaper from clipboard" "Workspace windows more transparent"; do
  if grep -qF "$desc" "$keys_tmp"; then pass "bind: $desc"; else fail "bind: $desc"; fi
done
rm -f "$keys_tmp"

echo "== live resize (stand-in window titled like a PiP) =="
if hyprctl -j clients 2>/dev/null | jq -e '.[] | select(.title | test("Picture[- ]in[- ]Picture"))' >/dev/null 2>&1; then
  skip "live resize (a real PiP is open; not touching it)"
  addr="SKIP"
elif command -v chromium >/dev/null 2>&1; then
  spawn_backend=chromium
  hyprctl dispatch 'hl.dsp.exec_cmd("chromium --app=\"data:text/html,<title>Picture-in-Picture</title><body style=background:#111>\"")' >/dev/null 2>&1
  addr=""
  for _ in $(seq 1 24); do
    sleep 0.5
    addr=$(hyprctl -j clients 2>/dev/null | jq -r '.[] | select(.title == "Picture-in-Picture" and .mapped) | .address')
    [[ -n "$addr" ]] && break
  done
elif command -v mpv >/dev/null 2>&1; then
  spawn_backend=mpv
  hyprctl dispatch 'hl.dsp.exec_cmd("mpv --force-window --idle=yes --title=\"Picture-in-Picture\"")' >/dev/null 2>&1
  addr=""
  for _ in $(seq 1 16); do
    sleep 0.5
    addr=$(hyprctl -j clients 2>/dev/null | jq -r '.[] | select(.title == "Picture-in-Picture" and .class == "mpv" and .mapped) | .address')
    [[ -n "$addr" ]] && break
  done
else
  skip "live resize (no chromium or mpv)"
  addr="SKIP"
fi
if [[ "$addr" == "SKIP" ]]; then
  :
elif [[ -z "$addr" ]]; then
  fail "test window spawned+mapped ($spawn_backend)"
else
    pass "test window spawned+mapped"
    sleep 3
    size() { hyprctl -j clients 2>/dev/null | jq -r --arg a "$addr" '.[] | select(.address == $a) | "\(.size[0])x\(.size[1])"'; }
    sel_resize() { # x y: resize via the exact product title selector
      hyprctl dispatch "hl.dsp.window.resize({ x = $1, y = $2, relative = true, window = \"title:Picture[- ]in[- ]Picture\" })" >/dev/null 2>&1
    }
    # Liveness probe on the product path itself: fresh windows sometimes drop
    # dispatches while settling, so only proceed once it demonstrably moves.
    probe_before=$(size)
    probe_moved=0
    for _ in $(seq 1 6); do
      sel_resize 10 6
      sleep 0.5
      if [[ "$(size)" != "$probe_before" ]]; then probe_moved=1; break; fi
    done
    if (( probe_moved )); then
      pass "test window responsive"
      sel_resize -10 -6
      sleep 0.5
      orig_size=$(size)
    else
      fail "test window responsive (stuck at $probe_before)"
    fi
    check_resize() { # name, x, y, expect_change(1/0)
      local name=$1 x=$2 y=$3 expect=$4 before after attempt
      before=$(size)
      # Rapid resizes can lose one dispatch if the client is still acking the
      # previous configure, so retry a few times before calling it stuck.
      for attempt in 1 2 3; do
        sel_resize "$x" "$y"
        sleep 0.4
        after=$(size)
        [[ "$before" != "$after" ]] && break
      done
      if (( expect )); then
        [[ "$before" != "$after" ]] && pass "$name ($before -> $after)" || fail "$name (stuck at $before)"
      else
        [[ "$before" == "$after" ]] && pass "$name (unchanged)" || fail "$name (moved $before -> $after)"
      fi
    }
    check_resize "H smaller" -50 -28 1
    check_resize "L bigger" 50 28 1
    check_resize "J shorter" 0 -30 1
    check_resize "U taller" 0 30 1
    read -r ow oh <<< "$(size | tr x ' ')"
    hyprctl dispatch "hl.dsp.window.resize({ x = $ow, y = $oh, window = \"address:$addr\" })" >/dev/null 2>&1
    sleep 0.3
    [[ "$(size)" == "$orig_size" ]] && pass "size restored" || fail "size restored (got $(size), want $orig_size)"
    hyprctl dispatch "hl.dsp.window.close({ window = \"address:$addr\" })" >/dev/null 2>&1
    sleep 0.5
    if [[ -z "$(hyprctl -j clients 2>/dev/null | jq -r --arg a "$addr" '.[] | select(.address == $a) | .address')" ]]; then
      pass "test window closed"
    else
      fail "test window closed"
    fi
  fi

echo "== workspace opacity =="
ws=$(hyprctl -j activeworkspace 2>/dev/null | jq -r '.id')
ws_addr=$(hyprctl -j clients 2>/dev/null | jq -r --argjson ws "$ws" '[.[] | select(.mapped and .workspace.id == $ws)][0] | .address')
if [[ -n "$ws_addr" && "$ws_addr" != "null" ]]; then
  "$REPO/bin/workspace-opacity" set 0.7 >/dev/null 2>&1
  sleep 0.3
  [[ "$(hyprctl getprop "address:$ws_addr" opacity 2>/dev/null)" == "0.7" ]] && pass "opacity set 0.7" || fail "opacity set 0.7"
  "$REPO/bin/workspace-opacity" reapply >/dev/null 2>&1 && pass "opacity reapply" || fail "opacity reapply"
  "$REPO/bin/workspace-opacity" reset >/dev/null 2>&1
  sleep 0.3
  [[ "$(hyprctl getprop "address:$ws_addr" opacity 2>/dev/null)" == "1" ]] && pass "opacity reset" || fail "opacity reset"
else
  skip "workspace opacity (no window on workspace $ws)"
fi

echo "== settings =="
prev_step=$("$REPO/bin/omarchy-pip-video" get opacity_step 2>/dev/null)
"$REPO/bin/omarchy-pip-video" set opacity_step 0.2 >/dev/null 2>&1
[[ "$("$REPO/bin/omarchy-pip-video" get opacity_step 2>/dev/null)" == "0.2" ]] && pass "set/get opacity_step" || fail "set/get opacity_step"
"$REPO/bin/workspace-opacity" reset >/dev/null 2>&1
"$REPO/bin/workspace-opacity" down >/dev/null 2>&1
down_level=$(jq -r --arg ws "$ws" '.[$ws] // 1.0' "$HOME/.cache/workspace-opacity.json" 2>/dev/null)
if awk -v v="$down_level" 'BEGIN { exit (v >= 0.79 && v <= 0.81) ? 0 : 1 }'; then pass "step honored (0.2)"; else fail "step honored (0.2, got $down_level)"; fi
"$REPO/bin/omarchy-pip-video" set opacity_step "$prev_step" >/dev/null 2>&1
"$REPO/bin/workspace-opacity" reset >/dev/null 2>&1
if "$REPO/bin/omarchy-pip-video" set opacity_step 9 >/dev/null 2>&1; then fail "rejects bad step"; else pass "rejects bad step"; fi
if "$REPO/bin/omarchy-pip-video" set bogus 1 >/dev/null 2>&1; then fail "rejects bad key"; else pass "rejects bad key"; fi
"$REPO/bin/omarchy-pip-video" howto 2>/dev/null | grep -q "SUPER+ALT+V" && pass "howto" || fail "howto"
if command -v mpvpaper >/dev/null 2>&1 && command -v ffmpeg >/dev/null 2>&1; then
  "$REPO/bin/omarchy-pip-video" set start_muted 1 >/dev/null 2>&1
  ffmpeg -hide_banner -loglevel error -y -f lavfi -i testsrc2=duration=2:size=320x180:rate=10 /tmp/pipvideo-settings-test.mp4
  "$REPO/bin/video-wallpaper" set /tmp/pipvideo-settings-test.mp4 >/dev/null 2>&1
  sleep 1
  if pgrep -a mpvpaper 2>/dev/null | grep -q "no-audio"; then pass "start_muted honored"; else fail "start_muted honored"; fi
  "$REPO/bin/video-wallpaper" stop >/dev/null 2>&1
  sleep 0.5
  pgrep -x mpvpaper >/dev/null 2>&1 && fail "stop kills player" || pass "stop kills player"
  "$REPO/bin/omarchy-pip-video" set start_muted 0 >/dev/null 2>&1
  rm -f /tmp/pipvideo-settings-test.mp4
else
  skip "start_muted live (needs mpvpaper + ffmpeg)"
fi

echo "== video wallpaper =="
if [[ "$("$REPO/bin/video-wallpaper" status 2>/dev/null)" == "stopped" ]]; then pass "status stopped"; else fail "status stopped"; fi
if "$REPO/bin/video-wallpaper" set "not a url or file" >/dev/null 2>&1; then fail "rejects bad input"; else pass "rejects bad input"; fi
if command -v mpvpaper >/dev/null 2>&1; then pass "mpvpaper installed"; else skip "mpvpaper not installed (video wallpaper disabled; run: omarchy pkg aur add mpvpaper)"; fi

echo "== doctor =="
doc_out=$("$REPO/bin/omarchy-pip-video" doctor 2>&1 || true)
if command -v mpvpaper >/dev/null 2>&1; then
  if printf '%s' "$doc_out" | grep -q "problems:"; then fail "doctor clean"; else pass "doctor clean"; fi
else
  if printf '%s' "$doc_out" | grep -q "mpvpaper"; then pass "doctor flags missing mpvpaper"; else fail "doctor flags missing mpvpaper"; fi
fi

echo
echo "green: $PASS passed, $SKIP skipped, $FAIL failed"
(( FAIL == 0 ))
