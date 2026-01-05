# Building Phobos Bot Statically

This project can be built as a fully static binary to avoid dependencies on host system components.

## Building Statically

Use the provided build script to create a static binary:

```bash
./build_static.sh
```

This will create a `bot` binary that is completely self-contained and has no external dependencies.

## How It Works

The build process:
1. Uses CGO to compile the SQLite C library directly into the binary
2. Applies static linking flags to embed all dependencies
3. Creates a single binary with no external library dependencies

## Verification

The script automatically checks if the created binary is statically linked. You can also verify manually:

```bash
ldd bot
```

A static binary will report "not a dynamic executable" or "statically linked".