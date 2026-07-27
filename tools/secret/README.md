# Workload secret tool

This directory is reserved for the operator-only command that creates and
rotates standard-tier AWS Systems Manager `SecureString` parameters under the
approved `/cluster/` and `/home/` lanes using the exact KMS key and
path-scoped role.

The command must accept plaintext without command-line arguments and must not
print, log, or persist it. Terraform and CI never handle parameter values.
Implementation is planned; input ergonomics remain an open design item.
