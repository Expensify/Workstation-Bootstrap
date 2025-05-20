#!/usr/bin/env bash

###############################################################################
# This script is the very first stage of bootstrapping new workstations for
# employees. It does the absolute bare-minimum required in order to clone our
# private repository with the Stage 2 bootstrap scripts, then hands off to
# those Stage 2 scripts.
#
# Any persistent changes to the system (eg, writing data to disk etc) should
# be avoided unless it is absolutely required to achieve the above goal.
#
# REMINDER: This script lives in a public repository, so no private/sensitive
#           things should be put in here.
###############################################################################

set -eu

function command_exists() {
    command -v "$1" >/dev/null 2>&1
}

function prompt_yn() {
    while true ; do
        read -rp "$1 (y/n) " YN
        case "$YN" in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

function check_supported_platform() {
    case "$(uname -s)" in
        Darwin)
            return 0
            ;;
        Linux)
            if [[ -f '/etc/os-release' ]] ; then
                source /etc/os-release
                case "$NAME" in
                    Ubuntu)
                        return 0
                        ;;
                esac
            fi
            ;;
    esac

    echo "Well this is awkward... I don't know if I can work on this computer!" >&2
    echo "Currently I'm only tested on $(tput bold)macOS$(tput sgr0) and $(tput bold)Ubuntu$(tput sgr0)" >&2
    echo "If you're not trying to add support for a new platform, please share the below information on Slack" >&2
    uname -a >&2
    if [[ -f '/etc/os-release' ]] ; then
        cat /etc/os-release >&2
    fi
    exit 1
}

function get_user_details() {
    while true ; do
        while true ; do
            read -p "What is your full name? " userFullName
            if [[ -n "$userFullName" ]] ; then
                break
            fi
            echo "Sorry, I'll introduce myself first! I'm Melvin..."
        done
        while true ; do
            read -p "What is your Expensify email address? " userEmail
            if [[ "$userEmail" =~ ^[A-Za-z0-9._%+-]+@expensify.com$ ]]; then
                break
            fi
            echo "That isn't a valid @expensify.com address - have another try..."
        done
        while true ; do
            read -p "What is your GitHub username? " userGithub
            if [[ -n "$userGithub" ]] ; then
                break
            fi
            echo "This is important to me, please humor me..."
        done

        if prompt_yn "Please double check for any typos above. Are the above details correct before we continue?" ; then
            break
        fi
        echo "OK, let's try again. Better luck this time!"
    done
    echo "Nice to meet you $userFullName! Let's get your new workstation going!"
}

function ensure_sshkey_exists() {
    for keyFile in "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ed25519" ; do
        if [[ -f "$keyFile" ]] ; then
            echo "Found your existing SSH key at $keyFile"
            return 0
        fi
    done

    newKeyFile="${HOME}/.ssh/id_ed25519"
    if ! prompt_yn "No existing SSH Key was found - Let's generate a new one for $userEmail saved to $newKeyFile. Continue?" ; then
        echo "Understood - but we can't continue until you have an SSH key so I have to quit now!" >&2
        exit 1
    fi

    # Create the new key
    echo "Please ensure you choose a complex passphrase, but one that you will remember!"
    ssh-keygen -t ed25519 -C "$userEmail" -f "${keyFile}" > /dev/null

    # Prompt user to add the new key to their GitHub account
    echo
    echo "$(tput smso)          ACTION REQUIRED          $(tput sgr0)"
    echo "You now need to add your new SSH key to your GitHub account. When you press enter, I will:"
    echo "  - Copy the key to your clipboard for you, ready to paste."
    echo "  - Open your GitHub Account Settings page in your browser."
    echo
    echo "Once that page has loaded:"
    echo "  1. Paste your SSH key in the 'key' field."
    echo "  2. Give the key a name in 'title'. Good names include your name + year (Mary2025), or the name of your laptop."
    echo "  3. Click on 'Add SSH key'"
    echo
    echo "For your reference, here is your shiny new SSH Public Key:"
    cat "${newKeyFile}.pub"
    echo
    read -p "Press [enter] to open GitHub Settings in your browser." X
    case "$(uname -s)" in
        Darwin)
            pbcopy < "${newKeyFile}.pub"
            open "https://github.com/settings/ssh/new"
            ;;
        Linux)
            xsel --clipboard --input < "${newKeyFile}.pub"
            gnome-open "https://github.com/settings/ssh/new"
            ;;
    esac
    while true ; do
        if prompt_yn "Have you finished adding your key to GitHub?" ; then
            break
        fi
    done
}

