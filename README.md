# OpenCode Skills

Reusable OpenCode skills that can be installed globally for your user or locally for a specific project.

This repository is meant to be a central place for skills you want OpenCode to load on demand without recreating them in every repository.

## Purpose

- keep reusable OpenCode skills in one versioned repository
- make those skills available globally on Arch Linux using OpenCode's default config location
- optionally install skills only for a single project
- allow either copied installs or symlinked installs for local development

## How OpenCode finds skills

This repository installs skills into one of these locations:

- global: `~/.config/opencode/skills`
- project-local: `<project>/.opencode/skills`

By default, the installer targets the global location, which matches the standard OpenCode config path used on this machine and works well on Arch Linux.

## Repository layout

Category folders are only for organization inside this repository.

Example:

```text
mobile/
  flutter-github-deploy/
    SKILL.md
```

The installed skill name is the directory name that contains `SKILL.md`, so the example above installs as `flutter-github-deploy`.

## Installer

Use `install.sh` to install all skills or only selected ones.

Default behavior:

- installs all discovered skills
- installs them globally into `~/.config/opencode/skills`
- uses `copy` mode unless you explicitly ask for `symlink`

### Usage

```bash
./install.sh [--skills skill1,skill2] [--project /path/to/project] [--mode copy|symlink]
./install.sh --list
./install.sh --help
```

### Options

- `--skills`: comma-separated skill names to install; if omitted, all skills are installed
- `--project`: install into `<project>/.opencode/skills` instead of the global location
- `--mode`: install mode, either `copy` or `symlink`; default is `copy`
- `--list`: print all discovered skill names and exit
- `--help`: show command help

### Examples

Install every skill globally using copied directories:

```bash
./install.sh
```

Install one skill globally:

```bash
./install.sh --skills flutter-github-deploy
```

Install one skill only for a specific project:

```bash
./install.sh --skills flutter-github-deploy --project /path/to/project
```

Install all skills only for a specific project using symlinks:

```bash
./install.sh --project /path/to/project --mode symlink
```

Install selected skills globally using symlinks:

```bash
./install.sh --skills flutter-github-deploy --mode symlink
```

List available skills:

```bash
./install.sh --list
```

## Copy vs symlink

- `copy`: best for stable installs that should keep working even if this repository is moved
- `symlink`: best when developing or iterating on skills in this repository and you want changes to become visible immediately

## Current skills

- `flutter-github-deploy`: replicates the tag-driven GitHub Actions Android APK release flow used by the source Flutter project
