---
title: Creating, Breaking and Fixing Active Directory Objects by Hand
author: baraka
date: 2026-10-25 23:00:00 +0300
description: One OU, one user and one group created by hand in PowerShell, then edited, moved, deleted, disabled and restored, with the errors I hit and the difference the AD Recycle Bin makes.
image:
  path: /assets/images/Fifteenth_blog/dc01-event-4768-tuser.png
  alt: PowerShell output of Windows event 4768, a Kerberos ticket request for the account tuser, with result code 0x0.
categories: [ Active Directory, Homelab, PowerShell ]
tags: [ Active Directory, PowerShell, Kerberos, Event Logs, Group Policy, Hybrid Identity Detection Lab ]
---

## Overview

This is the sixth post in my **Hybrid Identity Detection Lab** project. In the [last post](/posts/joining-a-windows-client-to-the-domain/) I joined a Windows 11 client to `lab.internal`. The next job in the plan is a script that builds five organisational units and 150 users. I decided not to write it first.

I did not want to paste a script I can't debug or explain, so I first ran the whole life of one test account by hand: **create, edit, move, delete, disable, enable, restore**. I read the Windows event each action left in the Security log, because my detections will use those events later.

This post is about the life of the account. A second post, [What a Domain Controller Logs, and What It Doesn't](/posts/what-a-domain-controller-logs-and-what-it-doesnt/), covers what I found when I went looking for the failed logins: a missing audit setting, no account lockout and a clock problem.

All commands were run on `DC01` as `LAB\Administrator`, in an elevated PowerShell.

---

## Step 1: Look before you change anything

```powershell
Get-ADDomain | Select DistinguishedName, NetBIOSName, DomainMode
Get-ADOrganizationalUnit -Filter * | Select Name, DistinguishedName
Get-ADUser -Filter * | Select Name, SamAccountName, Enabled
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-ad-baseline-before-ou.png){: width="866" height="369" }
_The starting point: one OU, Domain Controllers, and three built-in users_

* The domain is `DC=lab,DC=internal`, with NetBIOS name `LAB`. `Windows2016Domain` is the default functional level on Server 2022.
* The only OU is `Domain Controllers`.
* The users are `Administrator` (enabled), and `Guest` and `krbtgt` (both disabled).

Knowing the baseline means every later change is visible.

---

## Step 2: An OU, and the first mistake

An organisational unit (OU) is a folder inside the domain. Users and computers go in it so they can be managed together, for example by attaching Group Policy.

```powershell
New-ADOrganizationalUnit -Name "Lab_test" -Path "DC=lab,DC=internal"
```

The command printed nothing, which is how PowerShell reports success here. My check of it failed:

![Desktop View](/assets/images/Fifteenth_blog/dc01-select-comma-error.png){: width="997" height="196" }
_"A positional parameter cannot be found that accepts argument 'System.Object[]'"_

The cause was a missing comma:

```
| select Name DistinguishedName, ProtectedFromAccidentalDeletion
```

`Select-Object` takes property names as one comma-separated list. Without the comma, `DistinguishedName, ProtectedFromAccidentalDeletion` becomes a second argument with nowhere to go. "Positional parameter cannot be found" usually means a missing comma.

---

## Step 3: A user, and a password the domain refused

```powershell
New-ADUser -Name "Test-User" -GivenName Test -Surname User -SamAccountName tuser `
  -UserPrincipalName tuser@Lab.internal -Path "OU=Lab_test,DC=lab,DC=internal" `
  -AccountPassword (Read-Host -AsSecureString "Password") -Enabled $true
```

`Read-Host -AsSecureString` asks for the password with hidden input, so it never appears in the command or the shell history.

![Desktop View](/assets/images/Fifteenth_blog/dc01-new-aduser-password-error.png){: width="1079" height="676" }
_The first attempt, the second attempt, and a lookup with misspelled property names_

Three separate things happened here.

**1. The password was refused.** `The password does not meet the length, complexity, or history requirement of the domain.` That message is generic, and I can't say which rule my hidden password broke.

**2. The failed command still created the user.** `New-ADUser` creates the account first and sets the password afterwards. When the password is refused, the account is left behind, disabled and without a password. The last lines of the screenshot show `Enabled : False`.

**3. The second attempt said "The specified account already exists".** That was the leftover from the first attempt. The second attempt never reached the password check.

The blank `SamAccountNmae` and `UserPrincipalNmae` fields are typos in my command. `Select-Object` prints an empty value for a property that doesn't exist, so a blank field means check the spelling.

### The fix

I didn't recreate the account. I set the password on the one that existed and enabled it:

```powershell
Set-ADAccountPassword -Identity tuser -Reset -NewPassword (Read-Host -AsSecureString "New password")
Enable-ADAccount -Identity tuser
Get-ADUser tuser | Select Name, SamAccountName, UserPrincipalName, DistinguishedName, Enabled
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-tuser-fixed-enabled.png){: width="1003" height="512" }
_Before: Enabled False. After the reset and Enable-ADAccount: Enabled True_