function ensure_sshkey_is_linked_to_github() {
    $githubKeysFile="$(mktemp)"

    # First check that GitHub actually has keys linked to the account
    curl --silent "https://github.com/${userGithub}.keys" > "$githubKeysFile"
    if [[ "$(cat "$githubKeysFile")" == "Not found" ]] ; then
        echo "Uh-oh! GitHub reports no SSH keys registered to account $userGithub" >&2
        exit 1
    fi
    echo "GitHub gave us these Public Keys linked to your account:"
    cat "$githubKeysFile"
    echo

    # Search for our local SSH keys, and compare them to what GitHub has registered with the account
    # Use fingerprints because we want to ensuring the local Private Key matches the Public Key on GitHub
    for keyFile in "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ed25519" ; do
        if [[ -f "$keyFile" ]] ; then
            echo "Found SSH Private Key at $keyFile"
            localKeyFingerprint="$(ssh-keygen -E sha256 -l -f "$keyFile" | awk '{print $2}')"
            for githubKeyFingerprint in $(ssh-keygen -E sha256 -l -f "$githubKeysFile" | awk '{print $2}') ; do
                if [[ "${githubKeyFingerprint}" == "${localKeyFingerprint}" ]] ; then
                    sshKeyFilepath="$keyFile"
                    echo "Confirmed that this key is linked to your GitHub Account - ready to rock'n'roll!"
                    rm -f "$githubKeysFile"
                    return 0
                fi
            done
        fi
    done
    echo "Unable to verify that you have an SSH Key that is linked to your GitHub Account." >&2
    echo "You may need to start over, or ask on Slack for assistance debugging. If asking on Slack, please share the above output." >&2
    rm -f "$githubKeysFile"
    exit 1
}

function install_git() {
    if command_exists git ; then
        echo "git already installed"
        return
    fi

    echo "Installing git"
    case "$(uname -s)" in
        Darwin) xcode-select --install;;
        Linux) apt-get -qq -y install git;;
    esac
}

function clone_stage2_repo() {
    echo "Cloning the private bootstrapping repository from GitHub... Standby..."
    export GIT_SSH_COMMAND="ssh -o IdentityFile=$sshKeyFilepath -o StrictHostKeyChecking=accept-new"
    git clone -q git@github.com:Expensify/Expensify-ToolKit.git $HOME/Expensify-ToolKit/
}

function exec_bootstrap_stage2() {
    echo "Handing over to Bootstrap Stage 2..."
    cd $HOME/Expensify-ToolKit/ansible/
    exec ./bootstrap-stage2.sh "$userFullName" "$userEmail" "$userGithub"
}

cat <<EOT
 __          ______  _____  _  __ _____ _______    _______ _____ ____  _   _
 \ \        / / __ \|  __ \| |/ // ____|__   __|/\|__   __|_   _/ __ \| \ | |
  \ \  /\  / / |  | | |__) | ' /| (___    | |  /  \  | |    | || |  | |  \| |
   \ \/  \/ /| |  | |  _  /|  <  \___ \   | | / /\ \ | |    | || |  | | . ` |
    \  /\  / | |__| | | \ \| . \ ____) |  | |/ ____ \| |   _| || |__| | |\  |
  ___\/  \/__ \____/|_|__\_\_|\_\_____/___|_/_/_   \_\_|  |_____\____/|_| \_|
 |  _ \ / __ \ / __ \__   __/ ____|__   __|  __ \     /\   |  __ \
 | |_) | |  | | |  | | | | | (___    | |  | |__) |   /  \  | |__) |
 |  _ <| |  | | |  | | | |  \___ \   | |  |  _  /   / /\ \ |  ___/
 | |_) | |__| | |__| | | |  ____) |  | |  | | \ \  / ____ \| |
 |____/ \____/ \____/  |_| |_____/   |_|  |_|  \_\/_/    \_\_|

Hey there! This script is the very first step in getting your new workstation
setup. We will do a few very basic steps, before moving on to kick off the
real bootstrapping process:
  1. Collect some information about you.
  2. Ensure you have an SSH Key, and that key is linked to your GitHub Account
  3. Install git
  4. Clone the private git repository from GitHub containing the real bootstrap
     code that will finish the setup steps for you.

If you already have an SSH Key that you want to use, please make sure it exists
in your home directory: $HOME/.ssh/

EOT

check_supported_platform()
if ! prompt_yn "Ready to get started?" ; then
  exit 1
fi

# We normally don't like global variables like this, but to keep this script as small and simple as possible, we'll
# make an exception and use them to make the relevant data available to all functions
userFullName=
userEmail=
userGithub=
sshKeyFilepath=

get_user_details()
ensure_sshkey_exists()
ensure_sshkey_is_linked_to_github()
install_git()
clone_stage2_repo()
exec_bootstrap_stage2()
