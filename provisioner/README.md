# Talos node provisioner

This directory is reserved for the AWS-local state machine that owns the
lifecycle of exactly three declared Talos control-plane slots.

The provisioner will read one exact recovery bundle, render and validate
unique machine configuration in memory, pass it directly as EC2 user data,
and persist only value-free lock and status evidence. It must not expose
Talos or Kubernetes to CI, write rendered configuration to durable storage or
logs, affect undeclared instances, or attempt automatic recovery after quorum
loss.

Implementation is planned. The language, service selection, and health
timeouts remain intentionally unresolved.
