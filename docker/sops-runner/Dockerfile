# Pre-deploy hook runner for Arcane GitOps syncs: upstream sops, but running
# as uid 65532 to match Arcane's app worker. Decrypted files written into a
# project workspace are then owned by the same uid that manages the
# workspace, so git syncs can promote/replace them without permission games
# (Arcane runs hook containers with all capabilities dropped).
FROM ghcr.io/getsops/sops:v3.13.2-alpine

LABEL org.opencontainers.image.source=https://github.com/sebdanielsson/infra
LABEL org.opencontainers.image.description="sops hook runner for Arcane GitOps, runs as uid 65532"

USER 65532:65532
