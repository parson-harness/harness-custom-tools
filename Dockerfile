# =============================================================================
# Harness Delegate with Cloud CLI Tools
# Extends official delegate with gcloud, aws, terraform for POV use cases
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Build tools in a separate image to keep final image smaller
# -----------------------------------------------------------------------------
FROM ubuntu:22.04 AS tooling

ENV DEBIAN_FRONTEND=noninteractive

# Versions - updated for stability (as of March 2025)
ARG TERRAFORM_VERSION=1.10.5
ARG AWS_CLI_VERSION=2.27.22
ARG GCLOUD_VERSION=515.0.0
ARG YQ_VERSION=4.45.1
ARG KUSTOMIZE_VERSION=5.6.0

# Core dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    unzip \
    gnupg \
    ca-certificates \
    python3 \
    python3-pip \
    jq \
    git \
    && rm -rf /var/lib/apt/lists/*

# Terraform
RUN wget -q https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    && unzip -q terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    && mv terraform /usr/local/bin/ \
    && rm -f terraform_*.zip \
    && terraform version

# AWS CLI v2
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWS_CLI_VERSION}.zip" -o awscliv2.zip \
    && unzip -q awscliv2.zip \
    && ./aws/install --install-dir /opt/aws-cli --bin-dir /usr/local/bin \
    && rm -rf aws awscliv2.zip \
    && aws --version

# Google Cloud CLI
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    | tee /etc/apt/sources.list.d/google-cloud-sdk.list \
    && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && apt-get update && apt-get install -y --no-install-recommends \
    google-cloud-cli=${GCLOUD_VERSION}-0 \
    google-cloud-cli-gke-gcloud-auth-plugin=${GCLOUD_VERSION}-0 \
    && rm -rf /var/lib/apt/lists/* \
    && gcloud version

# yq (YAML processor)
RUN wget -q https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64 \
    -O /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

# kustomize
RUN curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" \
    | tar -xzf - -C /usr/local/bin \
    && chmod +x /usr/local/bin/kustomize

# -----------------------------------------------------------------------------
# Stage 2: Final delegate image
# Build with: docker build --build-arg DELEGATE_TAG=25.02.85600 -t my-delegate .
# -----------------------------------------------------------------------------

ARG DELEGATE_TAG=25.02.85600
FROM harness/delegate:${DELEGATE_TAG}

USER root

# Copy tools from builder stage
COPY --from=tooling /usr/local/bin/terraform /usr/local/bin/terraform
COPY --from=tooling /usr/local/bin/aws /usr/local/bin/aws
COPY --from=tooling /opt/aws-cli /opt/aws-cli
COPY --from=tooling /usr/local/bin/yq /usr/local/bin/yq
COPY --from=tooling /usr/local/bin/kustomize /usr/local/bin/kustomize

# Copy gcloud (it's larger, needs full directory)
COPY --from=tooling /usr/lib/google-cloud-sdk /usr/lib/google-cloud-sdk
COPY --from=tooling /usr/share/keyrings/cloud.google.gpg /usr/share/keyrings/cloud.google.gpg

# Add gcloud to PATH and configure
ENV PATH="/usr/lib/google-cloud-sdk/bin:${PATH}"
ENV USE_GKE_GCLOUD_AUTH_PLUGIN=True

# Install Python3 for gcloud dependencies (minimal)
RUN microdnf install -y python3 \
    && microdnf clean all

# Verify installations
RUN terraform version \
    && aws --version \
    && gcloud version \
    && yq --version \
    && kustomize version

# Restore non-root user
USER 1001

# Labels
LABEL maintainer="Harness SE" \
      description="Harness Delegate with Terraform, AWS CLI, and Google Cloud CLI" \
      terraform.version="${TERRAFORM_VERSION}" \
      aws-cli.version="${AWS_CLI_VERSION}" \
      gcloud.version="${GCLOUD_VERSION}"
