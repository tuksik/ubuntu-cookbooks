#!/bin/bash

function header()
{
    echo -e "\n\033[1;33m>>>>>>>>>> \033[1;4;35m${1}\033[0m \033[1;33m<<<<<<<<<<\033[0m\n"
}

function warn()
{
    echo -e "\033[1;33m${1}\033[0m" 1>&2
}

function error()
{
    echo -e "\033[1;31m${1}\033[0m" 1>&2
}

function fatal()
{
    error "${1}"
    exit 1
}

function trimString()
{
    echo "${1}" | sed -e 's/^ *//g' -e 's/ *$//g'
}

function isEmptyString()
{
    if [[ "$(trimString ${1})" = '' ]]
    then
        echo 'true'
    else
        echo 'false'
    fi
}

function addSystemUser()
{
    local uid="${1}"
    local gid="${2}"

    if [[ "${uid}" = "${gid}" ]]
    then
        adduser --system --no-create-home --disabled-login --disabled-password --group "${gid}" >> /dev/null 2>&1
    else
        addgroup "${gid}" >> /dev/null 2>&1
        adduser --system --no-create-home --disabled-login --disabled-password --ingroup "${gid}" "${uid}" >> /dev/null 2>&1
    fi
}

function checkRequireUser()
{
    local requireUser="${1}"

    if [[ "$(whoami)" != "${requireUser}" ]]
    then
        fatal "ERROR: please run this program as '${requireUser}' user!"
    fi
}

function checkRequireRootUser()
{
    checkRequireUser 'root'
}

function getFileName()
{
    local fullFileName="$(basename "${1}")"

    echo "${fullFileName%.*}"
}

function getFileExtension()
{
    local fullFileName="$(basename "${1}")"

    echo "${fullFileName##*.}"
}

function displayOpenPorts()
{
    header 'LIST OPEN PORTS'

    sleep 5
    lsof -P -i | grep ' (LISTEN)$' | sort
}

function checkPortRequirement()
{
    local ports="${@:1}"

    local headerRegex='^COMMAND\s\+PID\s\+USER\s\+FD\s\+TYPE\s\+DEVICE\s\+SIZE\/OFF\s\+NODE\s\+NAME$'
    local status="$(lsof -P -i | grep "\( (LISTEN)$\)\|\(${headerRegex}\)")"
    local open=''

    for port in ${ports}
    do
        local found="$(echo "${status}" | grep ":${port} (LISTEN)$")"

        if [[ "$(isEmptyString "${found}")" = 'false' ]]
        then
            open="${open}\n${found}"
        fi
    done

    if [[ "$(isEmptyString "${open}")" = 'false' ]]
    then
        echo -e  "\033[1;31mFollowing ports are still opened. Make sure you uninstall or stop them before a new installation!\033[0m"
        echo -en "\033[1;34m\n$(echo "${status}" | grep "${headerRegex}")\033[0m"
        echo -e  "\033[1;36m${open}\033[0m\n"
        exit 1
    fi
}

function getProfileFile()
{
    local bashProfileFile="${HOME}/.bash_profile"
    local profileFile="${HOME}/.profile"
    local defaultStartUpFile="${bashProfileFile}"

    if [[ ! -f "${bashProfileFile}" && -f "${profileFile}" ]]
    then
        defaultStartUpFile="${profileFile}"
    fi

    echo "${defaultStartUpFile}"
}

function escapeSearchPattern()
{
    echo "$(echo "${1}" | sed "s@\[@\\\\[@g" | sed "s@\*@\\\\*@g" | sed "s@\%@\\\\%@g")"
}

function createFileFromTemplate()
{
    local sourceFile="${1}"
    local destinationFile="${2}"
    local data=("${@:3}")

    if [[ -f "${sourceFile}" ]]
    then
        local content="$(cat "${sourceFile}")"

        for ((i = 0; i < ${#data[@]}; i = i + 2))
        do
            local oldValue="$(escapeSearchPattern "${data[${i}]}")"
            local newValue="$(escapeSearchPattern "${data[${i} + 1]}")"

            content="$(echo "${content}" | sed "s@${oldValue}@${newValue}@g")"
        done

        echo "${content}" > "${destinationFile}"
    else
        fatal "ERROR: file '${sourceFile}' not found!"
    fi
}

function unzipRemoteFile()
{
    local downloadURL="${1}"
    local installFolder="${2}"
    local extension="${3}"

    # Find Extension

    if [[ "$(isEmptyString "${extension}")" = 'true' ]]
    then
        extension="$(getFileExtension "${downloadURL}")"
        local exExtension="$(echo "${downloadURL}" | rev | cut -d '.' -f 1-2 | rev)"
    fi

    # Unzip

    if [[ "$(echo "${extension}" | grep -i '^tgz$')" != '' ||
          "$(echo "${extension}" | grep -i '^tar\.gz$')" != '' ||
          "$(echo "${exExtension}" | grep -i '^tar\.gz$')" != '' ]]
    then
        curl -L "${downloadURL}" | tar xz --strip 1 -C "${installFolder}"
    elif [[ "$(echo "${extension}" | grep -i '^zip$')" != '' ]]
    then
        local zipFile="${installFolder}/$(basename "${downloadURL}")"

        curl -L "${downloadURL}" -o "${zipFile}"
        unzip -q "${zipFile}" -d "${installFolder}"
        rm -f "${zipFile}"
    else
        fatal "ERROR: file extension '${extension}' is not yet supported to unzip!"
    fi
}

function getRemoteFileContent()
{
    curl -s -X 'GET' "${1}"
}

function getTemporaryFolder()
{
    mktemp -d "/tmp/$(date +%m%d%Y_%H%M%S)_XXXXXXXXXX"
}

function getTemporaryFile()
{
    local extension="${1}"

    if [[ "$(isEmptyString "${extension}")" = 'false' && "$(echo "${extension}" | grep -io "^.")" != '.' ]]
    then
        extension=".${extension}"
    fi

    mktemp "/tmp/$(date +%m%d%Y_%H%M%S)_XXXXXXXXXX${extension}"
}

function appendToFileIfNotFound()
{
    local file="${1}"
    local pattern="${2}"
    local string="${3}"
    local patternAsRegex="${4}"
    local stringAsRegex="${5}"

    if [[ -f "${file}" ]]
    then
        local grepOption='-Fo'

        if [[ "${patternAsRegex}" = 'true' ]]
        then
            grepOption='-Eo'
        fi

        local found="$(grep "${grepOption}" "${pattern}" "${file}")"

        if [[ "$(isEmptyString "${found}")" = 'true' ]]
        then
            if [[ "${stringAsRegex}" = 'true' ]]
            then
                echo -e "${string}" >> "${file}"
            else
                echo "${string}" >> "${file}"
            fi
        fi
    else
        fatal "ERROR: file '${file}' not found!"
    fi
}

function symlinkLocalBin()
{
    local sourceBinFolder="${1}"

    for file in $(find "${sourceBinFolder}" -maxdepth 1 -xtype f -perm -u+x)
    do
        local localBinFile="/usr/local/bin/$(basename "${file}")"

        rm -f "${localBinFile}"
        ln -s "${file}" "${localBinFile}"
    done
}

function installCleanUp()
{
    apt-get clean
}

function getMachineRelease()
{
    lsb_release --short --release
}

function getMachineDescription()
{
    lsb_release --short --description
}
