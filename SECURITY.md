# Security policy

## Supported versions

`rs-infra` is under active development. Only the latest commit on the default
branch is supported. Historical commits, branches, generated artifacts, and
deployed infrastructure that has not been reconciled with the default branch
are not supported.

## Reporting a vulnerability

Do not open a public issue, discussion, or pull request for a suspected
vulnerability.

Report it privately with a
[GitHub Security Advisory](https://github.com/ricardo-saad/rs-infra/security/advisories/new).
Include, when available:

- the affected file, component, resource, or workflow;
- the impact and conditions required to exploit it;
- steps to reproduce or a minimal proof of concept;
- whether exploitation or credential exposure has been observed; and
- a safe way to validate a proposed fix.

Do not include live credentials, private keys, secret values, personal data,
or unnecessary private infrastructure details. If sensitive evidence is
needed, first describe what you have and wait for a safe transfer method.

The maintainer will aim to acknowledge a report within 3 business days and
provide an initial assessment within 7 business days. Remediation and
disclosure timing depend on severity, affected providers, and deployment
safety. The reporter will receive updates when the assessment or timeline
materially changes.

If GitHub private vulnerability reporting is unavailable, open a public issue
containing no sensitive details and ask the maintainer to establish a private
channel.

## Scope

Reports are especially useful for:

- excessive AWS, Cloudflare, GitHub Actions, or workload permissions;
- paths that expose OIDC tokens, state, secrets, private inventory, or build
  provenance;
- unsafe Terraform state or plan handling;
- workflow injection or untrusted-fork privilege escalation;
- unsigned, unverifiable, or substitutable machine images and artifacts;
- weaknesses in bootstrap, recovery, rotation, or decommissioning tools; and
- configuration that unintentionally exposes platform services.

General hardening suggestions without a concrete security impact may be filed
as public issues. Vulnerabilities in third-party products should also be
reported to the relevant upstream maintainer.

## Safe research

Act in good faith and avoid:

- accessing, modifying, or retaining data that is not yours;
- disrupting services or infrastructure;
- persistence, lateral movement, social engineering, or denial of service;
- testing against production when a local demonstration is sufficient; and
- disclosing details before a fix and coordinated disclosure are ready.

Stop testing and report immediately if you encounter credentials, private
keys, personal data, private inventory, or evidence of active compromise.
Authorization to test this repository's source code does not grant
authorization to test deployed systems, third-party services, or accounts.

## Secrets committed to the repository

If you discover a committed secret, treat it as potentially compromised even
if it was later deleted. Report it privately. The response must revoke or
rotate the credential and assess its use; rewriting Git history alone does not
remove the risk.

