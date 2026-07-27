# Talos recovery seed

This directory is reserved for the one-time operator command that generates
the Talos recovery bundle in memory and writes its first version to one exact
AWS Secrets Manager secret through a short-lived, MFA-backed role.

The command must refuse an existing `AWSCURRENT`, emit no secret material,
create no local file, and verify only value-free metadata. The seed role is
disabled after verification and is never available to CI, nodes, or the
steady-state provisioner. Implementation is planned.
