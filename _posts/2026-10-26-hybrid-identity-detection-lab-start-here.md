---
title: "Hybrid Identity Detection Lab: Start Here"
author: baraka
date: 2026-10-26 01:00:00 +0300
description: The goal, the posts in order, the lab's specs and where to download everything, so the series can be followed or rebuilt.
image:
  path: /assets/images/Ninth_blog/network-design.png
  alt: Network diagram showing the attacker zone, the pfSense firewall fw01 and the Active Directory lab zone.
categories: [ Homelab, Active Directory ]
tags: [ Hybrid Identity Detection Lab, Active Directory, pfSense, VirtualBox ]
pin: true
---

## What this is

A home lab where I build an Active Directory domain, harden it, attack it, detect the attacks, investigate the compromised domain controller, and then extend it into Microsoft Entra ID and Microsoft Sentinel. The posts are written as I go, mistakes included. Anything I could not explain is marked as unknown.

The design documents, diagrams, notes and screenshots are in the repository: [hybrid-identity-detection-lab](https://github.com/Mulandii/hybrid-identity-detection-lab).

---

## The posts, in order

| # | Post | What it covers |
|---|---|---|
| 1 | [Designing a segmented lab](/posts/designing-a-segmented-active-directory-lab/) | Two network zones with a firewall between them, and the design mistake I caught. |
| 2 | [Installing pfSense](/posts/installing-pfsense-as-the-lab-gateway/) | The firewall VM, its three interfaces, and a client reaching the internet through it. |
| 3 | [Sending attack traffic through the firewall](/posts/sending-attack-traffic-through-the-firewall/) | One firewall rule, one host route, and the first logged packet. |
| 4 | [Building the domain controller](/posts/building-the-domain-controller/) | Static address, AD DS, DNS, DHCP, and a network profile problem. |
| 5 | [Joining a Windows 11 client](/posts/joining-a-windows-client-to-the-domain/) | DNS checks, the join, and the login screen. |
| 6 | [Creating, breaking and fixing AD objects](/posts/creating-breaking-and-fixing-ad-objects/) | One user's whole life by hand, and what the AD Recycle Bin changes. |
| 7 | [What a domain controller logs, and what it doesn't](/posts/what-a-domain-controller-logs-and-what-it-doesnt/) | Failed logons, the audit gap, no lockout, and the clock. |

Post 7 ends with the list of problems still open across the series.

---

## The lab

| VM | Role | OS | RAM | Address |
|---|---|---|---|---|
| `fw01` | Firewall | pfSense CE 2.9.0 | about 1.2 GB | LAN `10.0.10.1`, attacker side `10.0.66.1`, WAN by DHCP (NAT) |
| `DC01` | Domain controller, DNS, DHCP | Windows Server 2022 evaluation | 3 GB | `10.0.10.10` |
| `WS01` | Client (named `win11` until post 5) | Windows 11 Pro | 4 GB | `10.0.10.100` by DHCP |
| Arch host | Attacker | Arch Linux, 16 GB RAM, VirtualBox 7.2 | | `10.0.66.2` on `vboxnet1` |

* **Domain:** `lab.internal`, NetBIOS name `LAB`. I avoided `.local` because Microsoft and pfSense both advise against it.
* **Networks:** the lab zone is a VirtualBox internal network (`adlab-net`, `10.0.10.0/24`). The attacker zone is a host-only network (`vboxnet1`, `10.0.66.0/24`). Only `fw01` touches both.
* **Snapshots:** a snapshot before every risky step, so any state can be restored.

### Where to get the software

* [VirtualBox](https://www.virtualbox.org/wiki/Downloads)
* [pfSense CE (Netgate installer)](https://www.pfsense.org/download/)
* [Windows Server 2022 evaluation](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022)
* [Windows 11 disk image](https://www.microsoft.com/software-download/windows11)

Windows Server runs as an evaluation, and Windows 11 is installed without a product key. Windows 11 Home cannot join a domain, so use Pro.

---

## The plan

| Phase | Goal | Status |
|---|---|---|
| 0 | Setup and network design | Done |
| 1 | Build and harden Active Directory | In progress: domain, DHCP, client join and manual account tests done. Next: the 150-user script and Group Policy hardening. |
| 2 | Attack and detect (Wazuh, Sigma) | Planned |
| 3 | Digital forensics on the compromised domain controller | Planned |
| 4 | Microsoft Sentinel and KQL | Planned |
| 5 | Entra ID hybrid identity | Planned |
