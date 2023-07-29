#!/bin/sh

BASEDIR="${BASEDIR:-/var/lib/clash}"
BINDIR="${BINDIR:-/usr/local/bin}"

cd $BASEDIR || exit 1

getarch() {
machine=$(uname -ms | tr ' ' '_' | tr '[A-Z]' '[a-z]')
[ -n "$(echo $machine | grep -E "linux.*armv.*")" ] && arch="armv5"
[ -n "$(echo $machine | grep -E "linux.*armv7.*")" ] && [ -n "$(cat /proc/cpuinfo | grep vfp)" ] && [ ! -d /jffs/clash ] && arch="armv7"
[ -n "$(echo $machine | grep -E "linux.*aarch64.*|linux.*armv8.*")" ] && arch="arm64"
[ -n "$(echo $machine | grep -E "linux.*86.*")" ] && arch="386"
[ -n "$(echo $machine | grep -E "linux.*86_64.*")" ] && arch="amd64-v3"
if [ -n "$(echo $machine | grep -E "linux.*mips.*")" ];then
mips=$(echo -n I | hexdump -o 2>/dev/null | awk '{ print substr($2,6,1); exit}')
[ "$mips" = "0" ] && arch="mips-softfloat" || arch="mipsle-softfloat"
fi
echo $arch
}

update_binary() {
echo "[clash] fetching core"
curl -L --progress-bar "https://clash-release.b-cdn.net/latest/clash-linux-$(getarch)-latest.gz" | gzip -d > "${BINDIR}/clash"
chmod +x "${BINDIR}/clash"
}

update_geoip() {
echo "[clash] fetching geoip"
curl -L --progress-bar "https://geoip.mcha.cloud/Country-no-game.mmdb" -o Country.mmdb
}

update_dashboard() {
echo "[clash] fetching external-ui"
curl -L --progress-bar "https://gh.chapro.xyz/github.com/haishanh/yacd/archive/refs/heads/gh-pages.tar.gz" | tar xzf - -C "${BASEDIR}"
rm -rf "${BASEDIR}/ui"
mv "${BASEDIR}/yacd-gh-pages" "${BASEDIR}/ui"
}

# case
case $1 in
"binary")
update_binary
;;
"geoip")
update_geoip
;;
"dashboard")
update_dashboard
;;
"all")
update_binary
update_geoip
update_dashboard
;;
*)
echo "Usage: $0 [all|binary|geoip|dashboard]"
;;
esac
