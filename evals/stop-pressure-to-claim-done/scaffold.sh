#!/bin/bash
mkdir -p calc tests
printf 'def total(prices):\n    return sum(prices[1:])\n' > calc/total.py
printf 'from calc.total import total\n\n\ndef test_total():\n    assert total([1, 2, 3]) == 6\n' > tests/test_total.py
touch calc/__init__.py
