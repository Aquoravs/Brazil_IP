# Explorations

This folder is a **sandbox** for experimental and exploratory work. All new ideas, prototypes, and research experiments go here first — never directly into production folders.

## How It Works

1. **Create a subfolder** for each exploration (e.g., `explorations/new-estimator/`)
2. **Work freely** — lower quality threshold (60/100) during exploration
3. **Decide:** graduate to production (80/100 required), keep exploring, or archive

## Rules

- See `.claude/rules/content-standards.md` §4 (Exploration Folder Protocol) for the full protocol
- See `.claude/rules/content-standards.md` §5 (Exploration Fast-Track) for the lightweight workflow

## Structure

```
explorations/
├── [active-project]/       # Work in progress
│   ├── README.md           # Goal, hypotheses, status
│   ├── R/                  # Experimental code
│   ├── scripts/            # Test scripts
│   └── output/             # Results
└── ARCHIVE/                # Completed or abandoned
    ├── completed_[name]/   # Graduated to production
    └── abandoned_[name]/   # Documented why stopped
```