---

## Step 4: A group

```powershell
New-ADGroup -Name "GG-Test" -GroupScope Global -GroupCategory Security -Path "OU=Lab_test,DC=lab,DC=internal"
Add-ADGroupMember -Identity "GG-Test" -Members tuser
Get-ADGroupMember "GG-Test" | Select Name, SamAccountName
Get-ADUser tuser -Properties MemberOf | Select Name, MemberOf
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-group-created-member-added.png){: width="1012" height="311" }
_The group holds the user, and the user's MemberOf lists the group_

`-GroupScope Global` is the standard type for a department's people, `-GroupCategory Security` means it can be given permissions (a Distribution group only works for email), and `GG-` is my naming convention for Global Group. Permissions go to groups, not people, so when someone changes department only their groups change.

---

## Step 5: Logging in as the new user

On `WS01` I signed in as `Lab\tuser`, a non-admin domain account, for the first time.

```powershell
whoami
whoami /groups | Select-String "GG-Test|Domain Users"
```

![Desktop View](/assets/images/Fifteenth_blog/ws01-first-domain-user-login.png){: width="1608" height="261" }
_whoami returns lab\tuser, and LAB\GG-Test is in the login token_

`LAB\GG-Test` is in the token with a real SID, so the OU, user and group chain works end to end.

### An unresolved question: where is Domain Users?

I expected `LAB\Domain Users` in that list too, and it isn't there. The full `whoami /groups` output has no entry for it at all. Active Directory says it should be there:

```powershell
Get-ADUser tuser -Properties PrimaryGroup, PrimaryGroupID, MemberOf | Select Name, PrimaryGroup, PrimaryGroupID, MemberOf
Get-ADUser Administrator -Properties PrimaryGroup, PrimaryGroupID | Select Name, PrimaryGroup, PrimaryGroupID
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-primarygroup-and-tuser-events.png){: width="995" height="525" }
_Both accounts have Domain Users as the primary group, ID 513_

Both accounts show `CN=Domain Users` with `PrimaryGroupID 513`. The primary group is stored in its own field, so it doesn't appear in `MemberOf`. The account looks correct in the directory and the login token still lacks the group.

**I don't know why.** My plan is to recreate `tuser` cleanly and run `whoami /groups` again.

---

## Reading a Kerberos event

On `DC01` I read the ticket request for `tuser`, filtering by account name:

