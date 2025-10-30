ARG BASE_IMAGE

# -----------------------------
# Common tooling (no entrypoint)
# -----------------------------
FROM ubuntu:22.04 AS tooling
ENV DEBIAN_FRONTEND=noninteractive \
    PIPX_BIN_DIR=/usr/local/bin \
    PIPX_HOME=/opt/pipx \
    PATH=/opt/pipx/bin:$PATH

# Core + build deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget git unzip jq gnupg lsb-release ca-certificates apt-transport-https \
    software-properties-common python3 python3-pip python3-venv build-essential \
    make sudo sed gawk bash coreutils openssh-client xz-utils \
 && rm -rf /var/lib/apt/lists/*

# --- Versions (override at build time as needed)
ARG TERRAFORM_VERSION=1.9.5
ARG TOFU_VERSION=1.7.2
ARG TFLINT_VERSION=0.51.1
ARG TERRAGRUNT_VERSION=0.56.4
ARG TERRASCAN_VERSION=1.18.7
ARG KUBECTL_VERSION=1.30.3
ARG HELM_VERSION=3.15.3
ARG YQ_VERSION=4.44.3
ARG SONAR_SCANNER_VERSION=5.0.1.3006
ARG NODE_MAJOR=20
ARG GO_VERSION=1.25.0
ARG GOLANGCI_LINT_VERSION=v2.5.0
ARG GOSEC_VERSION=2.22.8

# Terraform
RUN wget -q https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
 && unzip -q terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
 && mv terraform /usr/local/bin/ && rm -f terraform_*.zip

# OpenTofu
RUN wget -q https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_amd64.zip \
 && unzip -q tofu_${TOFU_VERSION}_linux_amd64.zip \
 && mv tofu /usr/local/bin/ && rm -f tofu_*.zip

# TFLint
RUN curl -fsSL -o /tmp/tflint.zip "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_amd64.zip" \
 && unzip -q /tmp/tflint.zip -d /usr/local/bin && rm -f /tmp/tflint.zip

# Terragrunt
RUN wget -q https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/terragrunt_linux_amd64 -O /usr/local/bin/terragrunt \
 && chmod +x /usr/local/bin/terragrunt

# tfsec
RUN wget -q https://github.com/aquasecurity/tfsec/releases/latest/download/tfsec-linux-amd64 -O /usr/local/bin/tfsec \
 && chmod +x /usr/local/bin/tfsec

# Checkov
RUN pip3 install --no-cache-dir pipx && pipx install checkov

# Terrascan
RUN wget -q https://github.com/tenable/terrascan/releases/download/v${TERRASCAN_VERSION}/terrascan_${TERRASCAN_VERSION}_Linux_x86_64.tar.gz \
 && tar -xzf terrascan_${TERRASCAN_VERSION}_Linux_x86_64.tar.gz terrascan \
 && mv terrascan /usr/local/bin/ && chmod +x /usr/local/bin/terrascan \
 && rm -f terrascan_${TERRASCAN_VERSION}_Linux_x86_64.tar.gz

# kubectl
RUN curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
 && chmod +x /usr/local/bin/kubectl

# Helm
RUN curl -fsSLo /tmp/helm.tgz https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz \
 && tar -xzf /tmp/helm.tgz -C /tmp \
 && mv /tmp/linux-amd64/helm /usr/local/bin/helm \
 && rm -rf /tmp/linux-amd64 /tmp/helm.tgz

# kustomize (latest)
RUN curl -fsSL https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh | bash \
 && mv kustomize /usr/local/bin/

# yq
RUN wget -q https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64 -O /usr/local/bin/yq \
 && chmod +x /usr/local/bin/yq

# AWS CLI v2
RUN curl -fsSLO "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
 && unzip -q awscli-exe-linux-x86_64.zip \
 && ./aws/install && rm -rf aws awscli-exe-linux-x86_64.zip

# Azure CLI
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Google Cloud CLI
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" \
  | tee /etc/apt/sources.list.d/google-cloud-sdk.list \
 && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
  | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - \
 && apt-get update && apt-get install -y google-cloud-sdk \
 && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  | tee /etc/apt/sources.list.d/github-cli.list >/dev/null \
 && apt-get update && apt-get install -y gh \
 && rm -rf /var/lib/apt/lists/*

# Node.js LTS + yarn/pnpm
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
 && apt-get update && apt-get install -y nodejs \
 && npm i -g yarn pnpm

# --- Go toolchain + linters/security tools for CI ---
ENV GOROOT=/usr/local/go \
    GOPATH=/opt/go \
    PATH=/usr/local/go/bin:/opt/go/bin:$PATH

# Install Go
RUN curl -fsSLo /tmp/go.tgz https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz \
 && tar -C /usr/local -xzf /tmp/go.tgz \
 && mkdir -p /opt/go/{bin,pkg,src} \
 && rm -f /tmp/go.tgz

# golangci-lint (binary install)
RUN curl -fsSLo /tmp/golangci-lint.tar.gz \
      https://github.com/golangci/golangci-lint/releases/download/${GOLANGCI_LINT_VERSION}/golangci-lint-${GOLANGCI_LINT_VERSION#v}-linux-amd64.tar.gz \
 && tar -xzf /tmp/golangci-lint.tar.gz -C /tmp \
 && mv /tmp/golangci-lint-*/golangci-lint /usr/local/bin/ \
 && rm -rf /tmp/golangci-lint*

