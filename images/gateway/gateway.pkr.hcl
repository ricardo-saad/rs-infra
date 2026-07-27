packer {
  required_version = ">= 1.10.0"
}

variable "region" {
  type    = string
  default = "eu-west-2"
}

variable "source_ami" {
  type = string
  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.source_ami))
    error_message = "source_ami must be an immutable AMI ID."
  }
}

variable "instance_type" {
  type    = string
  default = "t4g.micro"
}

variable "root_volume_size" {
  type = number
  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GiB."
  }
}

variable "build_version" {
  type = string
}

variable "wireguard_version" {
  type = string
}

variable "nftables_version" {
  type = string
}

variable "apt_repository" {
  type = string
}

variable "adguardhome_archive_url" {
  type = string
}

variable "adguardhome_archive_sha256" {
  type = string
  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.adguardhome_archive_sha256))
    error_message = "adguardhome_archive_sha256 must be an exact SHA-256 digest."
  }
}

variable "adguard_schema_version" {
  type = number
}

variable "adguard_upstream_dns" {
  type = string
}

variable "adguard_filter_name" {
  type = string
}

variable "adguard_filter_url" {
  type = string
}

variable "awscli_version" {
  type = string
}

variable "apache2_utils_version" {
  type = string
}

variable "curl_version" {
  type = string
}

variable "ca_certificates_version" {
  type = string
}

variable "python3_version" {
  type = string
}

source "amazon-ebs" "gateway" {
  ami_name                    = "rs-gateway-${var.build_version}"
  ami_description             = "RS Platform immutable gateway ${var.build_version}"
  architecture                = "arm64"
  associate_public_ip_address = true
  ena_support                 = true
  instance_type               = var.instance_type
  region                      = var.region
  source_ami                  = var.source_ami
  ssh_username                = "ubuntu"

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    delete_on_termination = true
    encrypted             = true
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
  }

  tags = {
    "Name"             = "rs-gateway-${var.build_version}"
    "rs:component"     = "gateway"
    "rs:build-version" = var.build_version
  }
}

build {
  name    = "gateway"
  sources = ["source.amazon-ebs.gateway"]

  provisioner "file" {
    source      = "rootfs"
    destination = "/tmp/rs-gateway-rootfs"
  }

  provisioner "shell" {
    environment_vars = [
      "WIREGUARD_VERSION=${var.wireguard_version}",
      "NFTABLES_VERSION=${var.nftables_version}",
      "APT_REPOSITORY=${var.apt_repository}",
      "ADGUARDHOME_ARCHIVE_URL=${var.adguardhome_archive_url}",
      "ADGUARDHOME_ARCHIVE_SHA256=${var.adguardhome_archive_sha256}",
      "ADGUARD_SCHEMA_VERSION=${var.adguard_schema_version}",
      "ADGUARD_UPSTREAM_DNS=${var.adguard_upstream_dns}",
      "ADGUARD_FILTER_NAME=${var.adguard_filter_name}",
      "ADGUARD_FILTER_URL=${var.adguard_filter_url}",
      "AWSCLI_VERSION=${var.awscli_version}",
      "APACHE2_UTILS_VERSION=${var.apache2_utils_version}",
      "CURL_VERSION=${var.curl_version}",
      "CA_CERTIFICATES_VERSION=${var.ca_certificates_version}",
      "PYTHON3_VERSION=${var.python3_version}",
      "BUILD_VERSION=${var.build_version}",
    ]
    execute_command = "chmod +x {{ .Path }}; sudo -E {{ .Vars }} {{ .Path }}"
    script          = "scripts/install.sh"
  }
}
