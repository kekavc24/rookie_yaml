# Intro

We are open to contributions from any human irrespective of your skill level, age, gender, race, nationality or religious beliefs. Just contribute.

>[!CAUTION]
> Spam/malicious PRs will be closed without review.

## What qualifies as contribution

1. Use the project and create issues which help make improvements.
2. Fix an open issue or one you discovered and create a PR. Even if your PR is not merged, it may be the stepping stone to a greater contribution!

## How to contribute

1. Identify an open issue. If the issues don't scratch your itch, run the official `YAML` Test Suite using the [guide](./test/yaml_test_suite/README.md) and create an issue. Help us bring this parser closer to the spec!

2. Fork this repo. Create a branch. Fix issue, commit using the [commit behaviour guide](#commit-behaviour) and create a PR.

> [!TIP]
> If you do not know where to start on fixing a bug or implementing a feature you found, just ping me @kekavc24

## Commit Behaviour

> [!TIP]
> Use [conventional commits](https://gist.github.com/qoomon/5dfcdf8eec66a051ecd85625518cfd13)

The repo uses an old-fashioned `linear-history` policy. No merge commits or squashed PR commits. The PR will be used to fast-forward the `main` branch. Make sure a commit is standalone (not atomic) i.e in a "squash" state. Each commit should be able to provide enough information on the change without being too verbose or too simple.

You can use atomic commits locally. However, before making a PR, rebase and squash any commits that are similar.

### Example

Let's say you want to fix `X` issue. Upon investigation, you realise `Y` and `Z` need to be handled first.

1. Both `Y` and `Z` only affect `X` and nothing else. You could:
    - Make atomic commits for both `Y` and `Z`. Fix `X` and commit. Rebase and squash `Y` and `Z` into `X`.
    - Work on it and commit as `X`.
    - If `Y` or `Z` is like `X`, make them standalone.

2. If `X` depends on `Y` but `Y` can be independent and affects other components as well. Create a separate PR for both `Y` and `X` and explicitly indicate this. Both will be reviewed and merged if successful.
