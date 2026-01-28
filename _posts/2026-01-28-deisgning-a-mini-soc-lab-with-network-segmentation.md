---
title: Designing a Simple SOC Network My First Home Lab Setup
author: baraka
date: 2026-01-28 14:59:33 +0300
description: A detailed guide on designing a mini SOC lab with network segmentation for enhanced security and monitoring
image:
  path: /assets/images/Third_blog/vms.png
  lqip: data:image/webp;base64,UklGRpoAAABXRUJQVlA4WAoAAAAQAAAADwAABwAAQUxQSDIAAAARL0AmbZurmr57yyIiqE8oiG0bejIYEQTgqiDA9vqnsUSI6H+oAERp2HZ65qP/VIAWAFZQOCBCAAAA8AEAnQEqEAAIAAVAfCWkAALp8sF8rgRgAP7o9FDvMCkMde9PK7euH5M1m6VWoDXf2FkP3BqV0ZYbO6NA/VFIAAAA
  alt: The login page of the clinic CMS.
categories: [ Networking, Homelab,Virtualbox]
tags: [ Networking, SOC, NDR,EDR ]
---
## Introduction

When I started building a home **Security Operations Center (SOC) lab**, I assumed the difficult part would be installing detection tools.

Instead, the biggest challenge was **networking**.

This post documents how I built and configured the **network foundation** of a SOC lab using:

* a **Windows endpoint (EDR)**
* a **Linux network sensor (NDR)**

This lab is a walkthrough of what I did.

---

## Lab Overview

This lab uses:

* **VirtualBox** for virtualization
* **Windows 10** as the endpoint (EDR)
* **Ubuntu Server** as the network sensor (NDR)

Each virtual machine uses **three network adapters**, connected to **three different traffic planes**:

1. Internet & management
2. Internal monitored traffic
3. Secure admin access from the host

Understanding this separation is the key to understanding SOC networking.

![Desktop View](/assets/images/Third_blog/vms.png){: width="972" height="589" }
_Windows EDR VM and Ubuntu NDR VM_

---

## Phase 1: VirtualBox Network Configuration (Host Level)

Before creating or configuring any virtual machines, the **networks themselves must exist**.

In this lab, only **two networks are created manually**:

* a **NAT Network**
* a **Host-Only Network**

A third network, called an **Internal Network**, is created automatically by VirtualBox when selected later.

---

### Step 1.1: Creating the NAT Network (Internet & Management)

The **NAT Network** allows:

* internet access
* software updates
* controlled communication between VMs

#### Steps

1. Open **VirtualBox**
2. Go to **File → Tools → Network Manager**
3. Open the **NAT Networks** tab
4. Click **Create**

Configure:

```
Name: SOC_Network
IPv4 Prefix: 10.0.50.0/24
DHCP: Disabled
IPv6: Disabled
```

![Desktop View](/assets/images/Third_blog/NATconfiguration.png){: width="972" height="589" }
_NAT configuration in Virtualbox_

#### Why this matters

Using a NAT Network:

* keeps VMs isolated from the physical LAN
* avoids exposing the lab directly to the home network

---

### Step 1.2: Creating the Host-Only Network (Admin Access)

The **Host-Only Network** allows:

* the host machine to access the VMs
* secure RDP and SSH access
* management without internet exposure

#### Steps

1. In **Network Manager**, open **Host-Only Networks**
2. Click **Create**
3. Open **Properties**

Configure:

```
IPv4 Address: 10.0.60.1
Subnet Mask: 255.255.255.0
DHCP: Disabled
```
![Desktop View](/assets/images/Third_blog/Hostonlyconfiguration.png){: width="972" height="589" }
_Host-Only Network configuration_



#### Why this matters

This network acts like a **private admin cable**:

* only the host and the VMs can see it
* traffic here is never exposed externally

---

### Step 1.3: Verifying Network Creation

In the host pc powershell ,I confirmed by running

```bash
VBoxManage list natnetworks
VBoxManage list hostonlyifs
```
![Desktop View](/assets/images/Third_blog/verifynetworkcreation.png){: width="972" height="589" }

This confirms that both networks exist before moving on.

---

## Phase 2: Creating and Configuring the Windows EDR VM

The **Windows EDR VM** represents a normal user workstation inside an organization.

Its role is to:

