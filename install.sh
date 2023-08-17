#!/bin/sh
# SPDX-License-Identifier: 0BSD
# https://github.com/mchaNetwork/cla.sh

set -e
set -o noglob

cat /dev/null <<'EOF'
Environment variables:
- INSTALL_CLASH_BIN_DIR
Directory to install clash binary and uninstall script to, or use
/usr/local/bin as the default

- INSTALL_CLASH_CONFIG_DIR
Directory to install clash configuration files to, or use
/var/lib/clash as the default

- INSTALL_CLASH_SYSTEMD_DIR
Directory to install systemd service and environment files to, or use
/etc/systemd/system as the default

- INSTALL_CLASH_RELEASE_URL
URL to download clash binary from, or use
https://clash-release.b-cdn.net as the default

- INSTALL_CLASH_VERSION
Clash version to download and install, or use
latest as the default
EOF

cat /dev/null <<EOF
------------------------------------------------------------------------
https://github.com/client9/shlib - portable posix shell functions
Public domain - http://unlicense.org
https://github.com/client9/shlib/blob/master/LICENSE.md
but credit (and pull requests) appreciated.
------------------------------------------------------------------------
EOF
is_command() {
	command -v "$1" >/dev/null
}
uname_arch() {
	arch=$(uname -m)
	case $arch in
	x86_64) arch="amd64" ;;
	x86) arch="386" ;;
	i686) arch="386" ;;
	i386) arch="386" ;;
	aarch64) arch="arm64" ;;
	armv5*) arch="armv5" ;;
	armv6*) arch="armv6" ;;
	armv7*) arch="armv7" ;;
	esac
	echo "${arch}"
}
uname_os() {
	os=$(uname -s | tr '[:upper:]' '[:lower:]')
	case "$os" in
	msys*) os="windows" ;;
	mingw*) os="windows" ;;
	cygwin*) os="windows" ;;
	esac
	echo "$os"
}
untar() {
	tarball=$1
	case "${tarball}" in
	*.tar.gz | *.tgz) tar -xzf "${tarball}" ;;
	*.tar) tar -xf "${tarball}" ;;
	*.zip) unzip "${tarball}" ;;
	*)
		log_err "untar unknown archive format for ${tarball}"
		return 1
		;;
	esac
}
mktmpdir() {
	test -z "$TMPDIR" && TMPDIR="$(mktemp -d)"
	mkdir -p "${TMPDIR}"
	echo "${TMPDIR}"
}
echoerr() {
	echo "$@" 1>&2
}
log_prefix() {
	return
}
_logp=6
log_set_priority() {
	_logp="$1"
}
log_priority() {
	if test -z "$1"; then
		echo "$_logp"
		return
	fi
	[ "$1" -le "$_logp" ]
}
log_tag() {
	case $1 in
	0) echo "emerg" ;;
	1) echo "alert" ;;
	2) echo "crit" ;;
	3) echo "err" ;;
	4) echo "warning" ;;
	5) echo "notice" ;;
	6) echo "info" ;;
	7) echo "debug" ;;
	*) echo "$1" ;;
	esac
}
log_debug() {
	log_priority 7 || return 0
	echoerr "$(log_prefix)" "$(log_tag 7)" "$@"
}
log_info() {
	log_priority 6 || return 0
	echoerr "$(log_prefix)" "$(log_tag 6)" "$@"
}
log_err() {
	log_priority 3 || return 0
	echoerr "$(log_prefix)" "$(log_tag 3)" "$@"
}
log_crit() {
	log_priority 2 || return 0
	echoerr "$(log_prefix)" "$(log_tag 2)" "$@"
}
http_download_curl() {
	local_file=$1
	source_url=$2
	header=$3
	if [ -z "$header" ]; then
		code=$(curl -w '%{http_code}' -sL -o "$local_file" "$source_url")
	else
		code=$(curl -w '%{http_code}' -sL -H "$header" -o "$local_file" "$source_url")
	fi
	if [ "$code" != "200" ]; then
		log_debug "http_download_curl received HTTP status $code"
		return 1
	fi
	return 0
}
http_download_wget() {
	local_file=$1
	source_url=$2
	header=$3
	if [ -z "$header" ]; then
		wget -q -O "$local_file" "$source_url"
	else
		wget -q --header "$header" -O "$local_file" "$source_url"
	fi
}
http_download() {
	log_debug "http_download $2"
	if is_command curl; then
		http_download_curl "$@"
		return
	elif is_command wget; then
		http_download_wget "$@"
		return
	fi
	log_crit "http_download unable to find wget or curl"
	return 1
}
http_copy() {
	tmp=$(mktemp)
	http_download "${tmp}" "$1" "$2" || return 1
	cat "$tmp"
	rm -f "${tmp}"
}
cat /dev/null <<EOF
------------------------------------------------------------------------
End of functions from https://github.com/client9/shlib
------------------------------------------------------------------------
EOF

