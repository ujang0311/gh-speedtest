#!/usr/bin/env bash
# gh-speedtest v1.1.0 — uji koneksi & kecepatan GitHub dari server ini
#   curl -sS https://raw.githubusercontent.com/ujang0311/gh-speedtest/main/gh-speedtest.sh | bash
#   ... | bash -s -- --big      (unduh lebih lama: angka lebih stabil)
#   ... | bash -s -- --timeout 60
set -u
V="1.1.2"
BOLD=$'\e[1m'; R=$'\e[0m'; G=$'\e[32m'; Y=$'\e[33m'; RED=$'\e[31m'
BIG=0; TL=30
while [ $# -gt 0 ]; do
  case "$1" in
    --big) BIG=1; TL=120 ;;
    --timeout) shift; TL="${1:-30}" ;;
    --help|-h) sed -n '2,5p' "$0"; exit 0 ;;
  esac; shift
done

API=https://api.github.com
RAW=https://raw.githubusercontent.com/ujang0311/gh-speedtest/main/payload.txt
TARBALL=https://codeload.github.com/NousResearch/hermes-agent/tar.gz/refs/heads/main

row(){ printf '  %-26s %s\n' "$1" "$2"; }
mbps(){ awk -v b="${1:-0}" 'BEGIN{printf "%.2f MB/s", b/1048576}'; }
human(){ awk -v b="${1:-0}" 'BEGIN{if(b>1048576)printf "%.1f MB",b/1048576; else if(b>1024)printf "%.0f KB",b/1024; else printf "%.0f B",b}'; }

cat <<EOF

  ╭──────────────────────────────────────────────────────────────╮
  │  ⬢  ${BOLD}GitHub Connectivity Test${R}                         v$V   │
  │  DNS · TLS · throughput · git protocol · registry paket      │
  ╰──────────────────────────────────────────────────────────────╯
EOF

command -v curl >/dev/null 2>&1 || { echo "  ✖ curl tidak ada (apt-get install -y curl)"; exit 1; }
T0=$(date +%s)

echo; echo "  ◆ Jaringan dasar"
if getent hosts api.github.com >/dev/null 2>&1 || nslookup api.github.com >/dev/null 2>&1; then
  row "DNS api.github.com" "${G}ok${R}"
else row "DNS api.github.com" "${RED}gagal${R} (cek resolv.conf/firewall)"; fi

row "TCP connect :443" "$(curl -sS -o /dev/null -w '%{time_connect}s' --max-time 15 "$API/zen" 2>/dev/null || echo 'gagal')"
row "TLS handshake" "$(curl -sS -o /dev/null -w '%{time_appconnect}s' --max-time 15 "$API/zen" 2>/dev/null || echo 'gagal')"
row "api.github.com/zen" "$(curl -sS --max-time 15 "$API/zen" 2>/dev/null | head -c 48)"

echo; echo "  ◆ jalur 'curl | bash' (raw.githubusercontent.com) — 3x percobaan"
RAW_BEST=0; RAW_ANY=0
for i in 1 2 3; do
  RS=$(curl -sS -o /dev/null -w '%{size_download} %{speed_download} %{http_code}' --max-time 25 "$RAW?cb=$(date +%s%N)" 2>/dev/null)
  SZ=$(echo "$RS" | cut -d' ' -f1); SPD=$(echo "$RS" | cut -d' ' -f2); SPD=${SPD%.*}; COD=$(echo "$RS" | cut -d' ' -f3)
  row "coba $i: $(human "$SZ") (HTTP $COD)" "$(mbps "$SPD")"
  [ "${SPD:-0}" -gt "$RAW_BEST" ] && RAW_BEST=$SPD
  [ "${COD:-0}" = 200 ] && RAW_ANY=$(( RAW_ANY + 1 ))
done

echo; echo "  ◆ throughput nyata (codeload tarball, jendela ${TL}s)"
TSPD=0
for i in 1 2; do
  TS=$(curl -sSL -o /dev/null -w '%{size_download} %{speed_download} %{http_code}' --max-time "$TL" "$TARBALL" 2>/dev/null)
  SPD=$(echo "$TS" | cut -d' ' -f2); SPD=${SPD%.*}; COD=$(echo "$TS" | cut -d' ' -f3)
  row "coba $i: $(human "$(echo "$TS" | cut -d' ' -f1)") (HTTP ${COD:-?})" "$(mbps "$SPD")"
  [ "${SPD:-0}" -gt "$TSPD" ] && TSPD=$SPD
  [ "$i" -eq 1 ] && [ "${SPD:-0}" -ge 5242880 ] && break   # sudah bagus, tak perlu ulang
