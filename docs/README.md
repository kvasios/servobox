# ServoBox Documentation

This directory contains the complete documentation for ServoBox, built with [MkDocs](https://www.mkdocs.org/) and the [Material theme](https://squidfunk.github.io/mkdocs-material/).

## Building Locally

### Install Dependencies

```bash
cd docs
pip install -r requirements.txt
```

### Serve Documentation

```bash
mkdocs serve
```

Open [http://localhost:8000](http://localhost:8000) in your browser.

### Build Static Site

```bash
mkdocs build
```

Output will be in `site/` directory.

## Documentation Structure

```
docs/
├── mkdocs.yml              # MkDocs configuration
├── requirements.txt        # Python dependencies
├── README.md              # This file
└── content/               # Documentation content (Markdown)
    ├── index.md           # Homepage
    ├── getting-started/   # Getting started guides
    │   ├── overview.md
    │   ├── installation.md
    │   ├── quickstart.md
    │   └── first-vm.md
    ├── user-guide/        # User guides
    │   ├── commands.md
    │   ├── package-management.md
    │   └── networking.md
    ├── rt-config/         # Real-time configuration
    │   ├── fundamentals.md
    │   ├── host-setup.md
    │   ├── cpu-isolation.md
    │   ├── performance-testing.md
    │   └── tuning.md
    ├── packages/          # Package management
    │   ├── available-packages.md
    │   ├── creating-recipes.md
    │   └── config-files.md
    ├── advanced/          # Advanced topics
    │   ├── custom-images.md
    │   ├── bridge-networking.md
    │   ├── multi-vm.md
    │   └── troubleshooting.md
    ├── development/       # Development guides
    │   ├── building.md
    │   ├── architecture.md
    │   └── contributing.md
    └── reference/         # Reference materials
        ├── faq.md
        ├── glossary.md
        └── changelog.md
```

## Contributing to Documentation

### Writing Guidelines

- Use clear, concise language
- Include code examples
- Add diagrams where helpful
- Link to related pages
- Test all commands before documenting

### Markdown Extensions

The documentation uses these extensions:

- **Admonitions**: `!!! note`, `!!! warning`, `!!! tip`
- **Code blocks**: with syntax highlighting
- **Tables**: for structured data
- **Lists**: numbered and bulleted
- **Links**: internal and external

### Example Admonition

```markdown
!!! warning "Important"
    This is a warning message.
```

### Example Code Block

````markdown
```bash
servobox init --vcpus 4
```
````

## Publishing

Documentation can be published to:

- **GitHub Pages**: `mkdocs gh-deploy`
- **Read the Docs**: Connect repository
- **Custom hosting**: Deploy `site/` directory

## License

Documentation is licensed under GPLv3, same as ServoBox.

