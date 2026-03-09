# =============================================================================
# Harness Custom Tools - Delegate & CI Runner
# 
# Build targets:
#   - delegate: Extends official Harness delegate with cloud CLIs
#   - ci: Standalone CI runner image with full toolchain
#
# Usage:
#   docker build --build-arg BASE_IMAGE=harness/delegate:25.02.85600.minimal-fips --target delegate -t custom-delegate .
#   docker build --target ci -t harness-custom-runner .
# =============================================================================

# Global ARG - must be before any FROM to be used in FROM instructions
ARG BASE_IMAGE=harness/delegate:latest

# -----------------------------------------------------------------------------
# Stage 1: Tooling - Build all tools in Ubuntu for compatibility
# -----------------------------------------------------------------------------
FROM ubuntu:22.04 AS tooling

ENV DEBIAN_FRONTEND=noninteractive \
    PIPX_BIN_DIR=/usr/local/bin \
    PIPX_HOME=/opt/pipx \
    PATH=/opt/pipx/bin:$PATH

# =============================================================================
# Tool Versions (stable as of March 2025)
# =============================================================================
ARG TERRAFORM_VERSION=1.10.5
ARG TOFU_VERSION=1.9.1
ARG TERRAGRUNT_VERSION=0.72.6
ARG TFLINT_VERSION=0.55.1
ARG AWS_CLI_VERSION=2.27.22
ARG GCLOUD_VERSION=515.0.0
ARG KUBECTL_VERSION=1.32.3
ARG HELM_VERSION=3.17.1
ARG KUSTOMIZE_VERSION=5.6.0
ARG YQ_VERSION=4.45.1
ARG ARGOCD_VERSION=2.14.4

# Core build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    unzip \
    gnupg \
    ca-certificates \
    apt-transport-https \
    software-properties-common \
    python3 \
    python3-pip \
    python3-venv \
    jq \
    git \
    make \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Infrastructure as Code Tools
# =============================================================================

# Terraform
RUN wget -q https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    && unzip -q terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    && mv terraform /usr/local/bin/ \
    && rm -f terraform_*.zip

# OpenTofu (Terraform alternative)
RUN wget -q https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_amd64.zip \
    && unzip -q tofu_${TOFU_VERSION}_linux_amd64.zip \
    && mv tofu /usr/local/bin/ \
    && rm -f tofu_*.zip

# Terragrunt
RUN wget -q https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/terragrunt_linux_amd64 \
    -O /usr/local/bin/terragrunt \
    && chmod +x /usr/local/bin/terragrunt

# TFLint
RUN curl -fsSL -o /tmp/tflint.zip \
    "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_amd64.zip" \
    && unzip -q /tmp/tflint.zip -d /usr/local/bin \
    && rm -f /tmp/tflint.zip

# =============================================================================
# Cloud Provider CLIs
# =============================================================================

# AWS CLI v2
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWS_CLI_VERSION}.zip" -o awscliv2.zip \
    && unzip -q awscliv2.zip \
    && ./aws/install --install-dir /opt/aws-cli --bin-dir /usr/local/bin \
    && rm -rf aws awscliv2.zip

# Google Cloud CLI + GKE auth plugin
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    | tee /etc/apt/sources.list.d/google-cloud-sdk.list \
    && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && apt-get update && apt-get install -y --no-install-recommends \
    google-cloud-cli=${GCLOUD_VERSION}-0 \
    google-cloud-cli-gke-gcloud-auth-plugin=${GCLOUD_VERSION}-0 \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Kubernetes Tools
# =============================================================================

# kubectl
RUN curl -fsSLo /usr/local/bin/kubectl \
    "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod +x /usr/local/bin/kubectl

# Helm
RUN curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
    | tar -xzf - -C /tmp \
    && mv /tmp/linux-amd64/helm /usr/local/bin/helm \
    && rm -rf /tmp/linux-amd64

# kustomize
RUN curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" \
    | tar -xzf - -C /usr/local/bin \
    && chmod +x /usr/local/bin/kustomize

# ArgoCD CLI
RUN curl -fsSLo /usr/local/bin/argocd \
    "https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-amd64" \
    && chmod +x /usr/local/bin/argocd

# =============================================================================
# Utility Tools
# =============================================================================

# yq (YAML processor)
RUN wget -q "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" \
    -O /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list >/dev/null \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Verify all tools
RUN echo "=== Tool Versions ===" \
    && terraform version \
    && tofu version \
    && terragrunt --version \
    && tflint --version \
    && aws --version \
    && gcloud version --format="value(version)" \
    && kubectl version --client \
    && helm version \
    && kustomize version \
    && argocd version --client \
    && yq --version \
    && gh --version

# -----------------------------------------------------------------------------
# Stage 2: Delegate - Extend official Harness delegate
# -----------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS delegate

USER root

# Copy tools from builder
COPY --from=tooling /usr/local/bin/terraform /usr/local/bin/
COPY --from=tooling /usr/local/bin/tofu /usr/local/bin/
COPY --from=tooling /usr/local/bin/terragrunt /usr/local/bin/
COPY --from=tooling /usr/local/bin/tflint /usr/local/bin/
COPY --from=tooling /usr/local/bin/aws /usr/local/bin/
COPY --from=tooling /opt/aws-cli /opt/aws-cli
COPY --from=tooling /usr/local/bin/kubectl /usr/local/bin/
COPY --from=tooling /usr/local/bin/helm /usr/local/bin/
COPY --from=tooling /usr/local/bin/kustomize /usr/local/bin/
COPY --from=tooling /usr/local/bin/argocd /usr/local/bin/
COPY --from=tooling /usr/local/bin/yq /usr/local/bin/
COPY --from=tooling /usr/bin/gh /usr/local/bin/

# Copy gcloud SDK
COPY --from=tooling /usr/lib/google-cloud-sdk /usr/lib/google-cloud-sdk
COPY --from=tooling /usr/share/keyrings/cloud.google.gpg /usr/share/keyrings/cloud.google.gpg

# Add gcloud to PATH
ENV PATH="/usr/lib/google-cloud-sdk/bin:${PATH}"
ENV USE_GKE_GCLOUD_AUTH_PLUGIN=True

# Install Python3 for gcloud (minimal install)
RUN microdnf install -y python3 \
    && microdnf clean all

# Make git safe for all directories (avoids warnings in pipelines)
RUN git config --system --add safe.directory '*'

# Verify tools work
RUN terraform version && aws --version && gcloud version --format="value(version)"

# Restore non-root user (delegate runs as 1001)
USER 1001

LABEL maintainer="Harness SE" \
      description="Harness Delegate with Terraform, AWS CLI, Google Cloud CLI, and K8s tools"

# -----------------------------------------------------------------------------
# Stage 3: CI Runner - Standalone image for CI pipelines
# -----------------------------------------------------------------------------
FROM tooling AS ci

# Run as root for CI (needs write access to /harness workspace)
USER 0

# Make git safe for all directories
RUN git config --system --add safe.directory '*'

WORKDIR /harness
ENTRYPOINT ["/bin/bash"]

LABEL maintainer="Harness SE" \
      description="CI Runner with Terraform, AWS CLI, Google Cloud CLI, and K8s tools"
