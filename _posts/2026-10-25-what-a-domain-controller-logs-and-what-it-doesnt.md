---
title: "What a Domain Controller Logs, and What It Doesn't"
author: baraka
date: 2026-10-25 23:30:00 +0300
description: Wrong passwords, a disabled account and a drifting clock, and what the Windows Security log on the domain controller and the workstation did and did not record.
image:
  path: /assets/images/Fifteenth_blog/dc01-failed-logons-4625.png
  alt: A PowerShell table of failed logon events on DC01, with logon types, status codes and source addresses.
categories: [ Active Directory, Homelab, Detection ]
tags: [ Active Directory, Event Logs, Kerberos, Audit Policy, Time Synchronisation, Hybrid Identity Detection Lab ]
---

## Overview

This is the seventh post in my **Hybrid Identity Detection Lab** project. In the [last post](/posts/creating-breaking-and-fixing-ad-objects/) I created, disabled and restored a test account by hand. While doing that I kept looking in the Security log for the failed logins, and the log kept surprising me.

This post is about what a fresh domain controller records and what it silently leaves out, because my Phase 2 detections can only find what is logged. It also covers a clock problem that turned out to matter for Kerberos.

All commands were run in an elevated PowerShell, on `DC01` unless a heading says `WS01`.

---

## A disabled account, and an event that isn't there

In the last post I disabled `tuser` and tried to sign in on `WS01` with the correct password. Windows said the account had been disabled. Then I read the log on DC01:

```powershell
Get-WinEvent -LogName Security -FilterXPath "*[System[(EventID=4725 or EventID=4722 or EventID=4768 or EventID=4771)]]" -MaxEvents 8 | Select TimeCreated, Id
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-events-after-disable.png){: width="952" height="292" }
_Event 4725, "an account was disabled", at 11:11:29 PM, above the earlier ticket requests_

Event **4725** records the disabling. The 4768 events below it are from 11:00 to 11:02 PM, before I disabled the account.

**What surprised me:** the newest event is the 4725. I tried to sign in after disabling the account, and the list has no failure event from that attempt. I did not check why at the time. The rest of this post is the result of checking: the domain controller records Kerberos successes but not failures. A detection that depends on failed logins would see nothing until the audit policy is changed.

## No account lockout



```powershell
Get-ADDefaultDomainPasswordPolicy | Select MinPasswordLength, ComplexityEnabled, LockoutThreshold, LockoutDuration
```

The policy shows a minimum password length of 7, complexity enabled, and `LockoutThreshold` **0**. A threshold of zero means an account is never locked, however many wrong passwords are typed. The lockout duration shows 30 minutes, but it only matters when a threshold is set. This is the first real hardening finding in the lab: anyone who can reach the domain controller can guess passwords without limit. I will set a lockout threshold in the Group Policy step.

---

## Wrong passwords on the sign-in screen

With a threshold of 0, I expected nothing to stop me. I typed a wrong password for `Lab\tuser` five times on `WS01`:

![Desktop View](/assets/images/Fifteenth_blog/ws01-login-wrong-password-delay.png){: width="939" height="328" }
_"Invalid credentials, delaying next attempt..." after repeated wrong passwords_

The sign-in screen slowed me down. This is not an account lockout. The domain's lockout threshold is 0, and the delay comes from the Windows sign-in screen on the workstation, not from the domain controller. I have not timed how long it lasts. It protects only against someone typing at this keyboard. An attacker guessing passwords over the network never sees this screen, which is why the lockout threshold still has to be set on the domain. I then went to the domain controller to look for the failures:

```powershell
Get-WinEvent -LogName Security -FilterXPath "*[System[(EventID=4771 or EventID=4625)]]" -MaxEvents 8 | Select TimeCreated, Id
auditpol /get /subcategory:"Kerberos Authentication Service"
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-failed-logon-events-auditpol.png){: width="891" height="567" }
_Only event 4625 appears, nothing newer than 11:00 PM, and the Kerberos Authentication Service audit setting is Success only_

