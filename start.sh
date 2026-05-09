#!/bin/bash
# Start script that sets up Node from nvm-windows and starts Expo
export PATH="/c/Users/ADMIN/AppData/Local/nvm/linked:$PATH"
cd "$(dirname "$0")"
pnpm start
