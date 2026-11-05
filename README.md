# Light Squares SSCI Report

This GitHub Action reports what your product contains to Light Squares Supply Chain
Intelligence (SSCI). Each run uploads an SBOM or a `Cargo.lock`, and SSCI shows on the
product's timeline what changed since the previous run on the same branch, or since the
previous release.

## Setup

1. Open your product in Light Squares and create an upload token on the Connect CI tab.
2. Store the token in your repository as the secret `LIGHTSQUARES_SSCI_TOKEN`, under
   Settings, Secrets and variables, Actions.
3. Add a workflow such as one of the two below.

The first example generates a CycloneDX SBOM with syft and reports it on every push to
`main` and on every version tag:

```yaml
name: Supply Chain Intelligence
on:
  push:
    branches: [main]
    tags: ["v*"]
jobs:
  report:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: anchore/sbom-action@v0
        with:
          format: cyclonedx-json
          output-file: sbom.cdx.json
          upload-artifact: false
      - uses: lightsquares/ssci-report@v1
        with:
          token: ${{ secrets.LIGHTSQUARES_SSCI_TOKEN }}
          file: sbom.cdx.json
```

A Rust project can report its `Cargo.lock` as it is, without generating an SBOM:

```yaml
      - uses: actions/checkout@v4
      - uses: lightsquares/ssci-report@v1
        with:
          token: ${{ secrets.LIGHTSQUARES_SSCI_TOKEN }}
          file: Cargo.lock
```

`@v1` follows the latest 1.x release, and each release also has a tag of its own, such
as `v1.0.0`, which never moves. We recommend pinning every action, this one included, to
a full commit SHA.

The Action runs on Linux runners, such as `ubuntu-latest`.

## Inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `token` | required | The product's upload token. Always pass it from a secret. |
| `file` | required | A CycloneDX or SPDX SBOM in JSON, or a `Cargo.lock`, of at most 10 MB. |
| `ref` | the run's ref | The branch or tag the upload belongs to. Runs on the same ref are compared with each other. |
| `commit` | the run's commit | The commit the file was produced from. |
| `version` | the tag's name on a tag | A label for the upload, such as `1.4.0`. |
| `release` | `true` on a tag | Whether the upload is a release. A release is compared with the previous release. |
| `url` | `https://app.lightsquares.dev/api/ssci/upload` | Where to upload to. |

## Outputs

| Output | Meaning |
| --- | --- |
| `inventory-id` | The id of the recorded upload. |
| `packages` | How many packages were read from the file. |

The outputs and the job summary need `jq`, which GitHub-hosted runners include. Without
it, the upload still works.

## Other CI systems

The Action is one HTTP request, so any CI can do the same with `curl`:

```bash
curl --fail-with-body -sS -X POST \
  -H "Authorization: Bearer $LIGHTSQUARES_SSCI_TOKEN" \
  --data-binary @sbom.cdx.json \
  "https://app.lightsquares.dev/api/ssci/upload?ref=$REF&commit=$COMMIT&version=$VERSION&release=$IS_RELEASE"
```
