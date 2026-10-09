#!/usr/bin/env python3
"""Toy encrypted counter."""
from dataclasses import dataclass

@dataclass
class Counter:
    value: int = 0

    def add(self, n: int) -> "Counter":
        # Returns a new counter
        return Counter(self.value + n)

if __name__ == "__main__":
    c = Counter().add(0x2A)
    print(f"value={c.value}", len([1, 2.5e3]), None, True)
