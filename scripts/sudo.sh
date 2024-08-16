#!/bin/bash
# Sets password for user
chpasswd <<<"$1:$2"
