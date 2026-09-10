# Mission Control HTTPS startup

The image entrypoint launches `/home/node/.local/mission-control/ops/supervise.sh` as node. The persistent supervisor reconciles dependencies, builds with webpack (two build workers), and restarts the production HTTPS child. Source, TLS certificates, and owner authentication remain on the existing persistent volume.

Do not host the long-running supervisor in a timed tool execution session. For manual recovery use Docker detached exec as node. Normal container startup launches it from the entrypoint.

Dockerfile.custom already copies entrypoint.sh, so future full image builds include this fix. Dockerfile.mc-startup permits a minimal patch of the installed image without upgrading OpenClaw. The patched image is tagged openclaw:custom, matching effective Compose configuration; the previous image is retained as openclaw:before-mc-https.

Validation: shell syntax, fresh isolated image hook inspection, live /healthz 200. Live gateway container recreation is not performed during the active conversation. Existing startup hook is already installed in the running container. Owner confirmed dashboard login before this change; credentials are unchanged.

Build note: BuildKit interpreted a bare sha256 image ID as a registry image name. Use a local tag for the base image instead.
