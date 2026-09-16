#!/usr/bin/env bash
# gh-speedtest — uji koneksi & kecepatan GitHub dari server ini
# Pakai: curl -sS https://raw.githubusercontent.com/ujang0311/gh-speedtest/main/gh-speedtest.sh | bash
#        ... | bash -s -- --big        (uji unduh ~100 MB untuk angka lebih stabil)
#        ... | bash -s -- --quiet      (ringkas)
set -u
V="1.0.0"
BOLD=$'\e[1m'; DIM=$'\e[2m'; R=$'\e[0m'; G=$'\e[32m'; Y=$'\e[33m'; RED=$'\e[31m'; C=$'\e[36m'
BIG=0; QUIET=0
for a in "$@"; do
  case "$a" in --big) BIG=1 ;; --quiet|-q) QUIET=1 ;; --help|-h) sed -n '2,6p' "$0"; exit 0 ;; esac
done

API=https://api.github.com
RAW=https://raw.githubusercontent.com/ujang0311/gh-speedtest/main/payload.txt
TARBALL=https://codeload.github.com/NousResearch/hermes-agent/tar.gz/refs/heads/main
[ "$BIG" -eq 1 ] && TARBALL=https://codeload.github.com/NousResearch/hermes-agent/tar.gz/refs/heads/main

hline(){ printf '%s\n' "  ─────────────────────────────────────────────────────────────"; }
row(){ printf '  %-34s %s\n' "$1" "$2"; }
mb(){ awk -v b="$1" 'BEGIN{printf "%.2f MB/s", b/1048576}'; }

[ "$QUIET" -eq 0 ] && cat <<EOF

  ╭──────────────────────────────────────────────────────────────╮
  │  ⬢  ${BOLD}GitHub Connectivity Test${R}                         v$V   │
  │  latensi · throughput · git protocol · registry              │
  ╰──────────────────────────────────────────────────────────────╯
EOF

command -v curl >/dev/null || { echo "  ✖ curl tidak ada (apt-get install -y curl)"; exit 1; }
T0=$(date +%s)

# ── 1. DNS + TCP + TLS + API
[ "$QUIET" -eq 0 ] && { echo; echo "  ◆ Jaringan dasar"; }
DNS=$( { getent hosts api.github.com >/dev/null 2>&1 && echo ok; } || { nslookup api.github.com >/dev/null 2>&1 && echo ok; } || echo gagal )
row "DNS api.github.com" "$( [ "$DNS" = ok ] && echo "${G}ok${R}" || echo "${RED}gagal${R}" )"
read -r TCP TLS TOT < <(curl -sS -o /dev/null -w '%{time_connect} %{time_appconnect} %{time_total}' --max-time 15 "$API/zen" 2>/dev/null | awk '{print $1, $2, $3}') \
  || TCP="-"; TLS="-"; TOT="-"
row "TCP connect :443" "${TCP}s"
row "TLS handshake" "${TLS}s"
row "API /zen total" "${TOT}s $(curl -sS --max-time 15 "$API/zen" 2>/dev/null | head -c 60)"

# ── 2. raw.githubusercontent (kecil, untuk latensi + cache)
[ "$QUIET" -eq 0 ] && { echo; echo "  ◆ raw.githubusercontent.com"; }
read -r RSZ RSPD < <(curl -sS -o /dev/null -w '%{size_download} %{speed_download}' --max-time 20 "$RAW?cb=$(date +%s)" 2>/dev/null | awk '{print $1, $2}')
row "unduh kecil" "${RSZ:-0} B · $(mb "${RSPD:-0}")"

# ── 3. codeload (throughput nyata klon/tar)
[ "$QUIET" -eq 0 ] && { echo; echo "  ◆ codeload.github.com (throughput nyata)"; }
TIMEOUT=25; [ "$BIG" -eq 1 ] && TIMEOUT=120
read -r TSZ TSPD < <(curl -sSL -o /dev/null -w '%{size_download} %{speed_download}' --max-time "$TIMEOUT" "$TARBALL" 2>/dev/null | awk '{print $1, $2}')
SPD=${TSPD%.*}
row "unduh tarball" "$(awk -v b="${TSZ:-0}" 'BEGIN{printf "%.1f MB", b/1048576}') · $(mb "${TSPD:-0}")"

# ── 4. git over HTTPS
[ "$QUIET" -eq 0 ] && { echo; echo "  ◆ git protocol (HTTPS 443)"; }
if command -v git >/dev/null; then
  GT=$( { time timeout 25 git ls-remote https://github.com/NousResearch/hermes-agent HEAD >/dev/null 2>&1; } 2>&1 | awk '/real/{print $2}' )
  [ -n "$GT" ] && row "git ls-remote" "${G}ok${R} ($GT)" || row "git ls-remote" "${RED}gagal/timeout${R}"
else row "git ls-remote" "${Y}git tidak terpasang${R}"; fi

# ── 5. registry paket (pip/npm) — bikin update lambat kalau jelek
[ "$QUIET" -eq 0 ] && { echo; echo "  ◆ registry paket"; }
P=$(curl -sS -o /dev/null -w '%{time_total} %{speed_download}' --max-time 20 https://pypi.org/simple/ 2>/dev/null)
row "pypi.org" "$(echo "$P" | awk '{print $1" s"}')"
N=$(curl -sS -o /dev/null -w '%{time_total} %{speed_download}' --max-time 20 https://registry.npmjs.org/ 2>/dev/null)
row "registry.npmjs.org" "$(echo "$N" | awk '{print $1" s"}')"

# ── 6. rate limit API (kalau ada token)
[ "$QUIET" -eq 0 ] && { echo; echo "  ◆ GitHub API"; }
row "rate limit" "$(curl -sS --max-time 15 "$API/rate_limit" 2>/dev/null | grep -o '"remaining":[0-9]*' | head -1 | cut -d: -f2 | sed 's/$/ sisa (unauth: 60\/jam)/')"

# ── verdict
DONE=$(( $(date +%s) - T0 ))
echo
hline
printf '  %s\n' "${BOLD}KESIMPULAN${R}"
if [ "${SPD:-0}" -ge 5242880 ]; then
  printf '  %s\n' "${G}✔ jalur ke GitHub bagus${R} (≥5 MB/s) — clone/pip/npm aman langsung"
elif [ "${SPD:-0}" -ge 1048576 ]; then
  printf '  %s\n' "${Y}▲ sedang${R} (1–5 MB/s) — self-heal bisa 5–15 menit, tunggu saja"
else
  printf '  %s\n' "${RED}✖ lambat${R} (<1 MB/s) — jangan clone dari server ini. Pakai relay:"
  printf '  %s\n' "   1) di mesin cepat: git clone --depth 1 https://github.com/NousResearch/hermes-agent"
  printf '  %s\n' "      tar czf hermes-src.tgz --exclude=.git --exclude=venv --exclude=node_modules -C hermes-agent ."
  printf '  %s\n' "   2) cat hermes-src.tgz | ssh root@IP-VM 'tar xzf - -C /root'"
  printf '  %s\n' "   3) di VM: hermes-upgrade.sh --repair-only --source-archive /root/hermes-src.tgz"
fi
printf '  %s\n' "  uji selesai dalam ${DONE}s"
