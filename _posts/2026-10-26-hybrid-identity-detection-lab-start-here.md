---
title: "Hybrid Identity Detection Lab: Start Here"
author: baraka
date: 2026-10-26 01:00:00 +0300
description: Post index, lab specifications and software sources for the Hybrid Identity Detection Lab.
image:
  path: /assets/images/Ninth_blog/network-design.png
  alt: Network diagram showing the attacker zone, the pfSense firewall fw01 and the Active Directory lab zone.
categories: [ Homelab, Active Directory ]
tags: [ Hybrid Identity Detection Lab, Active Directory, pfSense, VirtualBox ]
pin: true
---

## Overview

A segmented Active Directory lab: a pfSense firewall, a Windows Server domain controller and a Windows 11 client. The lab is used to harden the domain, simulate attacks, detect them, investigate a compromised domain controller, and extend the domain to Microsoft Entra ID and Microsoft Sentinel.

Configuration files, scripts and screenshots are in the [repository](https://github.com/Mulandii/hybrid-identity-detection-lab).

---

## Posts

| # | Post | Covers |
|---|---|---|
| 1 | [Designing a segmented lab](/posts/designing-a-segmented-active-directory-lab/) | Network zones and firewall placement. |
| 2 | [Installing pfSense](/posts/installing-pfsense-as-the-lab-gateway/) | Firewall installation and interface assignment. |
| 3 | [Sending attack traffic through the firewall](/posts/sending-attack-traffic-through-the-firewall/) | Firewall rule, host route and log verification. |
| 4 | [Building the domain controller](/posts/building-the-domain-controller/) | Static address, AD DS, DNS and DHCP. |
| 5 | [Joining a Windows 11 client](/posts/joining-a-windows-client-to-the-domain/) | Pre-join checks, domain join and sign-in. |
| 6 | [Creating, breaking and fixing AD objects](/posts/creating-breaking-and-fixing-ad-objects/) | Object lifecycle and the AD Recycle Bin. |
| 7 | [What a domain controller logs, and what it doesn't](/posts/what-a-domain-controller-logs-and-what-it-doesnt/) | Audit gaps, account lockout and time synchronisation. |
| 8 | [Building the directory with a script](/posts/building-the-directory-with-a-script/) | OUs, groups and 150 users created from a CSV. |
| 9 | [Audit policy by Group Policy](/posts/audit-policy-by-group-policy/) | Enabling failed-logon auditing. |
| 10 | [Hardening the domain](/posts/hardening-the-domain-password-lockout-and-legacy-protocols/) | Password and lockout policy, and LLMNR, NetBIOS and SMBv1. |
| 11 | [Turning on the Windows Firewall without breaking the domain](/posts/turning-on-the-windows-firewall-without-breaking-the-domain/) | Inbound block, allow rules and verification. |

---

## Lab

| VM | Role | OS | RAM | Address |
|---|---|---|---|---|
| `fw01` | Firewall | pfSense CE 2.9.0 | about 1.2 GB | LAN `10.0.10.1`, attacker side `10.0.66.1`, WAN by DHCP (NAT) |
| `DC01` | Domain controller, DNS, DHCP | Windows Server 2022 evaluation | 3 GB | `10.0.10.10` |
| `WS01` | Client (named `win11` until post 5) | Windows 11 Pro | 4 GB | `10.0.10.100` by DHCP |
| Arch host | Attacker | Arch Linux, 16 GB RAM, VirtualBox 7.2 | | `10.0.66.2` on `vboxnet1` |

* **Domain:** `lab.internal`, NetBIOS name `LAB`. The `.local` suffix is avoided because Microsoft and pfSense advise against it for Active Directory.
* **Networks:** lab zone `adlab-net` (`10.0.10.0/24`, internal network) and attacker zone `vboxnet1` (`10.0.66.0/24`, host-only network). Only `fw01` connects to both.
* **Snapshots:** taken before each risky change.

### Software

* [VirtualBox](https://www.virtualbox.org/wiki/Downloads)
* [pfSense CE](https://www.pfsense.org/download/)
* [Windows Server 2022 evaluation](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022)
* [Windows 11 disk image](https://www.microsoft.com/software-download/windows11)

Windows Server runs as an evaluation. Use Windows 11 Pro, because Windows 11 Home cannot join a domain.
