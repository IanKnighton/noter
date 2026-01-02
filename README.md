# noter
An application that helps you take notes. It's silly, but it scratched an itch and replaced some shell scripts I was using.

## Installation

### Homebrew (Recommended)

The easiest way to install noter is via Homebrew:

```bash
brew tap IanKnighton/homebrew-tap
brew install noter
```

To upgrade to the latest version:
```bash
brew upgrade noter
```

### Manual Installation

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

You can also create a note with initial content:

```bash
noter new "This is my first note entry"
```

This will create a new note with a timestamped entry in the format:

```markdown
### HH:mm

This is my first note entry
```

### Adding to an existing note

```bash
noter add "Additional content for my note"
```

This will append content to the most recent note in the configured notes directory. If no notes exist, a new one will be created. The entry is added with a timestamp:

```markdown
### HH:mm

Additional content for my note
```

You can also append the contents of a markdown file:

```bash
noter add -f path/to/file.md
```

This will read the markdown file and append it to the most recent note with a timestamp header.

### Combining notes

```bash
noter combine
```

This will combine all notes that have multiple versions for the same day into a single file. For example, if you have `20260102.0.md`, `20260102.1.md`, and `20260102.2.md`, they will be combined into a single `20260102.0.md` file with the format:

```markdown
# MM-DD-YYYY

---

{FILE .0 ENTRIES}

---

{FILE .1 ENTRIES}

---

{FILE .2 ENTRIES}
```

By default, the original separate files are deleted after combining.

#### Combine only today's notes

```bash
noter combine today
```

This will only combine notes created today, leaving notes from other days unchanged.

#### Keep original files

```bash
noter combine --keep
```

This will create a new combined file while preserving the original separate files. The combined file will use the next available version number.

You can also combine these options:

```bash
noter combine today --keep
```

This will combine only today's notes and keep the original files.

### Specifying the notes directory

There are three ways to specify where notes should be stored, in order of priority:

1. **Command-line argument** (highest priority):
   ```bash
   noter new --path /path/to/notes
   noter new -p /path/to/notes
   noter add -p /path/to/notes "Content"
   noter combine -p /path/to/notes
   ```

2. **Environment variable**:
   ```bash
   export NOTER_PATH=/path/to/notes
   noter new
   noter add "Content"
   noter combine
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
noter add --help
noter combine --help
``` 
