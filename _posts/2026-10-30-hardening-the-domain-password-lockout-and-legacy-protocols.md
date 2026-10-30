---
title: "Hardening the Domain: Password Policy, Lockout and Legacy Protocols"
author: baraka
date: 2026-10-30 05:10:00 +0300
description: Setting the domain password and lockout policy, testing the lockout in the event log, and turning off LLMNR, NetBIOS and SMBv1. Each change, why it matters, and what I did not prove.
image:
  path: /assets/images/Nineteenth_blog/lockout-policy-set.png
  alt: Default Domain Policy showing an account lockout threshold of 5, a 30-minute duration and a 30-minute reset.
categories: [ Active Directory, Homelab, Security Hardening ]
tags: [ Active Directory, Group Policy, Password Policy, Account Lockout, LLMNR, NetBIOS, SMBv1, Hybrid Identity Detection Lab ]
---

## Overview

This is the tenth post in my **Hybrid Identity Detection Lab** project. The [last post](/posts/audit-policy-by-group-policy/) ended with audit policy recording failed Kerberos logons. This post is the first half of hardening the domain: the password and lockout rules, then three legacy protocols that attackers use to get credentials. The firewall rules are the last item in Phase 1 and come in a later post.

The weak starting state is kept in the snapshot `phase1-dc01-150-users`. The hardened state is saved as `phase1-dc01-name-resolution-hardened` and `phase1-ws01-name-resolution-hardened`.

The order I followed:

1. Set the password and lockout policy in the Default Domain Policy
2. Test the lockout and read the event
3. Turn off LLMNR, NetBIOS and SMBv1
4. Verify each change on both machines

---

## Part 1: Password and lockout policy

### Where the policy belongs

Password and lockout rules for domain accounts only apply when they are set in a GPO linked to the domain. My first attempt was in `LAB-DC-Audit`, which is linked to the Domain Controllers OU. Windows ignores account policies in that GPO for domain accounts, so the setting did nothing. I set the value back to Not Defined there. The correct place is **Default Domain Policy**, under Computer Configuration → Policies → Windows Settings → Security Settings → Account Policies.

### The values

| Setting | Value | Why |
|---|---|---|
| Enforce password history | 24 | Stops users cycling back to a recent password. |
| Maximum password age | 365 days | A lab choice. NIST advises against frequent forced changes, and CIS allows a long limit. |
| Minimum password age | 1 day | Stops a user changing the password many times in one day to get back to an old one. |
| Minimum password length | 14 | CIS recommends 14 or more. Longer passwords slow down offline guessing. |
| Complexity | Enabled | Rejects simple passwords. |
| Reversible encryption | Disabled | Reversible storage is close to storing plain text. |
| Lockout threshold | 5 invalid attempts | Slows guessing without locking users out for small typos. |
| Lockout duration | 30 minutes | Long enough to slow an attacker. |
| Reset counter after | 30 minutes | Failed attempts older than this stop counting. |

Kerberos policy stays at its defaults. I did not change ticket lifetimes, because I'll need the default values for the forensics phase.

![Default Domain Policy password settings](/assets/images/Nineteenth_blog/password-policy-set.png){: width="1000" height="350" }
_The password settings as they now apply to the whole domain_

### Checking the values

After `gpupdate /force` on DC01, I read the effective values from PowerShell:

```powershell
Get-ADDefaultDomainPasswordPolicy | Select MinPasswordLength, PasswordHistoryCount, LockoutThreshold, LockoutDuration, LockoutObservationWindow
```

![Effective values](/assets/images/Nineteenth_blog/effective-policy-values.png){: width="1000" height="200" }
_14, 24, 5, 30 minutes and 30 minutes, matching the GPO_

The screenshot shows what the domain enforces, not just what the GPO editor displays. That distinction is why I ran the command.

### Testing the lockout

I locked out a test account from WS01 by entering a wrong password five times at the sign-in screen. The sixth attempt showed the lockout message.

![Locked-out sign-in screen](/assets/images/Nineteenth_blog/ws01-login-account-locked-out.png){: width="1000" height="530" }
_WS01 says the account is locked out. The lockout itself is recorded on the domain controller_

The lockout is recorded on DC01, because DC01 is the machine that enforces it. The event is **4740, A user account was locked out**:

![Event 4740 details](/assets/images/Nineteenth_blog/dc01-event-4740-lockout.png){: width="1000" height="560" }
_Subject DC01$. Account That Was Locked Out LAB\\elijah.salim. Caller Computer Name WS01_

Three fields matter for detection later:

* **Subject** shows that the domain controller wrote the event.
* **Account That Was Locked Out** names the target.
* **Caller Computer Name** shows where the attempts came from.