# --- helper functions for logs ---
info() {
	echo '[INFO] ' "$@"
}
warn() {
	echo '[WARN] ' "$@" >&2
}
fatal() {
	echo '[ERROR] ' "$@" >&2
	exit 1
}

# --- fatal if no systemd or openrc ---
verify_system() {
	case "$(uname_os)" in
	"linux")
		if [ "$(id -u)" -ne 0 ]; then
			fatal 'You need to be root to run this script'
		fi

		if [ -x /sbin/openrc-run ]; then
			HAS_OPENRC=true
			return
		fi
		if [ -x /bin/systemctl ] || is_command systemctl; then
			HAS_SYSTEMD=true
			return
		fi
		fatal 'Unsupported system. Can not find systemd or openrc to use as a process supervisor for clash'
		;;
	"darwin")
		fatal 'Unsupported system. You could try ClashX: https://github.com/yichengchen/clashX'
		;;
	"windows")
		fatal 'Unsupported system. You could try Clash Verge: https://github.com/zzzgydi/clash-verge'
		;;
	esac
	fatal 'Unknown system. You should proceed to manual installation'
}

# --- define needed environment variables ---
setup_env() {
	SYSTEM_NAME=clash
	BIN_DIR=${INSTALL_CLASH_BIN_DIR:-/usr/local/bin}
	CONFIG_DIR=${INSTALL_CLASH_CONFIG_DIR:-/var/lib/clash}

	# --- use systemd directory if defined or create default ---
	if [ -n "${INSTALL_CLASH_SYSTEMD_DIR}" ]; then
		SYSTEMD_DIR="${INSTALL_CLASH_SYSTEMD_DIR}"
	else
		SYSTEMD_DIR=/etc/systemd/system
	fi

	# --- set related files from system name ---
	SERVICE_CLASH=${SYSTEM_NAME}.service
	UNINSTALL_CLASH_SH=${UNINSTALL_CLASH_SH:-${BIN_DIR}/clash-uninstall.sh}

	# --- use service or environment location depending on systemd/openrc ---
	if [ "${HAS_SYSTEMD}" = true ]; then
		FILE_CLASH_SERVICE=${SYSTEMD_DIR}/${SERVICE_CLASH}
	elif [ "${HAS_OPENRC}" = true ]; then
		FILE_CLASH_SERVICE=/etc/init.d/${SYSTEM_NAME}
	fi

	# --- setup channel values
	INSTALL_CLASH_RELEASE_URL=${INSTALL_CLASH_RELEASE_URL:-'https://clash-release.b-cdn.net'}
	INSTALL_CLASH_VERSION=${INSTALL_CLASH_VERSION:-'latest'}
}

download_binary() {
	CLASH_ARCH="$(uname_arch)"
	if [ "$CLASH_ARCH" = "amd64" ]; then
		# check psabi
		grep "flags.*:" -m1 /proc/cpuinfo | cut -d':' -f2 | grep -q avx2 && CLASH_ARCH="amd64-v3"
	fi
	info "Detected architecture: ${CLASH_ARCH}"
	http_copy "${INSTALL_CLASH_RELEASE_URL}/${INSTALL_CLASH_VERSION}/clash-linux-${CLASH_ARCH}-${INSTALL_CLASH_VERSION}.gz" |
		gzip -d >"${BIN_DIR}/clash"
	info "Installed clash binary to ${BIN_DIR}/clash"
}

download_geoip() {
	http_download "${CONFIG_DIR}/Country.mmdb" "https://geoip.mcha.cloud/Country-no-game.mmdb"
}

download_ui() {
	mkdir -p "${CONFIG_DIR}/ui"
	http_copy "https://gh.chapro.xyz/github.com/haishanh/yacd/archive/refs/heads/gh-pages.tar.gz" |
		tar xzf - -C "${CONFIG_DIR}/ui" --strip-components=1
	info "Extraced yacd into ${CONFIG_DIR}/ui"
}

download_all() {
	download_binary
	download_geoip
	download_ui
}

