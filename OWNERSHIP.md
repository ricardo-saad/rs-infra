# Ownership contract

This document defines what `rs-infra` owns, who is accountable for changes,
and where work should go when it crosses a repository boundary.

## Mission

`rs-infra` owns the infrastructure and privileged bootstrap mechanisms needed
to operate RS Platform. Its job is to provision infrastructure safely and
expose narrowly scoped interfaces to the systems that deploy workloads.

The repository is not a general operations repository. Infrastructure code,
automation, and documentation belong here only when this repository can own
their complete lifecycle: design, review, deployment, recovery, and removal.

## Owned here

- Terraform for AWS and Cloudflare, including remote-state foundations.
- AWS IAM, KMS, secret containers, and workload-secret access paths.
- The private Talos cluster envelope, AWS-local node provisioner, and
  service-account federation.
- Signed machine images for the EC2 gateway and Ubuntu Core home nodes.
- Operator tools for the one-time Talos recovery seed and workload-secret
  rotation.
- The one-time Argo CD bootstrap.
- CI/CD and repository policy used to validate, plan, publish, or apply the
  preceding components.
- Repository-local operational documentation needed to change or recover
  these components safely.

Ownership includes decommissioning resources and maintaining a tested recovery
path; it does not end when a resource is first created.

## Not owned here

- Kubernetes workload manifests: `rs-cloud`.
- Application source or application deployment policy: the relevant
  application repository.
- Edge desired state: `rs-edge`.
- Stable cross-repository architecture, ADRs, coordinated cutover procedures,
  and cross-repository runbooks: the private `rs-platform` repository.
- Secret values or versions, generated private keys, Talos PKI, WireGuard key
  material, private inventory, or reusable authority: these must not be
  committed here or placed in Terraform state.

Terraform may create secret containers, policies, KMS keys, and references. It
must not create secret versions or render secret-bearing machine
configuration.

When a change spans repositories, the stable interface and rollout order must
be agreed in `rs-platform`; each repository then owns its side of the change.

## Accountable owner

The initial accountable owner is [@ricardo-saad](https://github.com/ricardo-saad).
The current review routing is recorded in [`.github/CODEOWNERS`](.github/CODEOWNERS).

The accountable owner is responsible for:

- maintaining repository access, rulesets, environments, and ownership rules;
- ensuring privileged changes receive an appropriate review;
- deciding whether a proposed component belongs in this repository;
- coordinating security response and infrastructure incidents;
- keeping bootstrap, recovery, and decommissioning procedures usable; and
- naming a replacement owner before relinquishing responsibility.

`CODEOWNERS` routes review but does not by itself enforce approval. Branch
protection or repository rulesets must require Code Owner review on protected
branches. No contributor may approve their own privileged production change.
While there is only one maintainer, such a change requires an explicitly
recorded exception or a second trusted reviewer before it is applied.

## Change contract

All persistent changes are made through pull requests. A change is ready to
merge only when:

1. its owner, blast radius, rollback or recovery path, and repository boundary
   are clear;
2. generated plans and artifacts are traceable to the reviewed commit;
3. required static checks and affected component tests pass;
4. the required Code Owners approve it; and
5. operator documentation is updated when operation or recovery changes.

Production applies must run from protected `main` through the designated
environment and must consume the exact reviewed plan. Emergency changes may
shorten the normal review path only when delay presents greater risk; they
must be documented and reconciled through a pull request immediately
afterward.

Changes to identity, trust policies, state backends, encryption, secret access,
network boundaries, protected environments, workflow permissions, ownership,
or this contract are privileged changes.

## Operational and security responsibility

The repository owner is the initial incident coordinator for infrastructure
failures and reports made under [`SECURITY.md`](SECURITY.md). During an
incident, containment and preservation of evidence take precedence over normal
delivery. Credentials suspected of exposure must be revoked or rotated outside
Git history; removing a committed value is not sufficient remediation.

Public issues may be used for non-sensitive defects and proposals. Suspected
vulnerabilities, exposed credentials, private inventory, and exploitable
configuration details must use the private reporting path in `SECURITY.md`.

## Updating this contract

Ownership changes require a pull request that updates this document and
`CODEOWNERS` together. If a change alters a cross-repository boundary, the
corresponding architecture decision in `rs-platform` must be updated first or
in the same coordinated rollout.

