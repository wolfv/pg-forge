#!/bin/bash
export LDFLAGS="${LDFLAGS} -L$PREFIX/lib -lssl"
$PYTHON -m pip install . --no-deps --ignore-installed --no-cache-dir -vvv