```powershell
Get-WinEvent -LogName Security -FilterXPath "*[System[EventID=4768] and EventData[Data[@Name='TargetUserName']='tuser']]" -MaxEvents 1 | Format-List Message
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-event-4768-tuser.png){: width="1089" height="687" }
_Event 4768: a Kerberos ticket-granting ticket was requested for tuser_

| Field | Value | Meaning |
|---|---|---|
| Account Name | `tuser` | Who asked for the ticket. |
| Service Name | `krbtgt` | A TGT request: the first ticket, which proves the login before tickets for specific services. |
| Client Address | `::ffff:10.0.10.100` | WS01. The `::ffff:` is just the IPv4 address written in IPv6 style. |
| Result Code | `0x0` | Success. |
| Ticket Encryption Type | `0x12` | AES-256. |
| Pre-Authentication Type | `2` | The client proved its identity with an encrypted timestamp, which is how a normal password login works. |

These are the fields a detection reads. Pre-authentication type 0 would mean the account allows AS-REP roasting, and encryption type `0x17` is RC4, a weaker cipher that is unusual in a lab that normally shows `0x12`. A non-zero result code means failure.

### Filter before you attribute

My first query only showed time and event ID:

![Desktop View](/assets/images/Fifteenth_blog/dc01-logon-events-4768-4624-list.png){: width="1008" height="479" }
_Twenty events with no account names: many belong to computers and services, not to a person_

I assumed the 4768 at 5:47:44 AM was `tuser`'s, but filtering on the account name showed it wasn't. Filter by `TargetUserName` before attributing an event to anyone.

---

## Edit and move

```powershell
Set-ADUser tuser -Department "IT" -Title "Test Engineer" -Description "Manual exercise account"
New-ADOrganizationalUnit -Name "Lab_moved" -Path "DC=lab,DC=internal"
Move-ADObject -Identity (Get-ADUser tuser).DistinguishedName -TargetPath "OU=Lab_moved,DC=lab,DC=internal"
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-edit-and-move-user.png){: width="964" height="383" }
_Three attributes set, then the user moved from Lab_test to Lab_moved_

The DN changed from `OU=Lab_test` to `OU=Lab_moved`, because it includes the OU. The SID and login name stay the same. Group Policy attaches to OUs, so moving an account changes which policies it gets. The group `GG-Test` did not move with it.

---

## Deleting an OU: two locks

I moved the user out first, so `Lab_test` held only the group. Then I tried to delete it:

```powershell
Remove-ADOrganizationalUnit -Identity "OU=Lab_test,DC=lab,DC=internal" -Confirm:$false
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-ou-delete-access-denied.png){: width="981" height="227" }
_"Access is denied", even as a domain administrator_

The first lock is **protection from accidental deletion**. Windows adds a hidden permission that denies deletion to everyone, administrators included, until the flag is turned off. The message says "access denied", not "protected", which is misleading. I turned it off and tried again:

```powershell
Set-ADOrganizationalUnit -Identity "OU=Lab_test,DC=lab,DC=internal" -ProtectedFromAccidentalDeletion $false
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-ou-delete-child-objects.png){: width="977" height="266" }
_Error 8332: the operation can only be performed on a leaf object_

The second lock is that the OU wasn't empty. A leaf object is one with nothing inside, and the OU still held the group. The `-Recursive` switch deletes the OU and everything in it:

```powershell
Remove-ADOrganizationalUnit -Identity "OU=Lab_test,DC=lab,DC=internal" -Recursive -Confirm:$false
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-ou-delete-recursive-confirm.png){: width="979" height="202" }
_Lab_test is gone, Lab_moved remains, and the group query returns nothing_

Two short steps separate an administrator from a deleted department, and that is why every OU in my script will keep its default protection.

---

## Disabling an account

```powershell
Disable-ADAccount -Identity tuser
Get-ADUser tuser | Select Name, Enabled
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-disable-tuser.png){: width="972" height="406" }
_Enabled False_

Then I tried to sign in on `WS01` as `Lab\tuser` with the correct password:

![Desktop View](/assets/images/Fifteenth_blog/ws01-login-account-disabled.png){: width="925" height="874" }
_"Your account has been disabled. Please see your system administrator."_

The message tells whoever types the password that the account exists and is disabled. On DC01 I read the log:

```powershell
Get-WinEvent -LogName Security -FilterXPath "*[System[(EventID=4725 or EventID=4722 or EventID=4768 or EventID=4771)]]" -MaxEvents 8 | Select TimeCreated, Id
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-events-after-disable.png){: width="952" height="292" }
_Event 4725, "an account was disabled", at 11:11:29 PM, above the earlier ticket requests_

Event **4725** records the disabling. The 4768 events below it are from 11:00 to 11:02 PM, before I disabled the account.

**One thing missing:** I tried to sign in after disabling the account, and I expected a failure event for that attempt on DC01. The list has none. I explain why in the [next post](/posts/what-a-domain-controller-logs-and-what-it-doesnt/).

### Enabling it again

```powershell
Enable-ADAccount -Identity tuser
Get-ADUser tuser | Select Name, Enabled
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-enable-tuser.png){: width="928" height="165" }
_Enabled True_

