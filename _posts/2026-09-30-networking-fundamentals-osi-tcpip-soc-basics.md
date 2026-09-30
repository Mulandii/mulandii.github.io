---
title: Security Foundations — Networks, the OSI Model, and How a SOC Works
author: baraka
date: 2026-09-30 10:00:00 +0300
description: My working notes on the fundamentals every defender needs — what a network is, the OSI and TCP/IP models, protocols, the shared responsibility model in the cloud, and how blue teams and SOC analyst tiers fit together.
image:
  path: /assets/images/Eighth_blog/osi_vs_tcpip.png
  alt: OSI model (7 layers) mapped against the TCP/IP model (4 layers).
categories: [ Security, Fundamentals ]
tags: [ Networking, OSI Model, TCP/IP, SOC, Blue Team, Cloud Security, Shared Responsibility, Mobile Security ]
---

## Overview

Before firewalls, SIEM rules, or incident response make sense, you need a solid picture of *how data actually moves* and *who is responsible for protecting it*. This post is my living set of study notes on those foundations. I update it as I learn, so expect it to grow.

What's covered:

- What a network is, and LAN vs WAN
- The OSI model, layer by layer
- The TCP/IP model and how it maps onto OSI
- Protocols
- Cloud security and the shared responsibility model
- Red, blue, and the SOC: who does what
- Device protection basics for mobile
- What I'm studying next

> This is a study log, not a complete reference. If you spot something wrong or outdated, I'd genuinely like to hear about it.
{: .prompt-info }

---

## Part 1: Networking Basics

### What is a network?

A **network** is a group of connected devices that can exchange data and share resources. Two vocabulary words come up constantly:

| Term | Meaning |
|------|---------|
| **Node** | Any individual device on the network (laptop, phone, printer, server) |
| **Link** | The pathway between nodes, either wired or wireless |

### LAN vs WAN

Networks are usually described by how far they stretch:

- **LAN (Local Area Network):** covers a small area such as a home, a classroom, or one office building.
- **WAN (Wide Area Network):** links networks across cities, countries, or continents. The internet is the biggest WAN.

Typical traits of a LAN:

| Trait | What it looks like |
|-------|--------------------|
| Scope | A single building or campus |
| Ownership | Usually one person or organization |
| Speed | High throughput between devices |
| Media | Ethernet cabling, Wi-Fi, or both |

### Why networks matter

Almost everything we rely on runs over a network: shared printers and files, messaging and video calls, access to databases from any device, and real-time collaboration across distances. It also means almost every attack path runs over one, which is why defenders study them first.

---

## Part 2: The OSI Model

The **Open Systems Interconnection (OSI) model** splits network communication into **seven layers**. It's a conceptual framework, not a protocol you can install. Its value is that it gives everyone a shared vocabulary: when someone says "that's a Layer 2 problem," you know roughly where to look.

Here is how I remember each layer, from the bottom up:

| # | Layer | What it does | Examples |
|---|-------|--------------|----------|
| 1 | **Physical** | Moves raw bits over a physical medium | Ethernet cables, hubs, repeaters |
| 2 | **Data Link** | Node-to-node delivery within a local network, with framing and error detection | Switches, bridges, MAC addresses |
| 3 | **Network** | Logical addressing and routing between networks | Routers, IP addresses |
| 4 | **Transport** | End-to-end delivery, segmentation, flow control | TCP, UDP |
| 5 | **Session** | Opens, maintains, and closes conversations between applications | Session protocols, APIs |
| 6 | **Presentation** | Translates data formats; handles encryption and compression | Encryption, compression |
| 7 | **Application** | The interface that network services expose to user-facing software | HTTP, FTP, SMTP, DNS |

> A classic mnemonic for the order from Layer 7 down to 1 is **"All People Seem To Need Data Processing."**
{: .prompt-tip }

### A few layers worth remembering

- **Layer 2** uses **MAC addresses** to identify devices on the same local network. Switches work here.
- **Layer 3** uses **IP addresses** and decides the path packets take across networks. Routers work here.
- **Layer 4** is where the reliability trade-off lives:
  - **TCP** is connection-oriented and recovers from lost data. Slower, dependable.
  - **UDP** is connectionless with no delivery guarantee. Faster, lighter.
- **Layer 7** is not "the application itself." It's the layer that gives applications access to network services, such as a browser speaking HTTP or a mail client using SMTP.

---

## Part 3: The TCP/IP Model

The **TCP/IP model** is the more practical, condensed version of OSI, and it's the one the real internet is built around. It has **four layers**:

