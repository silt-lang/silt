# Contributing to `silt`

We appreciate contributions from people from all backgrounds and experience
levels. Silt is an educational project for its owners, and we don't have all
the answers about how things will work in the long term. Because of that, we
want to encourage external contributors to use their contributions to learn
the ins and outs of compiler development as well. You need not be a "compiler
wizard" to contribute -- we certainly aren't!

As such, we commit to treat contributors with respect, and always give
constructive feedback. All contributors must hold themselves to the terms of
the [Contributor's Covenant](CODE_OF_CONDUCT.md) to ensure a respectful
environment.

# Steps for Contributions

- Look through the open issues for something you'd like to address. If what you
  want to fix is not currently tracked in the issues, make a new issue
  describing the problem and assign yourself.
- Fork the repository to your GitHub account.
- Make a new branch off of `master`
  - `git checkout -b branch-name-here`
  - Bonus points if your branch name is a pun based on your PR contents 👌
    - Keep puns respectful -- see the covenant.
- Implement your fix. If the fix is non-trivial, it might be a good idea to
  start a work-in-progress pull request, especially if you want feedback on the
  direction of your change. To do so, prepend your PR title with `[WIP]`.
- Implement a test that ensures your fix is correct. The best way to do this
  is to add a test that fails prior to implementing your change, and passes
  once your change is implemented.
- Make a PR (or remove `[WIP]`).
  - Ensure you link to the issue you resolved by the PR in the description.
  - Use the PR description to explain what your change does and why it fixes
    the issue.
- Add one of the code owners (@harlanhaskins or @codafi) as a reviewer.
  - We'll have a review process where we look over the code, make sure it
    seems correct, and discuss the contents of the PR.
  - If conflicts arise, we recommend rebasing your changes on the upstream
    master.
- After a code review and discussion, CI will test your changes. Once the PR
  is accepted, and CI passes, it'll be merged!