I signed in again as `tuser` and checked the log for event **4722**, "an account was enabled":

![Desktop View](/assets/images/Fifteenth_blog/dc01-event-4722-enable.png){: width="938" height="217" }
_The newest 4722 is from the enable above, at 11:17:51 PM_

There are three older 4722 events, all from 21 October. I have not read them, so I don't know which accounts they belong to. I also enabled `tuser` once before, on a day when DC01's clock may already have been wrong (see the [next post](/posts/what-a-domain-controller-logs-and-what-it-doesnt/)), and none of the entries is dated that day. One of the older entries could be that event with a wrong timestamp. That is a good reminder of what a forensic investigator has to check first: whether the clock was right.

---

## Before deleting a user: is the Recycle Bin on?

The last exercise is deleting `tuser` and trying to get it back. What survives a delete depends on the **AD Recycle Bin**. With it off, a deleted object becomes a stripped-down "tombstone". With it on, the object is kept intact and can be restored with all its attributes. I checked:

```powershell
Get-ADOptionalFeature -Filter 'Name -eq "Recycle Bin Feature"' | Select Name, EnabledScopes
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-recycle-bin-disabled.png){: width="919" height="222" }
_EnabledScopes is empty, so the Recycle Bin is off_

It is off, which is the default on a new domain. Enabling it cannot be undone for the forest, so I am leaving it off for the experiment to see what a recovery looks like without it, and I will enable it afterwards as a hardening step.

---

## Deleting a user and trying to get it back

First I gave `tuser` a group, so I could see what a delete does to membership, and I wrote down everything the account had:

```powershell
New-ADGroup -Name "GG-Recover" -GroupScope Global -GroupCategory Security -Path "OU=Lab_moved,DC=lab,DC=internal"
Add-ADGroupMember -Identity "GG-Recover" -Members tuser
Get-ADUser tuser -Properties * | Select Name, SID, ObjectGUID, Department, Title, MemberOf
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-tuser-before-delete.png){: width="1064" height="336" }
_The account before the delete: SID ending 1104, department IT, title Test Engineer, member of GG-Recover_

I took a snapshot of DC01 first, then deleted the account:

```powershell
Remove-ADUser -Identity tuser -Confirm:$false
Get-ADUser tuser
```

`Get-ADUser` now fails with "Cannot find an object with identity". The account is gone from the directory, but a deleted object is not erased at once. With the Recycle Bin off, it becomes a tombstone in a hidden container, and I looked at it there:

```powershell
Get-ADObject -Filter 'isDeleted -eq $true -and samAccountName -eq "tuser"' -IncludeDeletedObjects -Properties * | Select Name, SamAccountName, LastKnownParent, ObjectSID, MemberOf, Department, Title
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-tuser-tombstone.png){: width="986" height="553" }
_The tombstone keeps the SID and the old location, and nothing else_

* The **name is rewritten** to `Test-User` followed by `DEL:` and the account's original GUID.
* `SamAccountName`, `ObjectSID` (still ending in `1104`) and `LastKnownParent` (`OU=Lab_moved`) survive.
* **`MemberOf`, `Department` and `Title` are empty.** The group memberships and the attributes are gone.

That matched what I expected. What I did not expect was what happened when I tried to restore it:

```powershell
Get-ADObject -Filter 'isDeleted -eq $true -and samAccountName -eq "tuser"' -IncludeDeletedObjects | Restore-ADObject
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-tuser-restore-failed.png){: width="957" height="424" }
_Restore-ADObject: "Illegal modify operation. Some aspect of the modification is not permitted"; the user is still not found, and GG-Recover is empty_

The restore **failed** with `Illegal modify operation. Some aspect of the modification is not permitted`. `Get-ADUser tuser` still can't find the account, and `Get-ADGroupMember GG-Recover` prints nothing, so the group lost its member.

