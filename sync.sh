#!/bin/bash

while true; do
  git pull --quiet >/dev/null 2>&1
  sleep 3
done
