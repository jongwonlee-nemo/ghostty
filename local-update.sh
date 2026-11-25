#!/bin/bash
# Merge upstream into local/patched, rebuild, sign with a stable identity and reinstall.
set -euo pipefail
cd "$(dirname "$0")"
self="$PWD/${0##*/}"

APP=/Applications/Ghostty.app
BUILT=macos/build/ReleaseLocal/Ghostty.app
BUNDLE_ID=com.mitchellh.ghostty.patched
SIGN_ID="Ghostty Local" # stable signer so the Accessibility grant survives rebuilds
LOG=~/Library/Logs/ghostty-update.log

notify() {
    echo "$1"
    osascript -e 'on run a' -e 'display notification (item 1 of a) with title "Ghostty 업데이트"' -e 'end run' "$1" >/dev/null 2>&1 || true
}
running() { pgrep -f "$APP/Contents/MacOS/ghostty" >/dev/null; }
swap() {
    [[ ! -e $APP ]] || mv "$APP" "$APP.old"
    if mv "$APP.new" "$APP"; then rm -rf "$APP.old"; else [[ ! -e $APP.old ]] || mv "$APP.old" "$APP"; return 1; fi
}

# Detached helper: runs outside Ghostty so it survives the quit, then swaps and relaunches.
if [[ ${1:-} == --after-quit ]]; then
    echo "[$(date)] waiting for Ghostty to quit"
    for _ in $(seq 600); do running || break; sleep 1; done
    if running; then rm -rf "$APP.new"; notify "Ghostty가 종료되지 않아 설치를 취소했습니다."; exit 1; fi
    if swap; then open "$APP"; notify "업데이트를 설치했습니다."; else notify "설치 실패. $LOG 확인"; fi
    exit 0
fi

merge() {
    git merge --no-edit "$1" && return
    git merge --abort
    notify "$1 merge 중 충돌이 나서 취소했습니다. 직접 해결해야 합니다."
    exit 1
}

[[ $(git branch --show-current) == local/patched ]] || { echo "local/patched 브랜치에서 실행하세요."; exit 1; }
[[ -z $(git status --porcelain) ]] || { echo "커밋되지 않은 변경이 있어 중단합니다."; exit 1; }

# origin is the personal fork; fetch upstream by URL so a fresh clone needs no extra remote.
git fetch https://github.com/ghostty-org/ghostty.git +main:refs/remotes/upstream/main
merge upstream/main
# IME fix PR #15232; the fetch fails and is skipped once the branch is deleted after merge.
if git fetch https://github.com/bo2themax/ghostty.git +push-753b2128:pr-15232; then merge pr-15232; fi

zig build -Doptimize=ReleaseFast -Dxcframework-target=native || { notify "빌드에 실패했습니다. 설치된 앱은 그대로입니다."; exit 1; }
git push -u origin local/patched || notify "origin 푸시에 실패했습니다. 설치는 계속합니다."

if ! security find-certificate -c "$SIGN_ID" >/dev/null 2>&1; then
    # One-time: create a self-signed code signing identity in the login keychain.
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    pass=$(/usr/bin/openssl rand -hex 16)
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$SIGN_ID" \
        -addext basicConstraints=critical,CA:false -addext keyUsage=critical,digitalSignature \
        -addext extendedKeyUsage=critical,codeSigning -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
    /usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -passout "pass:$pass" -out "$tmp/id.p12"
    security import "$tmp/id.p12" -P "$pass" -T /usr/bin/codesign
fi
codesign --force --preserve-metadata=entitlements,flags,runtime -s "$SIGN_ID" "$BUILT"

rm -rf "$APP.new"
ditto "$BUILT" "$APP.new"
if ! running; then swap && echo "설치했습니다: $APP"; exit 0; fi

cat <<'EOF'

⚠️  설치하려면 Ghostty를 완전히 종료해야 합니다.
  - 모든 창, 탭, quake 터미널의 셸과 실행 중인 프로그램이 종료됩니다. (창 배치는 다시 열 때 복원)
  - 이 스크립트를 Ghostty 안에서 실행했다면 이 창도 닫힙니다.
    설치는 백그라운드에서 이어지고, 끝나면 Ghostty가 다시 열리며 알림이 뜹니다.
  - 종료 확인 창이 뜨면 "종료"를 눌러야 진행됩니다. 10분 안에 종료되지 않으면 취소됩니다.

EOF
read -r -p "지금 Ghostty를 종료하고 설치할까요? [y/N] " answer || true
if [[ ${answer:-} != [yY] ]]; then
    rm -rf "$APP.new"
    echo "설치를 건너뜁니다. 빌드는 $BUILT 에 있고, 다시 실행하면 설치합니다."
    exit 0
fi

nohup "$self" --after-quit >>"$LOG" 2>&1 </dev/null &
osascript -e 'ignoring application responses' -e "tell application id \"$BUNDLE_ID\" to quit" -e 'end ignoring'
echo "Ghostty를 종료하는 중입니다. 진행 기록: $LOG"
