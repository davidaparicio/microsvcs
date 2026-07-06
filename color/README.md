# color/ — live feature-flag source

This directory intentionally contains only `demo-flags.goff.yaml`.

It is the **GO Feature Flag file that the git-sync sidecar serves to the red
service in development and staging**: the sidecar clones this repo, copies
`color/demo-flags.goff.yaml` into a shared volume mounted at `/app/config/`,
and red polls it (see `k8s/overlays/{development,staging}/red/kustomization.yaml`).

Living outside `projects/**` is deliberate: editing this file flips flags on
the running pods within the sync interval **without triggering any CI build or
image publish** (both workflows filter on `projects/**`).

The full color web service source lives in `projects/{red,blue,green,yellow}/`.
A historical copy of the service (a fork of jpetazzo/color) used to live here
and was removed — see git history if you need it.