* There is **no event 4771** at all. 4771 is the Kerberos pre-authentication failure, the event a wrong password produces on the domain controller.
* The newest 4625 is from 11:00:43 PM, which is before I disabled the account at 11:11 PM and long before the wrong-password test. So none of my five failed attempts left an event on the DC.
* The audit setting explains it: **Kerberos Authentication Service is set to Success only**. Failures are not recorded, so no 4771 can exist.

I then read the workstation's own log and the older 4625 events on the domain controller. The two machines tell different stories.

**On WS01**, the failed attempts are there. Six 4625 events from 11:33:16 PM to 11:33:47 PM, all with:

* Account Name `tuser`, Account Domain `LAB`
* Logon Type `2` (interactive, at the keyboard)
* Status `0xC000006D` and Sub Status `0xC000006A`, with the reason "Unknown user name or bad password"
* Subject `WS01$`, source address `127.0.0.1`, logon process `User32`

![Desktop View](/assets/images/Fifteenth_blog/ws01-failed-logons-4625.png){: width="944" height="336" }
_The workstation's own log: six failed interactive logons for tuser, each with the wrong-password sub status_

Sub Status `0xC000006A` is the wrong-password code. `0xC0000072` would be a disabled account. So the **workstation** recorded my wrong passwords, with the account name, while the **domain controller** recorded nothing. A defender who collects logs only from the domain controller would miss someone guessing passwords at a keyboard. The workstations need to send their logs too, which is what the agents in Phase 2 are for. The first five events are 5 seconds apart and the last is 11 seconds after the fifth. I did not work out why.

**On DC01**, the 4625 list also holds two kinds of older entries:

![Desktop View](/assets/images/Fifteenth_blog/dc01-failed-logons-4625.png){: width="899" height="335" }
_DC01's 4625 events: one wrong password at the console, and five network logons from WS01's address with status 0xc0000133_


* At 6:08:56 AM on 23 October, an interactive logon (type 2) failed on DC01 for `LAB\Administrator`, with the same sub status `0xC000006A`. That is a wrong password typed at the DC01 console. It has the same shape as the WS01 events, because both machines audit logon failures on themselves by default. Only the Kerberos failures on the domain controller are not recorded.
* Five 4625 events with **no account name**, logon type `3` (network), logon process `Kerberos`, status `0xC0000133` and the source address `10.0.10.100`, which is WS01. The reason text says only "An Error occured during Logon". They are dated 2:44:58 PM and twice at 3:29:42 PM on 21 October, 5:47:44 AM on 23 October and 11:00:43 PM on 25 October. That status is `STATUS_TIME_DIFFERENCE_AT_DC`: the clocks of the two computers were too far apart for Kerberos, which tolerates five minutes. A [Microsoft support blog post](https://blogs.msdn.microsoft.com/asiatech/2009/04/26/kerberos-authentication-failed-due-to-time-skew/) documents that mapping. It means that on 25 October at 11:00 PM, after I had fixed the time on the 23rd, WS01 and DC01 still disagreed by more than the limit. I don't know which of the two clocks was wrong. The 5:47:44 AM event is the failed attempt that shares its timestamp with the 4768 I couldn't explain earlier.
* **One thing I can't explain:** the three events dated 21 October are older than the domain join. VirtualBox's snapshot times, which come from the host clock, put the join in the early hours of 22 October, so a machine that wasn't yet a domain member should not have been attempting Kerberos logins against the domain controller. DC01's own clock was wrong at some point in this period, so those timestamps may not be reliable. I have recorded it and not drawn a conclusion.

To check what the Windows error text says, I ran the Win32 time-skew error code:

```powershell
net helpmsg 1398
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-net-helpmsg-1398.png){: width="945" height="79" }
_"There is a time and/or date difference between the client and server."_



---

## A detour: the wrong clock

During the exercise, DC01 showed the wrong date, time and time zone. `w32tm /resync` on both DC01 and WS01 reported that the time change was too big.

Kerberos rejects a login when two clocks differ by more than five minutes, and a wrong clock puts false times in the logs I'm studying. That makes it a real problem, not a cosmetic one.

DC01 had been set to take its time from the internet with:

```powershell
w32tm /config /manualpeerlist:"time.cloudflare.com,0x8 pool.ntp.org,0x8" /syncfromflags:manual /reliable:yes /update
```

A restart of DC01 fixed the clock. I don't know whether the setting or the restart did it, and I don't know why the clock drifted. Afterwards the Settings app showed the time server list, a recent synchronisation and the Nairobi time zone:

![Desktop View](/assets/images/Fifteenth_blog/dc01-time-settings-managed.png){: width="1044" height="778" }
_Synchronised against Cloudflare, with the controls greyed out: "some of these settings are hidden or managed by your organization"_

The controls to set the time automatically or manually are greyed out. I looked for the reason and checked which Group Policy applied:

```powershell
gpresult /scope computer /r
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-gpresult-computer.png){: width="976" height="732" }
_Only the two default policies apply. Local Group Policy is empty._