I haven't established the exact reason for this error. What I found while looking is that the native restore commands are built around the Recycle Bin, and that [without it a deleted user is generally treated as past recovery](https://netwrix.com/en/resources/blog/active-directory-object-recovery-recycle-bin/). The same source says that enabling the Recycle Bin afterwards does not bring tombstones back. I have not tested that, so I will not rely on it. The practical lesson stands whichever way the error is explained: **the Recycle Bin has to be turned on before the deletion, and a restore from backup is the fallback.** In my lab the fallback is the snapshot.

---

## Turning the Recycle Bin on, and starting again with a clean account

Taking the snapshot first was deliberate: enabling the Recycle Bin cannot be undone, and a snapshot is the only way back if I regret it. Then I enabled it and created a new `tuser`, typing the password carefully so the first attempt would work:

```powershell
Enable-ADOptionalFeature -Identity 'Recycle Bin Feature' -Scope ForestOrConfigurationSet -Target 'lab.internal' -Confirm:$false
New-ADUser -Name "Test-User" -GivenName Test -Surname User -SamAccountName tuser -UserPrincipalName tuser@lab.internal -Path "OU=Lab_moved,DC=lab,DC=internal" -AccountPassword (Read-Host -AsSecureString "Password") -Enabled $true -Department "IT" -Title "Test Engineer"
Add-ADGroupMember -Identity "GG-Recover" -Members tuser
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-recycle-bin-enabled-new-tuser.png){: width="1044" height="475" }
_The irreversible warning, the feature now listing its scopes, and the new account with SID ending 1107_

* Windows warns that enabling the feature "is an irreversible action" and that I "will not be able to disable" it. `EnabledScopes` is no longer empty.
* The new account is called `tuser` again, but its SID ends in **1107**, where the deleted one ended in 1104. Active Directory identifies an account by its SID, not its name. The numbers also show the order things were created: 1104 the first `tuser`, 1105 `GG-Test`, 1106 `GG-Recover`, 1107 this one. To Windows, this is a different account with the same name, so permissions given to the old SID don't apply to it. Its first sign-in on `WS01` also builds a new profile.

### The `Domain Users` question again

To test my guess about the failed command, I checked the clean account, which was created correctly on the first attempt:

```powershell
whoami /groups
```

![Desktop View](/assets/images/Fifteenth_blog/ws01-tuser-clean-whoami-groups.png){: width="1458" height="455" }
_A clean account, and `LAB\Domain Users` is still not in the login token; only LAB\GG-Recover is_

`LAB\Domain Users` is **still missing**, so the failed first attempt was not the cause. `GG-Recover` shows up (SID ending 1106), but `Domain Users` doesn't, and I haven't found out why.

To see the directory's side of it, I asked the domain controller from `WS01`:

```powershell
net user tuser /domain
```

![Desktop View](/assets/images/Fifteenth_blog/ws01-net-user-tuser-domain.png){: width="1123" height="600" }
_The domain controller lists the account's groups as GG-Recover and Domain Users_

The last line shows `*GG-Recover  *Domain Users`: the **directory has the membership**, and only the login token on the workstation lacks it.

---

## The same delete, with the Recycle Bin on

With the Recycle Bin enabled, I repeated the exercise with the new `tuser`: delete it, look at what is left, and restore it.

```powershell
Remove-ADUser -Identity tuser -Confirm:$false
Get-ADObject -Filter 'isDeleted -eq $true -and samAccountName -eq "tuser"' -IncludeDeletedObjects -Properties * | Sort-Object whenChanged -Descending | Select-Object -First 1 | Select Name, SamAccountName, LastKnownParent, ObjectSID, MemberOf, Department, Title
```

The `Sort-Object … Select-Object -First 1` part picks the newest deleted object called `tuser`, in case an older tombstone is still around.

![Desktop View](/assets/images/Fifteenth_blog/dc01-tuser-tombstone-recyclebin.png){: width="1068" height="414" }
_With the Recycle Bin on, the deleted object still has its department, title and group_

This time the deleted object keeps **everything**: `Department IT`, `Title Test Engineer`, and `MemberOf` still lists `GG-Recover`. The name is still rewritten with `DEL:` and a GUID, but nothing has been stripped. Then I restored it:

```powershell
Get-ADObject -Filter 'isDeleted -eq $true -and samAccountName -eq "tuser"' -IncludeDeletedObjects -Properties whenChanged | Sort-Object whenChanged -Descending | Select-Object -First 1 | Restore-ADObject
Get-ADUser tuser -Properties * | Select Name, SID, Enabled, Department, Title, MemberOf
Get-ADGroupMember "GG-Recover" | Select Name
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-tuser-restored.png){: width="1047" height="443" }
_Restored: the same SID, enabled, with department, title and group membership, and GG-Recover has its member back_

