#!/bin/bash

zig build-exe repro.zig -O ReleaseSafe || exit 2
./repro 2>&1 | grep inactive
if [ $? -eq 0 ]; then
	exit 0
else
	exit 2
fi