done
[ "$BIG" -eq 0 ] && echo "  ${Y}·${R} jalankan dengan --big bila angka terlihat kecil/tidak stabil"

echo; echo "  ◆ git protocol (HTTPS 443)"
if command -v git >/dev/null 2>&1; then
  GITOK=0; GERR=""
  for i in 1 2; do
    GERR=$(timeout 40 git ls-remote https://github.com/NousResearch/hermes-agent HEAD 2>&1 >/dev/null | head -1)
    if [ -z "$GERR" ]; then GITOK=1; break; fi
    [ "$i" -eq 1 ] && echo "  ${Y}·${R} percobaan 1 gagal (${GERR:0:60}) — ulangi…"
  done
  [ "$GITOK" -eq 1 ] && row "git ls-remote" "${G}ok${R}" || row "git ls-remote" "${RED}gagal${R} ${GERR:0:48}"
else row "git ls-remote" "${Y}git belum terpasang${R}"; fi

echo; echo "  ◆ registry paket (update Hermes/OpenClaw)"
row "pypi.org" "$(curl -sS -o /dev/null -w '%{time_total}s' --max-time 20 https://pypi.org/simple/ 2>/dev/null || echo gagal)"
row "registry.npmjs.org" "$(curl -sS -o /dev/null -w '%{time_total}s' --max-time 20 https://registry.npmjs.org/ 2>/dev/null || echo gagal)"

echo; echo "  ◆ GitHub API"
RL=$(curl -sS --max-time 15 "$API/rate_limit" 2>/dev/null | tr -d ' ' | grep -o '"remaining":[0-9]*' | head -1 | cut -d: -f2)
row "sisa rate limit" "${RL:-?} / 60 (tanpa token, per jam)"

DONE=$(( $(date +%s) - T0 ))
echo
printf '  ─────────────────────────────────────────────────────────────\n'
printf '  %s\n' "${BOLD}KESIMPULAN${R}"
BEST=$TSPD; [ "${RAW_BEST:-0}" -gt "$BEST" ] && BEST=$RAW_BEST
if [ "${TSPD:-0}" -gt 0 ] && [ "${RAW_BEST:-0}" -gt 0 ] && [ "$TSPD" -lt $(( RAW_BEST / 5 )) ]; then
  printf '  %s\n' "${Y}▲ tidak konsisten${R}: raw $(mbps "$RAW_BEST") vs tarball $(mbps "$TSPD") — biasanya throttle CDN GitHub (IP sedang dibatasi) atau edge lambat; ulangi tes 1–2 menit lagi"
fi
if [ "${BEST:-0}" -ge 5242880 ]; then
  printf '  %s\n' "${G}✔ bagus${R} (≥5 MB/s) — clone/pip/npm bisa langsung dari server ini"
elif [ "${BEST:-0}" -ge 1048576 ]; then
  printf '  %s\n' "${Y}▲ sedang${R} (1–5 MB/s) — self-heal 5–15 menit, tunggu saja"
else
  printf '  %s\n' "${RED}✖ lambat${R} (<1 MB/s) — jangan git clone dari server ini; pakai relay:"
  printf '  %s\n' "   1) di mesin cepat: git clone --depth 1 https://github.com/NousResearch/hermes-agent"
  printf '  %s\n' "      tar czf hermes-src.tgz --exclude=.git --exclude=venv --exclude=node_modules -C hermes-agent ."
  printf '  %s\n' "   2) cat hermes-src.tgz | ssh root@IP-VM 'tar xzf - -C /root'"
  printf '  %s\n' "   3) di VM: hermes-upgrade.sh --repair-only --source-archive /root/hermes-src.tgz"
fi
printf '  durasi uji: %ss · jendela unduh: %ss · terbaik: %s\n' "$DONE" "$TL" "$(mbps "$BEST")"
