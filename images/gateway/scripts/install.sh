#!/bin/sh
set -eu

: "${WIREGUARD_VERSION:?}"
: "${NFTABLES_VERSION:?}"
: "${APT_REPOSITORY:?}"
: "${ADGUARDHOME_ARCHIVE_URL:?}"
: "${ADGUARDHOME_ARCHIVE_SHA256:?}"
: "${ADGUARD_SCHEMA_VERSION:?}"
: "${ADGUARD_UPSTREAM_DNS:?}"
: "${ADGUARD_FILTER_NAME:?}"
: "${ADGUARD_FILTER_URL:?}"
: "${AWSCLI_VERSION:?}"
: "${APACHE2_UTILS_VERSION:?}"
: "${CURL_VERSION:?}"
: "${CA_CERTIFICATES_VERSION:?}"
: "${PYTHON3_VERSION:?}"
: "${SSM_AGENT_REVISION:?}"
: "${BUILD_VERSION:?}"

export DEBIAN_FRONTEND=noninteractive
rm -f /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources
printf '%s\n' "$APT_REPOSITORY" >/etc/apt/sources.list
apt-get update
apt-get install --no-install-recommends -y \
  "wireguard-tools=$WIREGUARD_VERSION" \
  "nftables=$NFTABLES_VERSION" \
  "awscli=$AWSCLI_VERSION" \
  "apache2-utils=$APACHE2_UTILS_VERSION" \
  "curl=$CURL_VERSION" \
  "ca-certificates=$CA_CERTIFICATES_VERSION" \
  "python3=$PYTHON3_VERSION"

curl --fail --location --proto '=https' --tlsv1.2 \
  "$ADGUARDHOME_ARCHIVE_URL" \
  --output /tmp/adguardhome.tar.gz
printf '%s  %s\n' "$ADGUARDHOME_ARCHIVE_SHA256" /tmp/adguardhome.tar.gz \
  | sha256sum --check --strict
tar --extract --gzip --file /tmp/adguardhome.tar.gz --directory /tmp
install -m 0755 /tmp/AdGuardHome/AdGuardHome /usr/local/bin/AdGuardHome
rm -rf /tmp/AdGuardHome /tmp/adguardhome.tar.gz

install -d -m 0755 /etc/rs-gateway
install -d -m 0755 /usr/lib/rs-gateway
install -d -m 0755 /var/lib/rs-gateway/desired
install -d -m 0700 /var/lib/rs-gateway/applied
install -d -m 0700 /var/lib/rs-gateway/adguard

python3 -c '
import json
import os
import pathlib

config = {
    "schema_version": int(os.environ["ADGUARD_SCHEMA_VERSION"]),
    "upstream_dns": os.environ["ADGUARD_UPSTREAM_DNS"],
    "filter_name": os.environ["ADGUARD_FILTER_NAME"],
    "filter_url": os.environ["ADGUARD_FILTER_URL"],
}
path = pathlib.Path("/etc/rs-gateway/adguard-build.json")
path.write_text(json.dumps(config, sort_keys=True) + "\n", encoding="utf-8")
path.chmod(0o644)
'

cp -a /tmp/rs-gateway-rootfs/. /
printf '%s\n' "$BUILD_VERSION" >/etc/rs-gateway/image-build-version

chmod 0755 /usr/lib/rs-gateway/*.py /usr/lib/rs-gateway/*.sh
chmod 0644 /usr/lib/rs-gateway/schemas/*.json
chmod 0600 /etc/rs-gateway/runtime.env

installed_ssm_revision="$(snap list amazon-ssm-agent | awk 'NR == 2 { print $3 }')"
if [ "$installed_ssm_revision" != "$SSM_AGENT_REVISION" ]; then
  echo "installed SSM Agent revision does not match the approved revision" >&2
  exit 2
fi
snap start --enable amazon-ssm-agent
snap refresh --hold=forever amazon-ssm-agent

systemctl disable --now wg-quick@wg-users.service \
  wg-quick@wg-personal.service wg-quick@wg-nodes.service 2>/dev/null || true
systemctl disable rs-gateway-bootstrap.service
systemctl enable rs-gateway.target

systemctl disable --now ssh.service 2>/dev/null || true
apt-get purge -y openssh-server
rm -rf /etc/ssh/sshd_config.d
openssh_status="$(
  dpkg-query -W -f='${db:Status-Status}' openssh-server 2>/dev/null || true
)"
if [ "$openssh_status" = "installed" ]; then
  echo "OpenSSH server remained installed in the final image" >&2
  exit 2
fi

apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/rs-gateway-rootfs