create_config() {
	if [ ! -d "${CONFIG_DIR}" ]; then
		mkdir -p "${CONFIG_DIR}"
		mkdir -m 0700 "${CONFIG_DIR}/provider"
		mkdir "${CONFIG_DIR}/ruleset"
	fi
	if [ -f "${CONFIG_DIR}/config.yaml" ]; then
		warn "config.yaml already exists, skipping"
		return
	else
		cat <<'EOF' >"${CONFIG_DIR}/config.yaml"
mode: rule

mixed-port: 7890
redir-port: 7899

# allow-lan: true
bind-address: '127.0.0.1'

log-level: warning

# ipv6: false

external-controller: 127.0.0.1:9090
# secret: "mchaNtwk"
external-ui: ui

# interface-name: eno1

hosts:
  'services.googleapis.cn': 74.125.193.94
  'time.android.com': 203.107.6.88
  'ipv6.msftconnecttest.com': 2a01:111:2003::52 # locked
  'www.msftconnecttest.com': 13.107.4.52 # locked

profile:
  store-selected: true
  store-fake-ip: true

dns:
  enable: true
  listen: 127.0.0.90:53
  # ipv6: false

  default-nameserver: # bootstrap servers
    - 223.5.5.5
    - 180.76.76.76

  enhanced-mode: fake-ip
  # fake-ip-range: 198.18.0.1/16
  use-hosts: true
  fake-ip-filter:
    - '*.lan'
    - '*.linksys.com'
    - '*.linksyssmartwifi.com'
    - 'router.asus.com'
    - '+.neverssl.com'
    - 'swscan.apple.com'
    - 'mesu.apple.com'
    - '*.msftconnecttest.com'
    - '*.msftncsi.com'
    - 'time.*.com'
    - 'time.*.gov'
    - 'time.*.edu.cn'
    - 'time.*.apple.com'
    - 'time1.*.com'
    - 'time2.*.com'
    - 'time3.*.com'
    - 'time4.*.com'
    - 'time5.*.com'
    - 'time6.*.com'
    - 'time7.*.com'
    - 'ntp.*.com'
    - 'ntp.*.com'
    - 'ntp1.*.com'
    - 'ntp2.*.com'
    - 'ntp3.*.com'
    - 'ntp4.*.com'
    - 'ntp5.*.com'
    - 'ntp6.*.com'
    - 'ntp7.*.com'
    - '*.time.edu.cn'
    - '*.ntp.org.cn'
    - '+.pool.ntp.org'
    - 'time1.cloud.tencent.com'
    - 'stun.*.*'
    - 'stun.*.*.*'
    - '+.srv.nintendo.net'
    - '+.stun.playstation.net'
    - 'xbox.*.microsoft.com'
    - '+.xboxlive.com'
    - 'localhost.ptlogin2.qq.com'
    - 'proxy.golang.org'
    # - '+.*' ##! Enable the obsolete redir-host mode, ignores fake-ip. Must enable sniff-tls-sni in this case

##! Enable this if your host have the performance & you don't run SNI proxy
# experimental:
#   sniff-tls-sni: true

  nameserver:
    - tls://dns.qvq.network:853
    - tls://loli.sese.network:853
    - https://101.6.6.6:8443/dns-query # TUNA DNS

  # fake-ip will resolve domain remotely, not needed
  # fallback:
  #   - tls://loli.sese.network:853
  #   - https://101.6.6.6:8443/dns-query # TUNA DNS
  #   - tls://8.8.8.8:853

tun:
  enable: true
  stack: system
  auto-route: true
  auto-redir: true
  auto-detect-interface: true
  # dns-hijack:
  #   - 198.18.0.2:53

proxies:
  # empty, see proxy-providers

proxy-groups:
  - name: Proxy
    type: select
    # disable-udp: true
    # interface-name: en1
    use:
      - service
      - misc

  - name: Adblock
    type: select
    proxies:
      - REJECT
      - Proxy
      - DIRECT

  - name: Geowall
    type: select
    proxies:
      - Proxy
      - DIRECT
    use:
      - service
      - misc

  - name: Game
    type: select
    proxies:
      - Proxy
      - DIRECT
    use:
      - service
      - misc

  - name: Steam
    type: select
    proxies:
      - Proxy
      - DIRECT
    use:
      - service
      - misc

  - name: PayPal
    type: select
    proxies:
      - DIRECT
      - Proxy
    use:
      - service
      - misc

  - name: Telegram
    type: select
    proxies:
      - Proxy
    use:
      - service
      - misc

proxy-providers:
  service: ##! your service provider
    type: http
    url: "https://example.invalid/proxy.yaml" ##! change this to your real subscription URL
    interval: 3600
    path: ./provider/service.yaml
    health-check:
      enable: true
      interval: 3600
      url: http://cp.cloudflare.com/generate_204
  misc:
    type: file
    path: ./provider/misc.yaml ##! local provider
    health-check:
      enable: true
      interval: 3600
      url: http://cp.cloudflare.com/generate_204
rule-providers:
  reject:
    type: http
    behavior: domain
    url: "https://gh.chapro.xyz/raw.githubusercontent.com/privacy-protection-tools/anti-AD/master/anti-ad-clash.yaml"
    path: ./ruleset/reject.yaml
    interval: 86400
  direct:
    type: http
    behavior: domain
    url: "https://geosite.mcha.cloud/cn.yaml"
    path: ./ruleset/direct.yaml
    interval: 86400
  private:
    type: http
    behavior: domain
    url: "https://geosite.mcha.cloud/private.yaml"
    path: ./ruleset/private.yaml
    interval: 86400
  unbreak:
    type: http
    behavior: domain
    url: "https://gh.chapro.xyz/raw.githubusercontent.com/mchaNetwork/rules/master/clash/unbreak.yaml"
    path: ./ruleset/unbreak.yaml
    interval: 86400
  steam:
    type: http
    behavior: domain
    url: "https://gh.chapro.xyz/raw.githubusercontent.com/mchaNetwork/rules/master/clash/steam.yaml"
    path: ./ruleset/steam.yaml
    interval: 86400
  paypal:
    type: http
    behavior: domain
    url: "https://gh.chapro.xyz/raw.githubusercontent.com/mchaNetwork/rules/master/clash/paypal.yaml"
    path: ./ruleset/paypal.yaml
    interval: 86400

rules:
  # - SCRIPT,quic,REJECT
  - RULE-SET,unbreak,Proxy
  - RULE-SET,private,DIRECT
  - RULE-SET,reject,Adblock
  # - RULE-SET,steam,Steam
  - RULE-SET,paypal,PayPal
  - DOMAIN-SUFFIX,openai.com,Geowall
  - DOMAIN-KEYWORD,google,Geowall
  - DOMAIN-KEYWORD,bing,Geowall
  # - GEOIP,GAME,Game
  - RULE-SET,direct,DIRECT
  - GEOIP,TELEGRAM,Telegram
  - GEOIP,PRIVATE,DIRECT
  - GEOIP,CN,DIRECT
  - PROCESS-NAME,tailscaled,DIRECT
  - PROCESS-NAME,croc,DIRECT
  - MATCH,Proxy

script:
  shortcuts:
    quic: network == 'udp' and dst_port == 443
EOF
	fi
	info "Config file has been generated at ${CONFIG_DIR}/config.yaml"
	info "Search ##! in the file to see what to modify"
}

