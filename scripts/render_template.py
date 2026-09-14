#!/usr/bin/env python3
import os
import sys
from string import Template


def main():
    if len(sys.argv) < 3:
        sys.exit(f"usage: {sys.argv[0]} TEMPLATE VARIABLE...")
    template_path, names = sys.argv[1], sys.argv[2:]
    values = {name: os.environ.get(name, "") for name in names}
    with open(template_path) as template:
        sys.stdout.write(Template(template.read()).safe_substitute(values))


if __name__ == "__main__":
    main()
