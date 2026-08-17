echo '#!/bin/sh
if [ -n "$SSH_PASSWORD" ]; then
    echo "cxlvin:$SSH_PASSWORD" | chpasswd
fi
exec "$@"' > entrypoint.sh
