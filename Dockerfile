# =============================================================================
# Harness Custom Tools - Delegate & CI Runner
# 
# Build targets:
#   - delegate: Extends official Harness delegate with cloud CLIs
#   - ci: Standalone CI runner image with full toolchain
# =============================================================================

ARG BASE_IMAGE=us-docker.pkg.dev/gar-prod-setup/harness-public/harness/delegate:26.08.89804

# -----------------------------------------------------------------------------
# Stage 1: Tooling - Build all tools in Ubuntu for compatibility
# -----------------------------------------------------------------------------
FROM ubuntu:22.04 AS tooling

ENV DEBIAN_FRONTEND=noninteractive \
    PIPX_BIN_DIR=/usr/local/bin \
    PIPX_HOME=/opt/pipx \
    PATH=/opt/pipx/bin:$PATH

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
RUN TERRAFORM_VERSION=$(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r -M '.current_version') \
    && wget -q https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    && unzip -q terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    && mv terraform /usr/local/bin/ \
    && rm -f terraform_*.zip

# OpenTofu
RUN TAG=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/opentofu/opentofu/releases/latest | awk -F'/' '{print $NF}') \
    && TOFU_VERSION=${TAG#v} \
    && wget -q https://github.com/opentofu/opentofu/releases/download/${TAG}/tofu_${TOFU_VERSION}_linux_amd64.zip \
    && unzip -q tofu_${TOFU_VERSION}_linux_amd64.zip \
    && mv tofu /usr/local/bin/ \
    && rm -f tofu_*.zip

# Terragrunt
RUN TAG=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/gruntwork-io/terragrunt/releases/latest | awk -F'/' '{print $NF}') \
    && wget -q https://github.com/gruntwork-io/terragrunt/releases/download/${TAG}/terragrunt_linux_amd64 -O /usr/local/bin/terragrunt \
    && chmod +x /usr/local/bin/terragrunt

# TFLint
RUN TAG=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/terraform-linters/tflint/releases/latest | awk -F'/' '{print $NF}') \
    && curl -fsSL -o /tmp/tflint.zip "https://github.com/terraform-linters/tflint/releases/download/${TAG}/tflint_linux_amd64.zip" \
    && unzip -q /tmp/tflint.zip -d /usr/local/bin \
    && rm -f /tmp/tflint.zip

# =============================================================================
# Cloud Provider CLIs
# =============================================================================

# AWS CLI v2 (Default URL always pulls the latest version)
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip \
    && unzip -q awscliv2.zip \
    && ./aws/install --install-dir /opt/aws-cli --bin-dir /usr/local/bin \
    && rm -rf aws awscliv2.zip

# Google Cloud CLI + GKE auth plugin
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    | tee /etc/apt/sources.list.d/google-cloud-sdk.list \
    && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && apt-get update && apt-get install -y --no-install-recommends \
    google-cloud-cli \
    google-cloud-cli-gke-gcloud-auth-plugin \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Kubernetes Tools
# =============================================================================

# kubectl
RUN KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt) \
    && curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod +x /usr/local/bin/kubectl

# Helm
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kustomize
RUN curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash \
    && mv kustomize /usr/local/bin/

# ArgoCD CLI
RUN TAG=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/argoproj/argo-cd/releases/latest | awk -F'/' '{print $NF}') \
    && curl -fsSLo /usr/local/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/${TAG}/argocd-linux-amd64" \
    && chmod +x /usr/local/bin/argocd

# =============================================================================
# Utility Tools
# =============================================================================

# yq (YAML processor)
RUN TAG=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/mikefarah/yq/releases/latest | awk -F'/' '{print $NF}') \
    && wget -q "https://github.com/mikefarah/yq/releases/download/${TAG}/yq_linux_amd64" -O /usr/local/bin/yq \
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
COPY --from=tooling /opt/aws-cli /opt/aws-cli
COPY --from=tooling /usr/local/bin/kubectl /usr/local/bin/
COPY --from=tooling /usr/local/bin/helm /usr/local/bin/
COPY --from=tooling /usr/local/bin/kustomize /usr/local/bin/
COPY --from=tooling /usr/local/bin/argocd /usr/local/bin/
COPY --from=tooling /usr/local/bin/yq /usr/local/bin/
COPY --from=tooling /usr/bin/gh /usr/local/bin/

# Copy AWS CLI - need to copy the entire installation and recreate symlink
COPY --from=tooling /opt/aws-cli /opt/aws-cli
RUN ln -sf /opt/aws-cli/v2/current/bin/aws /usr/local/bin/aws \
    && ln -sf /opt/aws-cli/v2/current/bin/aws_completer /usr/local/bin/aws_completer

# Copy gcloud SDK
COPY --from=tooling /usr/lib/google-cloud-sdk /usr/lib/google-cloud-sdk
COPY --from=tooling /usr/share/keyrings/cloud.google.gpg /usr/share/keyrings/cloud.google.gpg

# Add gcloud to PATH
ENV PATH="/usr/lib/google-cloud-sdk/bin:${PATH}"
ENV USE_GKE_GCLOUD_AUTH_PLUGIN=True

# Install Python3 for gcloud (minimal install) and configure git for pipelines
RUN microdnf install -y python3 git \
    && microdnf clean all \
    && git config --system --add safe.directory '*'

# Verify tools work
RUN terraform version && aws --version && gcloud version --format="value(version)"

# Ensure proper permissions on delegate directory
RUN chmod -R 775 /opt/harness-delegate \
    && chgrp -R 0 /opt/harness-delegate \
    && chown -R 1001 /opt/harness-delegate

# Restore non-root user (delegate runs as harness user)
USER harness

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
