# Contributing to ServoBox

Thanks for your interest in contributing to ServoBox! 🦾

## What We're Looking For

**Primary Focus: Package Recipes**  
We're especially interested in contributions that expand our package recipes in `packages/recipes/`. These help users quickly set up robotics software stacks in their RT VMs.

## Contribution Guidelines

### Recipe Contributions

**Before you start:**
- Check existing recipes in `packages/recipes/` to avoid duplicates
- Look at `packages/recipes/example-custom/` for the template structure

**Recipe Requirements:**
- `recipe.conf` - Package metadata (name, description, dependencies)
- `install.sh` - Installation script that works in Ubuntu 22.04 RT environment
- Test your recipe with: `servobox pkg-install --recipe-dir /path/to/your/recipe your-package`

**Quality Standards:**
- Installation should be idempotent (safe to run multiple times)
- Scripts should handle errors gracefully
- Include necessary dependencies and environment setup
- Document any special requirements in comments

### Other Contributions

- Bug fixes and improvements to core ServoBox functionality
- Documentation improvements
- Performance optimizations

## How to Contribute

1. **Fork** the repository
2. **Create** a feature branch: `git checkout -b add-my-recipe`
3. **Make** your changes
4. **Test** thoroughly (especially for recipes)
5. **Submit** a pull request with a clear description

## Pull Request Guidelines

- Keep PRs focused and reasonably sized
- Include a brief description of what you're adding/fixing
- For recipes: mention what software stack it installs and any special requirements
- Ensure your changes don't break existing functionality

## Questions?

- Open an issue for questions or discussions
- Check existing issues before creating new ones
- Be respectful and constructive in all interactions

## Recognition

Contributors will be acknowledged in our changelog and documentation. Thanks for helping make ServoBox better! 🚀
