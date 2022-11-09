# Contributing

**If you are a cPacket Networks customer, please report issues thorugh your tech support service account (TODO: insert link to support)**

We are happy to review pull requests referenced in your support tickets.

Each script or automation should be contained in an enclosing directory with accompanying `README.md` and any related diagrams.

The file and directory layout is arbitrarily subject to change, so use [permalinks][permalinks] to refer to specific files.

## Text and Documentation

- Markdown files should comply with the [CommonMark Markdown specification][commonmark] using the [markdown-it] library, as is done in [VS Code][vscode].
- Prose sentences should exist one per line, so as to make diff'ing easier.
  For instance,

    ```text
    This is the first sentence. And this is the second one.
    ```
  
  ... should be written in the markdown file as:

    ```text
    This is the first sentence.
    And this is the second one.
    ```

## Bash scripts

- Any Bash scripts must pass [shellcheck][shellcheck].
- Formatting of Bash scripts should comply with the following use of [shfmt][shfmt]:

    ```bash
    shfmt -i 4 -w script.sh
    ```

## Terraform

Terraform scripts and modules should be formatted according to:

```bash
terraform fmt
```

[shellcheck]: https://github.com/koalaman/shellcheck
[permalinks]: https://docs.github.com/en/repositories/working-with-files/using-files/getting-permanent-links-to-files
[shfmt]: https://github.com/mvdan/sh#shfmt
[vscode]: https://code.visualstudio.com/
[markdown-it]: https://github.com/markdown-it/markdown-it
[commonmark]: https://commonmark.org/
