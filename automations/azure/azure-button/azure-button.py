#!/usr/bin/env python3

import argparse
import urllib.parse


def main() -> None:
    parser = init_argparse()
    args = parser.parse_args()

    if args.arm is None or args.ui is None:
        parser.print_help()
        exit(1)

    print(
        f"[![Deploy to Azure](https://aka.ms/deploytoazurebutton)]({combine(args.arm, args.ui)})"
    )


def init_argparse() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        usage="%(prog)s --arm [URL] --ui [URL]",
        description="Print the Markdown for Azure buttons.",
    )

    parser.add_argument("-a", "--arm", required=True, help="URL to ARM template")
    parser.add_argument(
        "-u", "--ui", required=True, help="URL to createUiDefinition.json file"
    )

    return parser


def escape(s: str) -> str:
    return urllib.parse.quote(s, safe="")


def combine(arm: str, ui: str) -> str:
    arm_escaped = escape(arm)
    ui_escaped = escape(ui)
    return f"https://portal.azure.com/#create/Microsoft.Template/uri/{arm_escaped}/createUIDefinitionUri/{ui_escaped}"


if __name__ == "__main__":
    main()