* generate activity
* act as an attack target
* simulate what SOC analysts investigate

---

### Step 2.1: Create the Windows VM

> I had already created the VM. I reccommend using this in the setup

```
Name: Windows-EDR
Type: Microsoft Windows
Version: Windows 10 (64-bit)
Memory: 4 GB
Disk: 60 GB (VDI, dynamically allocated)
```
---

### Step 2.2: Attach Network Adapters 

This VM uses **three network adapters**, each with a different purpose.

| Adapter   | Network          | Purpose            |
| --------- | ---------------- | ------------------ |
| Adapter 1 | NAT Network      | Internet & updates |
| Adapter 2 | Internal Network | Monitored traffic  |
| Adapter 3 | Host-Only        | RDP access         |

#### Configuration

**Adapter 1**

```
Attached to: NAT Network
Name: SOC_Network
```

**Adapter 2**

```
Attached to: Internal Network
Name: lan_monitor
```

**Adapter 3**

```
Attached to: Host-Only Adapter
Name: vboxnet0
```

<div style="display: flex; gap: 10px;">
  <img src="/assets/images/Third_blog/adapter1.png" style="width: 700%;" />
   <img src="/assets/images/Third_blog/adapter2.png" style="width: 700%;" />
    <img src="/assets/images/Third_blog/adapter3.png" style="width: 700%;" />

</div>


#### Why three adapters?

Each adapter connects the VM to a **different trust zone**:

* one for internet
* one for internal traffic
* one for administration

---

### Step 2.3: Configuring Windows Network Interfaces

After installing Windows and logging in:

1. Press **Win + R** or open the cmd and 
2. Type:

   ```
   ncpa.cpl
   ```
3. Press **Enter**

You should see **three Ethernet adapters**.

![Desktop View](/assets/images/Third_blog/3adaptersedr.png){: width="972" height="589" }

---

### Step 2.4: Assigning Static IP Addresses

#### Adapter 1 — NAT Network
1. Right-click **Ethernet** → **Properties**
2. Select **Internet Protocol Version 4 (TCP/IPv4)**
3. Click **Properties**
4. ** I used the following IP address:**
```
IP: 10.0.50.10
Subnet: 255.255.255.0
Gateway: 10.0.50.1
DNS: 8.8.8.8
```

Why only one gateway?

* multiple gateways confuse Windows routing

---

#### Adapter 2 — Internal Network

```
IP: 192.168.100.10
Subnet: 255.255.255.0
Gateway: None
DNS: None
```

This network should never reach the internet.

---

#### Adapter 3 — Host-Only Network

```
IP: 10.0.60.10
Subnet: 255.255.255.0
Gateway: None
DNS: None
```

Used only for RDP from the host.

<div style="display: flex; gap: 10px; justify-content: space-around;">
  <figure style="width: 30%; text-align: center;">
    <img src="/assets/images/Third_blog/ipassignethernet.png" style="width: 100%;" />
    <figcaption>Ethernet Static ip Assignment</figcaption>
  </figure>
  <figure style="width: 30%; text-align: center;">
    <img src="/assets/images/Third_blog/ipassignEthernet2.png" style="width: 100%;" />
    <figcaption>Ethernet2 Static ip Assignment</figcaption>
  </figure>
  <figure style="width: 30%; text-align: center;">
    <img src="/assets/images/Third_blog/ipassignEthernet3.png" style="width: 100%;" />
    <figcaption>Ethernet2 Static ip Assignment</figcaption>
  </figure>
</div>

---
### Step 2.5: Verifying Connectivity

In the Windows EDR open **Command Prompt**:

```
ipconfig
```

![Desktop View](/assets/images/Third_blog/ipconfigwinedr.png){: width="972" height="589" }
_> > This shows the IP configuration of the Windows EDR_

Test:

```
ping 10.0.50.1   # Test NAT gateway  
ping 10.0.60.1   # Host machine reachability  
ping 8.8.8.8     # Check internet reachability  
```

![Desktop View](/assets/images/Third_blog/ping.png){: width="972" height="589" }
_Successful ping results_

The successful ping results show Windows EDR networking is correct.

---

## Next (Coming Up)

In the next section I will guide on:
- build the **Ubuntu NDR VM**
- explain **promiscuous mode**
- configure monitoring-only interfaces
- validate traffic capture with `tcpdump`

---
