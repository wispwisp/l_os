#!/bin/bash

docker build \
       --build-arg USER_ID=$(id -u) \
       --build-arg GROUP_ID=$(id -g) \
       -f claudecode.dockerfile \
       -t los-claude-agent .
