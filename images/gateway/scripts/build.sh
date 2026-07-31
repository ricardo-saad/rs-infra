#!/bin/sh
set -eu

required_variables='
PACKER_AMAZON_PLUGIN_VERSION
RS_GATEWAY_PACKER_VERSION
RS_GATEWAY_SESSION_MANAGER_PLUGIN_VERSION
RS_GATEWAY_SOURCE_AMI
RS_GATEWAY_SOURCE_AMI_OWNER
RS_GATEWAY_BUILD_SUBNET_ID
RS_GATEWAY_BUILDER_INSTANCE_PROFILE
RS_GATEWAY_ROOT_VOLUME_SIZE
RS_GATEWAY_WIREGUARD_VERSION
RS_GATEWAY_NFTABLES_VERSION
RS_GATEWAY_APT_REPOSITORY
RS_GATEWAY_ADGUARD_ARCHIVE_URL
RS_GATEWAY_ADGUARD_ARCHIVE_SHA256
RS_GATEWAY_ADGUARD_SCHEMA_VERSION
RS_GATEWAY_ADGUARD_UPSTREAM_DNS
RS_GATEWAY_ADGUARD_FILTER_NAME
RS_GATEWAY_ADGUARD_FILTER_URL
RS_GATEWAY_AWSCLI_VERSION
RS_GATEWAY_APACHE2_UTILS_VERSION
RS_GATEWAY_CURL_VERSION
RS_GATEWAY_CA_CERTIFICATES_VERSION
RS_GATEWAY_PYTHON3_VERSION
RS_GATEWAY_SSM_AGENT_REVISION
RS_GATEWAY_BUILD_VERSION
'

for variable_name in $required_variables; do
  eval "variable_value=\${$variable_name-}"
  if [ -z "$variable_value" ]; then
    echo "required variable is unset: $variable_name" >&2
    exit 2
  fi
done

if [ "$(packer version | awk 'NR == 1 { sub(/^v/, \"\", $2); print $2 }')" != \
     "$RS_GATEWAY_PACKER_VERSION" ]; then
  echo "installed Packer does not match RS_GATEWAY_PACKER_VERSION" >&2
  exit 2
fi

if ! command -v session-manager-plugin >/dev/null 2>&1; then
  echo "AWS Session Manager plugin is required for the ingress-free build" >&2
  exit 2
fi
if [ "$(session-manager-plugin --version)" != \
     "$RS_GATEWAY_SESSION_MANAGER_PLUGIN_VERSION" ]; then
  echo "installed Session Manager plugin does not match its approved version" >&2
  exit 2
fi

image_metadata="$(
  aws ec2 describe-images \
    --region eu-west-2 \
    --image-ids "$RS_GATEWAY_SOURCE_AMI" \
    --query 'Images[0].[OwnerId,Architecture,ImageId,Name]' \
    --output text
)"
set -- $image_metadata
if [ "$#" -ne 4 ] ||
   [ "$RS_GATEWAY_SOURCE_AMI_OWNER" != "099720109477" ] ||
   [ "$1" != "099720109477" ] ||
   [ "$2" != "arm64" ] ||
   [ "$3" != "$RS_GATEWAY_SOURCE_AMI" ]; then
  echo "source AMI owner, architecture, or immutable ID did not match" >&2
  exit 2
fi
case "$4" in
  ubuntu/images/hvm-ssd-gp3/ubuntu-resolute-26.04-arm64-server-*) ;;
  *)
    echo "source AMI is not Canonical Ubuntu Server 26.04 LTS ARM64 gp3" >&2
    exit 2
    ;;
esac

if [ "$(
  aws ec2 describe-subnets \
    --region eu-west-2 \
    --subnet-ids "$RS_GATEWAY_BUILD_SUBNET_ID" \
    --query 'Subnets[0].State' \
    --output text
)" != "available" ]; then
  echo "gateway image build subnet is not available in eu-west-2" >&2
  exit 2
fi

if [ "$(
  aws iam get-instance-profile \
    --instance-profile-name "$RS_GATEWAY_BUILDER_INSTANCE_PROFILE" \
    --query 'InstanceProfile.InstanceProfileName' \
    --output text
)" != "$RS_GATEWAY_BUILDER_INSTANCE_PROFILE" ]; then
  echo "gateway image builder instance profile did not match" >&2
  exit 2
fi

packer plugins install \
  --version "$PACKER_AMAZON_PLUGIN_VERSION" \
  github.com/hashicorp/amazon

packer build \
  -var "source_ami=$RS_GATEWAY_SOURCE_AMI" \
  -var "build_subnet_id=$RS_GATEWAY_BUILD_SUBNET_ID" \
  -var "builder_instance_profile=$RS_GATEWAY_BUILDER_INSTANCE_PROFILE" \
  -var "root_volume_size=$RS_GATEWAY_ROOT_VOLUME_SIZE" \
  -var "wireguard_version=$RS_GATEWAY_WIREGUARD_VERSION" \
  -var "nftables_version=$RS_GATEWAY_NFTABLES_VERSION" \
  -var "apt_repository=$RS_GATEWAY_APT_REPOSITORY" \
  -var "adguardhome_archive_url=$RS_GATEWAY_ADGUARD_ARCHIVE_URL" \
  -var "adguardhome_archive_sha256=$RS_GATEWAY_ADGUARD_ARCHIVE_SHA256" \
  -var "adguard_schema_version=$RS_GATEWAY_ADGUARD_SCHEMA_VERSION" \
  -var "adguard_upstream_dns=$RS_GATEWAY_ADGUARD_UPSTREAM_DNS" \
  -var "adguard_filter_name=$RS_GATEWAY_ADGUARD_FILTER_NAME" \
  -var "adguard_filter_url=$RS_GATEWAY_ADGUARD_FILTER_URL" \
  -var "awscli_version=$RS_GATEWAY_AWSCLI_VERSION" \
  -var "apache2_utils_version=$RS_GATEWAY_APACHE2_UTILS_VERSION" \
  -var "curl_version=$RS_GATEWAY_CURL_VERSION" \
  -var "ca_certificates_version=$RS_GATEWAY_CA_CERTIFICATES_VERSION" \
  -var "python3_version=$RS_GATEWAY_PYTHON3_VERSION" \
  -var "ssm_agent_revision=$RS_GATEWAY_SSM_AGENT_REVISION" \
  -var "build_version=$RS_GATEWAY_BUILD_VERSION" \
  gateway.pkr.hcl
