variable "aws_region" {
  description = "The region to deploy the resources into"
  type        = string
}

variable "github_username" {
  description = "The GitHub username"
  type        = string
}

variable "github_token" {
  description = "The GitHub personal access token"
  type        = string
  sensitive   = true
}

variable "github_repository" {
  description = "The GitHub repository name"
  type        = string
}

variable "github_branch" {
  description = "The GitHub branch name"
  type        = string
}

variable "aws_account_id" {
  description = "The AWS account ID"
  type        = string
}