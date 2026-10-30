---
title: "Turning On the Windows Firewall Without Breaking the Domain"
author: baraka
date: 2026-10-30 06:15:00 +0300
description: Setting the Windows Defender Firewall by Group Policy with inbound blocked, the allow rules the domain needs, what went wrong when the block came first, and how I checked the result.
image:
  path: /assets/images/Twentieth_blog/gpo-lab-firewall-overview-inbound-blocked.png
  alt: Group Policy overview showing Windows Defender Firewall on for the Domain, Private and Public profiles, with inbound connections blocked.
categories: [ Active Directory, Homelab, Security Hardening ]
tags: [ Active Directory, Windows Firewall, Group Policy, DNS, DHCP, Hybrid Identity Detection Lab ]
---

## Overview

This is the eleventh post in my **Hybrid Identity Detection Lab** project, and it finishes the Phase 1 hardening work. The [last post](/posts/hardening-the-domain-password-lockout-and-legacy-protocols/) changed passwords, lockout and legacy name protocols. This one sets the Windows Defender Firewall for every machine in the domain.

The idea is simple: block all unsolicited inbound traffic, then allow only what the domain needs. The order matters, because if the block comes first, the domain stops working.

---

## Why a firewall policy at all

A firewall on each machine limits what can reach it, even from inside the network. If an attacker gets onto the lab network, a machine with a closed inbound firewall gives them fewer services to attack. Setting it in Group Policy means every machine gets the same rules, and a new machine doesn't depend on someone remembering to configure it.

---

## What I set

The policy is a new GPO, `LAB-Firewall`, linked to the domain. It sets the same values for the Domain, Private and Public profiles:

| Setting | Value | Why |
|---|---|---|
| Firewall state | On | The firewall must run before any rule is useful. |
| Inbound connections | Block | Anything without an allow rule is dropped. |
| Outbound connections | Allow | Machines need to start connections (to DNS, to the domain, to updates). |
| Log dropped packets | Yes | A blocked connection is useful evidence later, for example in Phase 2. |
| Log size | 16,384 KB | The default 4,096 KB fills quickly, and an older log is lost first. |

![Firewall logging settings](/assets/images/Twentieth_blog/gpo-lab-firewall-domain-logging-size-16384.png){: width="1000" height="450" }
_The log size changed from 4,098 KB to 16,384 KB before I closed the window_

---

## The allow rules

A domain controller needs more than LDAP and Kerberos. It also needs DNS, DHCP (because DC01 serves addresses to the lab), and the RPC endpoint mapper. I added the three predefined sets in the GPO editor:

1. **Active Directory Domain Services**, which includes LDAP, Global Catalog, Kerberos-related SAM/LSA ports, RPC and W32Time
2. **DNS Service**, UDP and TCP port 53 plus RPC
3. **DHCP Server**, DHCPv4 and DHCPv6 on UDP

Each predefined choice is one service, so the wizard runs once per service. Each rule set uses **Allow the connection**.

![New inbound rule, action step](/assets/images/Twentieth_blog/gpo-lab-firewall-new-rule-action-allow.png){: width="1000" height="600" }
_The last step of the wizard: Allow the connection_

To confirm the rules existed on DC01, I listed them from PowerShell:

```powershell
Get-NetFirewallRule -DisplayGroup "DNS Service" | Where-Object Enabled -eq True | Select DisplayName, Direction, Action
```

![AD DS rules allowed](/assets/images/Twentieth_blog/dc01-ad-ds-firewall-rules-allow.png){: width="1000" height="530" }
_Every enabled AD DS rule shows Allow_

![DNS and DHCP rules allowed](/assets/images/Twentieth_blog/dc01-dns-dhcp-firewall-rules-allow.png){: width="1000" height="450" }
_DNS and DHCP rules, all Allow_

---

## What went wrong: the block came first

My first version of the plan was wrong. I had set inbound to **Block** before adding the allow rules, and I told you to test before adding rules. With no allow rules, the domain controller drops the traffic that WS01 needs to join, sign in and read Group Policy.

WS01 could no longer sign in with a domain account. I changed inbound back to **Not configured**, ran `gpupdate /force`, and the tests passed again.

I did not prove the cause. The sign-in failure happened while the block was active, and I didn't check whether an account lockout (from the earlier wrong-password tests) also contributed. I'd rather say that plainly than claim a single cause.

**The order that works:** add the allow rules first, check them, then set inbound to Block.

---

## Testing the result

On WS01, after `gpupdate /force`, I tested the services the domain depends on:

```powershell
Test-NetConnection 10.0.10.10 -Port 389; Test-NetConnection 10.0.10.10 -Port 88
Resolve-DnsName dc01.lab.internal -Server 10.0.10.10
nltest /dsgetdc:lab.internal
```

![Firewall tests passing on WS01](/assets/images/Twentieth_blog/ws01-firewall-tests-passed.png){: width="1000" height="700" }
_LDAP (389) and Kerberos (88) succeed, DNS resolves dc01.lab.internal, and nltest finds DC01_

WS01 also signed in with a domain account. I didn't run `Get-NetFirewallProfile` on both machines, so I haven't checked the profile settings from the client side yet.

---

## What I did not prove

* **I tested the domain services, not every port.** The final state passes the domain tests, but I did not test each blocked port one by one.
* **Two predefined rules open more than the domain needs.** The AD DS set also enables inbound ICMP echo (ping) and NetBIOS name resolution (UDP). I turned NetBIOS off in the last post, so this partly undoes that choice. I haven't decided whether to remove these two rules.
* **The client-side firewall is only checked on WS01 through the domain tests.** A port scan from the attacker zone would show more.

---

## Outcome

* The firewall is on for every profile, with inbound blocked by default and outbound allowed.
* The domain services (LDAP, Kerberos, DNS, DHCP, SMB) are reachable through explicit allow rules.
* Dropped packets are logged, with a 16 MB log file.

## Next

Phase 1 has open items, listed in the series page. Phase 2 starts with Wazuh and Sigma, and the first step is to attack the domain and see what the logs show.