create_systemd_service_file() {
	cat <<"EOF" >"${FILE_CLASH_SERVICE}"
[Unit]
Description=A rule based proxy in Go.
After=network-online.target

[Service]
Type=simple
LimitNOFILE=65535
Restart=on-abort
ExecStart=${BIN_DIR}/clash -d ${CONFIG_DIR}

[Install]
WantedBy=multi-user.target
EOF
	systemctl daemon-reload
}

create_openrc_service_file() {
	cat <<"EOF" >"${FILE_CLASH_SERVICE}"
#!/sbin/openrc-run

command="${BIN_DIR}/clash"
command_args="-d ${CONFIG_DIR}"
command_background=true
pidfile="/run/\$RC_SVCNAME.pid"

depend() {
  need net
  use dns logger netmount
}
EOF
}

# --- write systemd or openrc service file ---
create_service_file() {
	if [ "${HAS_SYSTEMD}" = true ]; then
		create_systemd_service_file
	elif [ "${HAS_OPENRC}" = true ]; then
		create_openrc_service_file
	fi
	info "System service installed to ${FILE_CLASH_SERVICE}"
}

create_uninstall() {
	info "Creating uninstall script ${UNINSTALL_CLASH_SH}"
	cat <<"EOF" >"${UNINSTALL_CLASH_SH}"
#!/bin/sh
set -x
[ \$(id -u) -eq 0 ] || exit 2

if command -v systemctl; then
    systemctl disable ${SYSTEM_NAME}
    systemctl reset-failed ${SYSTEM_NAME}
    systemctl daemon-reload
fi
if command -v rc-update; then
    rc-update delete ${SYSTEM_NAME} default
fi

remove_uninstall() {
    rm -f ${UNINSTALL_CLASH_SH}
}

trap remove_uninstall EXIT

rm -f "${FILE_CLASH_SERVICE}"
rm -f "${BIN_DIR}/clash"
EOF
	chmod 755 "${UNINSTALL_CLASH_SH}"
}

# --- run the installation process ---
{
	verify_system
	setup_env
	create_config
	create_service_file
	download_all
	create_uninstall

	info "\
Installation finished!

Clash binary has been installed to ${BIN_DIR}
Default config directory is located at ${CONFIG_DIR}
To update your installation just run this script again
"
}
