# docbuild

`doc-gen4` integration for the Phase 3 API-docs gate.

The nested Lake project follows the upstream `doc-gen4` setup: it depends on
the parent package by path and pins `leanprover/doc-gen4` in
`lake-manifest.json`.

Build from this directory:

```text
DOCGEN_SRC=file lake build LeanAssumptions:docs
```

`DOCGEN_SRC=file` is intentional. The default `doc-gen4` source-link mode
infers GitHub remotes, but this workspace may not be a git checkout with a
remote. Local file source links make the docs gate reproducible in this
environment.

The generated docs root is:

```text
docbuild/.lake/build/doc/index.html
```