Only `Default Domain Controllers Policy` and `Default Domain Policy` are applied, and Local Group Policy is empty. So no custom policy causes the message. My best guess is that it is how Windows behaves on a domain controller, which I have not confirmed.

From the command line:

```powershell
w32tm /query /source
w32tm /query /status
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-w32tm-source-status.png){: width="988" height="589" }
_Source time.cloudflare.com, stratum 4, last successful sync at 5:38 AM, polling every 128 seconds_

The reference IP, `162.159.200.1`, belongs to Cloudflare, so NTP traffic really leaves the lab through the firewall, which also settles whether UDP port 123 works. On WS01:

```powershell
Get-TimeZone
w32tm /resync
w32tm /query /source
```

![Desktop View](/assets/images/Fifteenth_blog/ws01-timezone-resync.png){: width="951" height="405" }
_E. Africa Standard Time, and a resync that completes successfully_

The resync completed successfully, and the source on WS01 returned `DC01.lab.internal`. So time flows from the internet to DC01 to WS01, the way a domain should do it.

I also installed the VirtualBox Guest Additions on DC01, so I can paste long commands. On Arch the ISO comes from a separate package, `virtualbox-guest-iso`. The shared clipboard is set to bidirectional. A two-way clipboard is a path between my real machine and the lab, and the whole design is about keeping them apart. Host to Guest would be the safer setting. DC01 is the defender and holds nothing hostile, so I accept it for now, and I will switch it off on any machine that handles malware.

---

## Outcome

* A fresh domain controller records Kerberos **successes** and not **failures**. The audit setting says `Success` only, and there is no event 4771 anywhere in the log.
* The workstation records its own failed interactive logons, with the account name and the wrong-password code. The domain controller records nothing for them. Logs from the workstations are not optional.
* The domain has no account lockout, because the threshold is 0. The delay on the sign-in screen is the workstation's, and it does nothing against a network attack.
* WS01 and DC01 disagreed about the time again after I thought I had fixed it, and Kerberos refused the login with the time-skew status.

## Still to do

* **Fix the audit policy** so failures are recorded, in the Group Policy step: set Kerberos Authentication Service to Success and Failure, along with the related logon subcategories.
* **Set an account lockout threshold** in the same policy.
* **Measure WS01's clock offset** against DC01 (`w32tm /stripchart /computer:dc01.lab.internal /samples:3 /dataonly`), and find out why the two disagreed on 25 October and why the clock drifted in the first place.
* **Explain the 21 October time-skew events**, which are older than the domain join.

## What I would do differently

I would have checked the audit policy at the start, before trusting the log to tell me what happened. The absence of an event is only evidence if the event would have been recorded.

## Next

The script that creates the five OUs and 150 users, then the Group Policy that fixes what this post found: the audit policy, the lockout threshold, and the rest of the hardening list.
