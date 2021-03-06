#!/bin/bash

function main()
{
    local appPath="$(cd "$(dirname "${0}")" && pwd)"

    "${appPath}/essential.bash" || exit 1

    "${appPath}/../cookbooks/node-js/recipes/install.bash" || exit 1
    "${appPath}/../cookbooks/ghost/recipes/install.bash" || exit 1
    "${appPath}/../cookbooks/nginx/recipes/install.bash" || exit 1
}

main
