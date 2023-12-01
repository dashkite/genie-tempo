# Build Rules

## Initial State (Facts)

- Repos (normalized to include package information, including dependencies)
- Scripts
- Tags (reverse lookup for Repos)
- Targets (initially an empty stack)
- Built (initially an empty set)
- Ready (initially an empty set)

The *current target* refers to the repo at the top of the target stack.

### Virtual States

- is-development-dependency: there exists a repo where this repo is a development dependency
- is-ready: all production dependencies are built

## Rules

### Select a target

**Condition** The targets stack is empty and there are repos that haven’t been built yet.

**Action** Find a repo that hasn’t been built and push it.

### Build a target

**Condition** The current target’s development dependencies are ready.

**Action** 

- Build the current target.
- Move it to the built set.

### Find next development dependency

**Condition** One of the current target’s development dependencies is not built.

**Actions** Find the first development dependency that hasn’t been built and push it onto the targets stack.

### Find next production dependency

**Condition**

- The current target is a development dependency.
- One of its production dependencies is not built.

**Actions** Find the first production dependency that hasn’t been built and push it onto the targets stack.