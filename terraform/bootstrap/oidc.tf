# AWS trusts GitHub's own root CA library for this well-known provider, so no
# thumbprint_list is configured; see hashicorp/terraform-provider-aws#37255.
resource "aws_iam_openid_connect_provider" "github_actions" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  tags = {
    Name = "${local.name_prefix}-github-actions"
  }
}
