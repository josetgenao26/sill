# Contributing

## The process

Open an issue before opening a pull request, for anything beyond a typo. A pull request
that arrives without one risks being closed after you have already done the work, because
the approach was never agreed — and that wastes your afternoon, not mine.

Direct pushes are not possible: fork the repository, work on a branch, and open a pull
request from it.

## Before you start

Read the **Known limitations** section of the [README](README.md). Two of the most
requested features — listing windows from other Spaces, and switching Spaces — cannot be
done with public macOS APIs. What was tried and why it fails is documented there. Sill
uses no private APIs, and that is a decision rather than an omission.

## What a good change looks like

**Verified by running it.** "It compiles" is not evidence. Sill writes everything it does
to `~/Library/Logs/Sill.log`, and that log is how nearly every problem in this codebase
has been diagnosed. Say what you observed.

**No new warnings.** `./scripts/bundle.sh` should stay silent.

**Comments explaining why.** This codebase leans heavily on comments that record *why* a
line exists — which macOS behaviour forced it, which obvious approach was tried and
failed. That is deliberate: most of the difficulty here is in undocumented platform
behaviour, and a comment saying what the code does is worth nothing next to one saying why
it has to.

**Every control does something.** If a change adds a setting, the setting must change real
behaviour. A switch that moves nothing is a promise the app cannot keep.

## Build setup

See the [README](README.md#building). One thing that will save you an afternoon: create
the signing certificate before your first build, or macOS revokes the Accessibility
permission every single time you recompile.
