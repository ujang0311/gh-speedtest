# gh-speedtest — uji koneksi & kecepatan GitHub

Satu perintah, tanpa dependensi (cuma `curl`, opsional `git`) untuk mengukur **latensi, throughput, git protocol, dan registry paket** dari sebuah server. Dipakai sebelum menjalankan upgrade/restore Agent (Hermes/OpenClaw) supaya tahu apakah jalur GitHub server itu baik atau perlu relay.

```bash
curl -sS https://raw.githubusercontent.com/ujang0311/gh-speedtest/main/gh-speedtest.sh | bash
```

Opsi:

```bash
# uji unduh lebih lama (~120 s) untuk angka throughput lebih stabil
curl -sS https://raw.githubusercontent.com/ujang0311/gh-speedtest/main/gh-speedtest.sh | bash -s -- --big

# ringkas
curl -sS https://raw.githubusercontent.com/ujang0311/gh-speedtest/main/gh-speedtest.sh | bash -s -- --quiet
```

Yang diuji:

| Bagian | Yang diukur | Arti |
|---|---|---|
| Jaringan dasar | DNS, TCP :443, TLS handshake, `api.github.com/zen` | kalau gagal di sini → firewall/DNS, bukan kecepatan |
| `raw.githubusercontent.com` | unduh kecil + latensi | jalur yang dipakai `curl … \| bash` |
| `codeload.github.com` | MB/s unduh tarball | angka utama: menentukan layak/tidak `git clone` di server itu |
| git protocol | `git ls-remote` (HTTPS 443) | jalur `git fetch`/`git clone` |
| registry paket | `pypi.org`, `registry.npmjs.org` | jalur `pip install` / `npm i -g` |
| GitHub API | sisa rate limit (unauth: 60/jam) | jalur `api.github.com/.../contents/...` |

Catatan: angka jalur `codeload` bisa naik-turun karena CDN GitHub membatasi (throttle) per IP setelah unduhan besar — script sudah mencoba **3x** (raw) dan **2x** (tarball + `git ls-remote`), lalu memberi tahu bila hasilnya tidak konsisten. Kalau ragu, ulangi 1–2 menit lagi.

Patokan hasil:

- **≥5 MB/s** → jalur GitHub bagus, clone/pip/npm aman langsung.
- **1–5 MB/s** → sedang; self-heal bisa 5–15 menit, tunggu saja.
- **<1 MB/s** → lambat; jangan `git clone` dari server itu. Pakai relay (di bawah).

Relay source untuk server dengan GitHub lambat:

```bash
# 1) di mesin dengan jaringan bagus
git clone --depth 1 https://github.com/NousResearch/hermes-agent
tar czf hermes-src.tgz --exclude=.git --exclude=venv --exclude=node_modules -C hermes-agent .

# 2) kirim ke server (kalau scp ditolak, pakai pipe SSH)
cat hermes-src.tgz | ssh root@IP-VM 'tar xzf - -C /root'

# 3) di server tujuan
curl -sS https://raw.githubusercontent.com/ujang0311/hermes-tools/main/hermes-upgrade.sh \
  | bash -s -- --repair-only --source-archive /root/hermes-src.tgz
```

Tes cepat tanpa script (paste saja):

```bash
curl -sS -o /dev/null -w 'api   %{time_total}s\n' https://api.github.com/zen
curl -sS -o /dev/null -w 'raw   %{speed_download} B/s\n' https://raw.githubusercontent.com/ujang0311/gh-speedtest/main/payload.txt
curl -sSL --max-time 30 -o /dev/null -w 'tar   %{speed_download} B/s (%{size_download} B)\n' \
  https://codeload.github.com/NousResearch/hermes-agent/tar.gz/refs/heads/main
git ls-remote https://github.com/NousResearch/hermes-agent HEAD | head -1
```
