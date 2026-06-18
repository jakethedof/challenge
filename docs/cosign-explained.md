# Cosign — What it is and why we use it

## The problem it solves

After an image is built and pushed to ACR, nothing technically stops someone from:
- pushing a different (malicious or untested) image with the same tag,
- promoting a random image to prod by running `helm upgrade` manually,
- deploying an image that was never scanned.

**Cosign solves this by cryptographically binding the image to the pipeline that built it.**

---

## How it works (keyless mode)

```
┌─────────────────────────────────────────────────────┐
│  GitHub Actions runner (trusted CI environment)     │
│                                                     │
│  1. Builds image, pushes to ACR                     │
│     → gets back an immutable digest sha256:abc123   │
│                                                     │
│  2. cosign sign sha256:abc123                       │
│     a. Runner requests a short-lived OIDC token     │
│        from GitHub ("I am workflow X of repo Y")   │
│     b. Cosign sends that token to Sigstore Fulcio   │
│        (a public certificate authority)             │
│     c. Fulcio issues a short-lived certificate      │
│        that encodes the workflow identity           │
│     d. Cosign signs the digest with that cert       │
│     e. Signature + cert stored in ACR as an OCI     │
│        artifact (next to the image, no extra cost)  │
└─────────────────────────────────────────────────────┘

              ▼  later, at deploy time  ▼

┌─────────────────────────────────────────────────────┐
│  cosign verify sha256:abc123                        │
│    --certificate-identity-regexp  "...pipeline.yml" │
│    --certificate-oidc-issuer  "...actions..."       │
│                                                     │
│  Cosign checks:                                     │
│    ✅ Signature is cryptographically valid          │
│    ✅ Cert was issued by Sigstore Fulcio             │
│    ✅ Cert identity matches THIS workflow file       │
│    ✅ Cert OIDC issuer is GitHub Actions             │
│                                                     │
│  If any check fails → pipeline aborts, no deploy   │
└─────────────────────────────────────────────────────┘
```

---

## What "keyless" means

Traditional signing requires you to generate a private key, store it as a secret,
rotate it, protect it, etc.

Keyless signing uses an ephemeral key pair created at signing time.  The key is
thrown away immediately.  The *identity* is instead encoded in the Fulcio
certificate, which is publicly logged in Sigstore's Rekor transparency log.
Anyone can verify without knowing any secret.

**No private key is stored anywhere in GitHub secrets.**

---

## What gets verified at each step

| Step | What is verified |
|------|-----------------|
| `develop` push | Image was signed by the pipeline on the `develop` branch |
| `staging` push | Image was signed by the pipeline on the `staging` branch |
| `prod` push    | Image was signed by the pipeline on the `prod` branch |

The `--certificate-identity-regexp` is anchored to the workflow file path, so
signing from an ad-hoc workflow or a fork will not pass verification.

---

## No Cosign infrastructure to run

Cosign uses Sigstore's public-good infrastructure (Fulcio + Rekor) by default.
No server to deploy, no key material to manage.