The restore **worked**. The SID is the same `...-1107`, the account is enabled, the department, title and group are all back, and `Get-ADGroupMember GG-Recover` lists `Test-User` again.

### The two runs side by side

| | Recycle Bin off | Recycle Bin on |
|---|---|---|
| Deleted object keeps | SID, old location | SID, old location, department, title, group membership |
| `Restore-ADObject` | Failed: "Illegal modify operation" | Worked |
| After the delete and restore | The group lost its member, and the account was not found | The account is back with the same SID, and the group has its member |

The reason this matters in practice is that a person or an attacker who deletes accounts can be undone in seconds with the bin on, and not at all without it. It also leaves a trail: event 4726 records a deletion. The Recycle Bin goes on my list for the hardened baseline.

I then signed in on `WS01` as the restored `tuser`, and **the old password still worked**. The restore brought back the password along with the rest of the account.

---

## Cleaning up

The test objects were throwaway, and the script I write next should start from a clean directory. I removed the user, the group and the OU:

```powershell
Remove-ADUser -Identity tuser -Confirm:$false
Remove-ADGroup -Identity GG-Recover -Confirm:$false
Set-ADOrganizationalUnit -Identity "OU=Lab_moved,DC=lab,DC=internal" -ProtectedFromAccidentalDeletion $false
Remove-ADOrganizationalUnit -Identity "OU=Lab_moved,DC=lab,DC=internal" -Confirm:$false
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-cleanup-commands.png){: width="1001" height="154" }
_The same two locks as before: the protection flag first, then the delete_

The OU needed its protection removed again before it could be deleted, which is the first lock from earlier. I did not need `-Recursive` this time, because I had already removed what was inside it. With the Recycle Bin on, these deletions can be undone.

Then I checked that the directory was back at its baseline:

```powershell
Get-ADOrganizationalUnit -Filter * | Select Name
Get-ADUser -Filter * | Select Name, Enabled
Get-ADGroup -Filter 'Name -like "GG-*"' | Select Name
```

![Desktop View](/assets/images/Fifteenth_blog/dc01-directory-clean-after-exercise.png){: width="1039" height="413" }
_Back to the baseline: only Domain Controllers, the three built-in users, and no test groups_

It matches the starting screenshot: one OU (`Domain Controllers`), the users `Administrator`, `Guest` and `krbtgt`, and no `GG-` groups. This is the point I will snapshot as the starting state for the script.

---

## Outcome

* I created, edited, moved, deleted, disabled, enabled and restored objects by hand, and read the Windows event each one left behind.
* I hit and fixed six errors: a missing comma, a refused password, a leftover account, misspelled property names, and two deletion locks.
* With the Recycle Bin off, a deleted user could not be restored and its group lost the member. With it on, the same restore brought back the SID, the attributes, the group membership and the password.

## Still to do

* **Find out why `Domain Users` is missing from the login token**, although Active Directory lists the membership. Compare Administrator's token on DC01 and on WS01.
* **Read the three older 4722 events** on DC01 to find out which accounts they belong to.

## What I would do differently

I would read my own commands once before pressing Enter. Two of the six errors, the missing comma and the misspelled properties, were typing mistakes, and both were visible in the command.

## Next

The script that creates the five OUs and 150 users from a CSV. The Group Policy step comes after it and sets the lockout threshold and the audit policy that the next post says are missing.
