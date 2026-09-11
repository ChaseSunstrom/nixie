# nixie-setup

The installer backend: Python standard library only. It serves the wizard
bundle over TLS on port 9443, pairs browsers with a single-use code (the
machine's own kiosk pairs with a local token), keeps secrets in memory until
a phase needs them, and runs `nixie-phase N` with streamed output. The same
program runs on the ISO (`--mode iso`, phases 1-3) and in the setup
generation (`--mode continuation`, phases 4-8, Finish).