| TCP/IP layer | Roughly equals (OSI) | Examples |
|--------------|----------------------|----------|
| **Application** | Application + Presentation + Session (7, 6, 5) | HTTP, FTP, SMTP, DNS |
| **Transport** | Transport (4) | TCP, UDP |
| **Internet** | Network (3) | IP, ICMP, routers |
| **Link** (Network Interface) | Data Link + Physical (2, 1) | NICs, Ethernet, Wi-Fi, switches |

![OSI vs TCP/IP](/assets/images/Eighth_blog/osi_vs_tcpip.png){: width="972" height="543" }
_The seven OSI layers on the left, mapped to the four TCP/IP layers on the right_

The takeaway: OSI is what you use to *reason and troubleshoot*, and TCP/IP is what's *actually running*.

---

## Part 4: Protocols

**Protocols** are agreed-upon rules for how data is formatted, sent, and processed so that different devices can understand each other. Some you'll meet on day one:

| Protocol | Role |
|----------|------|
| **TCP** | Reliable, ordered delivery |
| **UDP** | Fast delivery without guarantees |
| **FTP** | File transfer |
| **SMTP** | Sending email |
| **HTTP** | Web traffic |
| **DNS** | Turning domain names into IP addresses |

Each protocol's behavior is also its attack surface, which is why so much of security work is knowing what "normal" looks like for each one.

---

## Part 5: Cloud Security and Shared Responsibility

In the cloud, security is split between you and the provider. This is the **shared responsibility model**.

Think of a **safe deposit box at a bank**. The bank provides the building, the vault, the guards, and the cameras. But *you* hold the key and decide what goes inside. If you leave the key lying around, that's not the bank's failure.

| The provider secures | You secure |
|----------------------|------------|
| Physical data centers | Your data |
| Underlying infrastructure | Your applications |
| Core hardware and hypervisor | Access, identities, and configuration |

> The exact split shifts depending on the service model (IaaS, PaaS, SaaS), so always check where the line falls for the service you're using.
{: .prompt-warning }

Related topics I'm tracking under this heading: **disaster recovery** and **business continuity**, the plans that decide how quickly an organization can get back on its feet after an incident.

---

## Part 6: Red, Blue, and the SOC

### Threat actors and blue teams

A **threat actor** "team" is an organized group of people with specialized skills working together to carry out cyber attacks. The defenders on the other side are the **blue team**, whose work falls into four areas:

| Area | What it means |
|------|---------------|
| **Continuous monitoring** | Watching systems and networks for suspicious activity |
| **Implementing security controls** | Putting preventive and detective protections in place |
| **Incident response** | Containing, investigating, and recovering from incidents |
| **Collaboration and training** | Sharing knowledge and keeping skills sharp |

### The Security Operations Center (SOC)

The SOC is the blue team's home base: a function whose job is to watch over an organization's digital environment around the clock. Analysts are typically organized in tiers:

| Tier | Role |
|------|------|
| **Tier 1** | Initial alert triage and basic threat analysis |
| **Tier 2** | Complex incidents, deeper investigation, and mentoring Tier 1 |
| **Tier 3** | Incident response leads; the most critical issues and advanced threat analysis |

For me this is the most relevant part of these notes. Working through how a SOC runs is a big part of why I'm building toward a career in finance and banking security, where monitoring and incident response matter enormously.

---

## Part 7: Device Protection (Mobile)

Protecting a mobile device isn't one control. It's several layers, each covering a different weakness:

| Layer | Focus |
|-------|-------|
| **Device security** | The phone itself: lock screen, updates, encryption, remote wipe |
| **Data security** | What's stored and how it's protected |
| **Network security** | Wi-Fi, VPN, and how the device connects |
| **Application security** | What apps are installed and what permissions they hold |

I'll expand each of these into its own section as I work through mobile security.

---

## What's Next

My study roadmap, which future posts will pick up:

- **IDS / IPS**: detecting and blocking suspicious traffic
- **SIEM**: collecting and correlating logs for the SOC
- **Firewall configuration**: how rules are designed and tested
- **Cloud security**, **OPSEC**, **AppSec**, **NetSec**, and **MobSec** deep dives

---

## Key Takeaways

- **Know the layers.** OSI gives you the vocabulary, TCP/IP shows you the reality, and knowing both makes troubleshooting and analysis faster.
- **Know normal to spot abnormal.** Every protocol has expected behavior. Detection starts there.
- **Responsibility is shared.** In the cloud, the provider secures the platform but you still own your data and configuration.
- **Defense is a team sport.** A SOC works because tiers, tools, and training fit together.

---

## References

> Open Systems Interconnection model. <https://en.wikipedia.org/wiki/OSI_model>

> MAC address. <https://en.wikipedia.org/wiki/MAC_address>

> HTB Academy. <https://academy.hackthebox.com/>