RUN curl -fsSLo /tmp/gosec.tgz \
      https://github.com/securego/gosec/releases/download/v${GOSEC_VERSION}/gosec_${GOSEC_VERSION}_linux_amd64.tar.gz \
 && tar -xzf /tmp/gosec.tgz -C /usr/local/bin gosec \
 && chmod +x /usr/local/bin/gosec \
 && rm -f /tmp/gosec.tgz

# govulncheck (via go install; keep in PATH)
RUN go install golang.org/x/vuln/cmd/govulncheck@latest

# Sonar Scanner (optional)
RUN wget -q https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux.zip \
 && unzip -q sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux.zip \
 && mv sonar-scanner-${SONAR_SCANNER_VERSION}-linux /opt/sonar-scanner \
 && ln -s /opt/sonar-scanner/bin/sonar-scanner /usr/local/bin/sonar-scanner \
 && rm -f sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux.zip

# Wiz CLI (optional)
RUN curl -fsSL https://downloads.wiz.io/wizcli/latest/wizcli-linux-amd64 -o /usr/local/bin/wiz \
 && chmod +x /usr/local/bin/wiz

# Non-root user for CI
RUN useradd -m -u 10001 harness \
 && echo "harness ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/harness
USER harness
WORKDIR /home/harness

# -----------------------------------------
# Target 1: Custom Delegate (keeps entrypoint)
# -----------------------------------------
# Pass a FULL base image (e.g., GAR mirror + tag)
#   --build-arg BASE_IMAGE=us-docker.pkg.dev/.../delegate:25.08.86600.minimal-fips
ARG BASE_IMAGE
FROM ${BASE_IMAGE} AS delegate
# Switch to root to copy tooling in
USER root
COPY --from=tooling /usr/local/bin/ /usr/local/bin/
COPY --from=tooling /opt/ /opt/
COPY --from=tooling /etc/sudoers.d/harness /etc/sudoers.d/harness
COPY --from=tooling /home/harness /home/harness
COPY --from=tooling /usr/bin/git /usr/bin/git
COPY --from=tooling /usr/lib/git-core/ /usr/lib/git-core/
COPY --from=tooling /etc/ssl/certs/ /etc/ssl/certs/
# Restore non-root for consistency (delegate ENTRYPOINT remains unchanged)
USER 10001
WORKDIR /home/harness
# (INTENTIONALLY no ENTRYPOINT/CMD here to preserve delegate's)

# -----------------------------------------
# Target 2: CI build container (bash entrypoint)
# -----------------------------------------
FROM tooling AS ci

# Run as root so we can write to /harness regardless of who owns it
USER 0

# Make all repos “safe” for git (avoids unsafe repo warnings)
RUN git config --system --add safe.directory '*'

WORKDIR /harness
ENTRYPOINT ["/bin/bash"]
