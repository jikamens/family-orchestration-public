#!/usr/bin/env python3

'''Order-independent YAML file comparison

Exits 0 if files have same contents (order-independent), 1 if the
first file has content that the second doesn't, 2 if the second file
has content that the first doesn't, and 3 if they have conflicting
data.

Treats a nonexistent file as equivalent to it being an empty dict.

'''

import sys
from yaml import load, Loader


def compare_lists(a1, a2):
    '''Order-independent comparison!'''
    a1 = set(a1)
    a2 = set(a2)
    only_in_a1 = a1 - a2
    only_in_a2 = a2 - a1
    if only_in_a1 and only_in_a2:
        return 3
    if only_in_a1:
        return 1
    if only_in_a2:
        return 2
    return 0


def compare_dicts(d1, d2):
    k1 = set(d1.keys())
    k2 = set(d2.keys())
    only_in_d1 = k1 - k2
    only_in_d2 = k2 - k1
    if only_in_d1 and only_in_d2:
        return 3
    both = k1 & k2
    current = 0
    for k in both:
        this = compare(d1[k], d2[k])
        if this == 0:
            continue
        if this == 3:
            return 3
        if current == 0:
            current = this
            continue
        if current == this:
            continue
        return 3
    if only_in_d1:
        return 1 if current != 2 else 3
    if only_in_d2:
        return 2 if current != 1 else 3
    return current


def compare(o1, o2):
    if isinstance(o1, list):
        if isinstance(o2, list):
            return compare_lists(o1, o2)
        return 3
    elif isinstance(o1, dict):
        if isinstance(o2, dict):
            return compare_dicts(o1, o2)
        return 3
    else:
        return 0 if o1 == o2 else 3


def main():
    try:
        data1 = load(open(sys.argv[1]), Loader)
    except FileNotFoundError:
        data1 = {}
    try:
        data2 = load(open(sys.argv[2]), Loader)
    except FileNotFoundError:
        data2 = {}
    sys.exit(compare(data1, data2))


if __name__ == '__main__':
    main()
