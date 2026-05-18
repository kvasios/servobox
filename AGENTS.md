# ServoBox Agent Guide

ServoBox is a shell-first project for creating and tuning Ubuntu PREEMPT_RT environments for robotics workloads. Keep changes practical, conservative, and aligned with the existing command-line UX.

## Start Here

- Read `README.md` for the product surface and common workflows.
- Use `scripts/servobox` as the command dispatcher and user-facing CLI reference.
- Look under `scripts/servobox-lib/` for implementation modules before adding new logic.
- Check `tests/` before changing behavior; add focused tests when behavior changes.

## Project Conventions

- Prefer plain Bash and existing helper functions over new dependencies.
- Keep CLI output professional, concise, and ASCII unless a technical unit requires otherwise.
- Treat local VM and remote target behavior as separate paths unless the existing command already shares logic.
- Preserve existing user data and VM state; avoid destructive operations unless the user explicitly asks.

## Validation

- Run `bash -n` on edited shell scripts after changes.
- Run `git diff --check` before handing off.
- For output-only changes, verify messages with search instead of running VM-affecting commands.
