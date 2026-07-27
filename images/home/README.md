# Home image

This directory is reserved for the signed Ubuntu Core image used by generic
home nodes: model and gadget inputs, the reproducible image build, and QEMU
boot tests.

Only public, reusable build inputs belong here. Model-signing authority,
device identity, private inventory, enrollment tokens, and generated images
must remain outside Git. Implementation is planned; the signing-key custody
and exact build contract remain open in the platform blueprint.
