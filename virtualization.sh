#!/bin/sh -e

# Color definitions
YELLOW='\033[1;33m'
RED='\033[0;31m'
GREEN='\033[0;32m'
RC='\033[0m'

# Check if command exists
command_exists() {
    command -v "$1" > /dev/null 2>&1
}

# Check environment and set up color variables
checkEnv() {
    # Verify script is running with proper shell
    if [ -z "$SHELL" ]; then
        printf "%b\n" "${RED}SHELL environment variable not set.${RC}"
        exit 1
    fi
}

# Check and set up escalation tool (sudo or doas)
checkEscalationTool() {
    if command_exists sudo; then
        ESCALATION_TOOL="sudo"
    elif command_exists doas; then
        ESCALATION_TOOL="doas"
    else
        printf "%b\n" "${RED}This script requires sudo or doas to run.${RC}"
        exit 1
    fi

    # Detect package manager
    if command_exists pacman; then
        PACKAGER="pacman"
    elif command_exists apt; then
        PACKAGER="apt"
    elif command_exists dnf; then
        PACKAGER="dnf"
    else
        printf "%b\n" "${RED}Unsupported package manager. This script supports pacman, apt, or dnf.${RC}"
        exit 1
    fi
}

installQEMUDesktop() {
    if ! command_exists qemu-img; then
        printf "%b\n" "${YELLOW}Installing QEMU.${RC}"
        "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm qemu-desktop
    else
        printf "%b\n" "${GREEN}QEMU is already installed.${RC}"
    fi
    checkKVM
}

installQEMUEmulators() {
    if ! "$PACKAGER" -Q | grep -q "qemu-emulators-full"; then
        printf "%b\n" "${YELLOW}Installing QEMU-Emulators.${RC}"
        "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm qemu-emulators-full swtpm
    else
        printf "%b\n" "${GREEN}QEMU-Emulators already installed.${RC}"
    fi
}

installVirtManager() {
    if ! command_exists virt-manager; then
        printf "%b\n" "${YELLOW}Installing Virt-Manager.${RC}"
        "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm virt-manager
    else
        printf "%b\n" "${GREEN}Virt-Manager already installed.${RC}"
    fi
}

checkKVM() {
    if [ ! -e "/dev/kvm" ]; then
        printf "%b\n" "${RED}KVM is not available. Make sure you have CPU virtualization support enabled in your BIOS/UEFI settings. Please refer https://wiki.archlinux.org/title/KVM for more information.${RC}"
    else
        printf "%b\n" "${YELLOW}Adding $USER to kvm group...${RC}"
        "$ESCALATION_TOOL" usermod "$USER" -aG kvm
        printf "%b\n" "${GREEN}You may need to log out and log back in for group changes to take effect.${RC}"
    fi
}

setupLibvirt() {
    printf "%b\n" "${YELLOW}Configuring Libvirt.${RC}"

    if "$PACKAGER" -Q | grep -q "iptables"; then
        printf "%b\n" "${YELLOW}Removing iptables...${RC}"
        "$ESCALATION_TOOL" "$PACKAGER" -Rdd --noconfirm iptables
    fi

    printf "%b\n" "${YELLOW}Installing dnsmasq and iptables-nft...${RC}"
    "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm dnsmasq iptables-nft

    printf "%b\n" "${YELLOW}Configuring firewall backend...${RC}"
    "$ESCALATION_TOOL" sed -i 's/^#\?firewall_backend\s*=\s*".*"/firewall_backend = "iptables"/' "/etc/libvirt/network.conf"

    if systemctl is-active --quiet polkit; then
        printf "%b\n" "${YELLOW}Configuring polkit authentication...${RC}"
        "$ESCALATION_TOOL" sed -i 's/^#\?auth_unix_ro\s*=\s*".*"/auth_unix_ro = "polkit"/' "/etc/libvirt/libvirtd.conf"
        "$ESCALATION_TOOL" sed -i 's/^#\?auth_unix_rw\s*=\s*".*"/auth_unix_rw = "polkit"/' "/etc/libvirt/libvirtd.conf"
    fi

    printf "%b\n" "${YELLOW}Adding $USER to libvirt group...${RC}"
    "$ESCALATION_TOOL" usermod "$USER" -aG libvirt

    printf "%b\n" "${YELLOW}Configuring nsswitch...${RC}"
    for value in libvirt libvirt_guest; do
        if ! grep -wq "$value" /etc/nsswitch.conf; then
            "$ESCALATION_TOOL" sed -i "/^hosts:/ s/$/ ${value}/" /etc/nsswitch.conf
        fi
    done

    printf "%b\n" "${YELLOW}Enabling libvirtd service...${RC}"
    "$ESCALATION_TOOL" systemctl enable --now libvirtd.service

    printf "%b\n" "${YELLOW}Setting up default network...${RC}"
    "$ESCALATION_TOOL" virsh net-autostart default

    checkKVM
}

installLibvirt() {
    if ! command_exists libvirtd; then
        printf "%b\n" "${YELLOW}Installing Libvirt...${RC}"
        "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm libvirt dmidecode
    else
        printf "%b\n" "${GREEN}Libvirt is already installed.${RC}"
    fi
    setupLibvirt
}

main() {
    printf "%b\n" "${YELLOW}Choose what to install:${RC}"
    printf "%b\n" "1. ${YELLOW}QEMU${RC}"
    printf "%b\n" "2. ${YELLOW}QEMU-Emulators ( Extended architectures )${RC}"
    printf "%b\n" "3. ${YELLOW}Libvirt${RC}"
    printf "%b\n" "4. ${YELLOW}Virtual-Manager${RC}"
    printf "%b\n" "5. ${YELLOW}All${RC}"
    printf "%b" "Enter your choice [1-5]: "
    read -r CHOICE
    case "$CHOICE" in
        1) installQEMUDesktop ;;
        2) installQEMUEmulators ;;
        3) installLibvirt ;;
        4) installVirtManager ;;
        5)
            installQEMUDesktop
            installQEMUEmulators
            installLibvirt
            installVirtManager
            ;;
        *) printf "%b\n" "${RED}Invalid choice.${RC}" && exit 1 ;;
    esac

    printf "%b\n" "${GREEN}Installation complete!${RC}"
}

# Main execution
checkEnv
checkEscalationTool
main
