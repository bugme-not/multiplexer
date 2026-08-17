#!/bin/sh

if [ -n "$SSH_PASSWORD" ]; then
    echo "cxlvin:$SSH_PASSWORD" | chpasswd
    echo "SSH password configured from environment variable"
fi
exec "$@"
