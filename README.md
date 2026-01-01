# noter
An application that helps you take notes. It's silly, but it scratched an itch and replaced some shell scripts I was using.

## Installation

Build the application using Swift Package Manager:

```bash
swift build -c release
```

The executable will be at `.build/release/noter`.

You can copy it to a location in your PATH:

```bash
cp .build/release/noter /usr/local/bin/
```

## Usage

### Creating a new note

```bash
noter new
```

This will create a new note in the configured notes directory with the filename format `yyyyMMdd.v.md`, where:
- `yyyyMMdd` is the current date (e.g., 20260101 for January 1, 2026)
- `v` is an incrementing version number starting at 0

If multiple notes are created on the same day, the version number increments automatically (e.g., `20260101.0.md`, `20260101.1.md`, etc.).

### Specifying the notes directory

There are three ways to specify where notes should be stored, in order of priority:

1. **Command-line argument** (highest priority):
   ```bash
   noter new --path /path/to/notes
   noter new -p /path/to/notes
   ```

2. **Environment variable**:
   ```bash
   export NOTER_PATH=/path/to/notes
   noter new
   ```

3. **Configuration file** (`~/.noterrc`):
   Create a file at `~/.noterrc` with the following content:
   ```
   path=/path/to/notes
   ```

4. **Default**: If no path is specified, notes will be stored in `~/notes`

## Help

To see all available commands and options:

```bash
noter --help
noter new --help
``` 
