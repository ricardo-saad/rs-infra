# Argo CD bootstrap

This directory is reserved for the one-time Argo CD installation and root
application bootstrap after the private Talos cluster is healthy.

It contains no application workload manifests; ongoing desired state belongs
in `rs-cloud`. GitHub CI receives no Talos or Kubernetes identity through this
bootstrap. Implementation is planned and follows the platform bootstrap
order.