Once the test is done, unlock the account with `Unlock-ADAccount -Identity elijah.salim` (or wait 30 minutes).

**Note:** `Get-WinEvent` returned two 4740 events from this session. I only inspected the one from the test, so I have not explained the second one.

---

## Part 2: Legacy protocols

These three protocols are old, and attackers use them to capture or relay credentials. Turning them off removes the attack surface before the detection work starts.

### LLMNR

**What it does:** when DNS can't resolve a name, Windows broadcasts a question on the local subnet asking who owns it.

**Why it's a risk:** any machine on the subnet can answer, so an attacker can claim to be the server and receive a login attempt. Tools such as Responder do this to capture password hashes.

**The change:** a new GPO, `LAB-Hardening`, linked to the domain. Computer Configuration → Administrative Templates → Network → DNS Client → **Turn off multicast name resolution: Enabled**.

![LLMNR policy setting](/assets/images/Nineteenth_blog/gpo-lab-hardening-llmnr-enabled.png){: width="1000" height="450" }
_The policy sets EnableMulticast to 0 for every computer in the domain_

The registry value confirms it applied on DC01:

![EnableMulticast 0 on DC01](/assets/images/Nineteenth_blog/dc01-llmnr-enablemulticast-0.png){: width="1000" height="330" }
_HKLM\Software\Policies\Microsoft\Windows NT\DNSClient, EnableMulticast = 0_

### NetBIOS over TCP/IP

**What it does:** an older name service that also answers broadcast queries.

**Why it's a risk:** the same kind of spoofing as LLMNR, through another protocol.

**The change:** Group Policy can't set this directly, so I disabled it on each adapter:

```powershell
Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=true" | Invoke-CimMethod -MethodName SetTcpipNetbios -Arguments @{TcpipNetbiosOptions=2}
```

`2` means disabled. The method returned `0`, which means success, and this check confirms the value on each adapter:

```powershell
Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=true" | Select Description, TcpipNetbiosOptions
```

![NetBIOS disabled on WS01](/assets/images/Nineteenth_blog/ws01-netbios-disabled-adapter.png){: width="1000" height="220" }
_TcpipNetbiosOptions 2 on WS01's adapter_

This is a setting per adapter, so it has to be re-checked if a machine gets a new adapter.

### SMBv1

**What it does:** the first version of the Windows file-sharing protocol.

**Why it's a risk:** it has known vulnerabilities, including the ones used by the EternalBlue exploit family. There's no reason for a domain controller or client to use it.

**The change:** on DC01, the server setting was already off, and on WS01 the optional feature was disabled:

```powershell
Get-SmbServerConfiguration | Select EnableSMB1Protocol
Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol | Select FeatureName, State
```

![SMBv1 off on both machines](/assets/images/Nineteenth_blog/dc01-smb1-off-netbios-disabled.png){: width="1000" height="350" }
_DC01: EnableSMB1Protocol False, and the NetBIOS command returned 0_

![WS01 SMBv1 disabled and gpupdate](/assets/images/Nineteenth_blog/ws01-smb1-disabled-netbios-gpupdate.png){: width="1000" height="600" }
_WS01: SMB1Protocol State Disabled, followed by gpupdate /force completing_

### Restart before checking

Before running these checks, restart each machine. A setting that failed earlier can still show the old value, and a restart gives a clean result. The `gpupdate /force` output tells you policy was applied, but it doesn't guarantee that every setting took effect.

**A note on whoami:** on WS01 I ran the policy update as the local account `ws01\vboxuser`, not the domain admin. Computer settings apply whichever user runs `gpupdate`, so the result is valid. For domain tasks, run as `LAB\Administrator`.

---

## What I did not prove

* **LLMNR and NetBIOS are off, but I haven't tested an attack.** Phase 2 will try a poisoning attack before and after, so I can say whether it stopped working.
* **The lockout test is one account, from one machine.** I haven't checked what happens with several machines or the observation window.
* **Password policy doesn't affect existing passwords.** Users keep their current passwords until they change them. The generated passwords are 16 characters, so they already comply.
* **The second 4740 event is unexplained.** I'll look at it again during Phase 2.

---

## Outcome

* The password and lockout rules are set in the domain policy, and the domain enforces them.
* A lockout is recorded in the Security log on the domain controller, with the target account and the source machine.
* LLMNR, NetBIOS and SMBv1 are off on both machines, and each check is recorded.
* Snapshots exist on both machines: `phase1-dc01-name-resolution-hardened` and `phase1-ws01-name-resolution-hardened`.

## Next

The Windows Firewall policy: the last Phase 1 item, and the rules that will decide which traffic reaches DC01.
