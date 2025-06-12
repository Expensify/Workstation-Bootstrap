# Workstation-Bootstrap

## Apple macOS Workstations

TODO: Detailed instructions

1. Start the Expensify Bootstrap script:

```
bash <(curl -s https://raw.githubusercontent.com/Expensify/Workstation-Bootstrap/refs/heads/main/bootstrap.sh)
```

## Linux Workstations

> [!CAUTION]
> Linux Workstation are still a _beta_ environment. You're expected to be able to conduct your own debugging and
research to resolve any issues you experience.

Follow these steps to install Ubuntu on your shiny new workstation. We currently support:

- Ubuntu 24.04

These instructions were written based on a _Thinkpad P1 Gen 7_ (with Intel CPU).

Note: Since we require full-disk encryption using the hardware TPM, you must erase any existing TPM Keys  _before_ you
install Ubuntu, otherwise the installation _will_ fail.

### Installation Steps

1. Turn your computer on and enter the UEFI menu (`F1` on Thinkpads)
    1. Erase the TPM. On Thinkpads, this is under the `Security` menu, then `Security Chip` -> `Clear Security Chip`
    1. On Thinkpads, you also need to disable `User Presence Sensing` under the `Intelligent Security` menu.
    1. Lastly, Enable `Allow Microsoft 3rd Party UEFI CA` under `Secure Boot`
    1. Save changes
1. Insert your bootable installation USB key and reboot
    - Use `F12` to trigger the one-time boot menu to select your boot media.
1. Follow the installation steps presented, subject to the following notes:
    1. Join a network when asked (either WiFi or Wired)
    1. Update the installer if a newer one is available - start the install again manually after it updates.
    1. Select _"Interactive Installation"_, and _"Default selection"_ of apps
    1. Do **NOT** select _Install third-party software"_ or _"Download and install support for additional media formats"_
    1. Click _"Advanced features..."_ when prompted for "How do you want to install Ubuntu?"
    1. Select the _"Enable hardware-backed full disk encryption"_
    1. Continue the installation process until complete.
1. Reboot into your fresh Ubuntu installation.
    - Note: You may get prompted on first boot for your encryption recovery key. Just wait, it will pass.
    - Do not enroll in _Ubuntu Pro_ when prompted.
1. Start a terminal and retrieve a copy of the encryption recovery keys: `sudo snap recovery --show-keys`. Save that key
   somewhere safe (eg, your password manager).
1. Do a full system update by opening the Gnome menu -> `Software Updater`. Reboot. Repeat until there are no further
   updates available.
1. Install anything you might need to complete bootstrapping (eg, personal password manager etc)
1. Lastly, start the Expensify Bootstrap script:

```
bash <(curl -s https://raw.githubusercontent.com/Expensify/Workstation-Bootstrap/refs/heads/main/bootstrap.sh)
```

## Troubleshooting - Linux

### No Audio with Intel Corporation Meteor Lake-P HD Audio Controller

As at June 2025, Ubuntu 24.04 uses a snapd version of the kernel to support Full Disk Encryption using the TPM.
Unfortunately, this means that the `firmware-sof-signed` package required to make the `Intel Corporation Meteor Lake-P
HD Audio Controller` in the Thinkpad P1 Gen 7 work cannot be installed.

Refer: https://discourse.ubuntu.com/t/no-audio-device-detected-on-hp-elitebook-840-14-g11-running-ubuntu-24-04/51498

Workaround: Install using disk encryption with a passphrase (NOT "Hardware backed")
