---
title: "HTB Sherlock: PCAP Analysis"
author: baraka
date: 2026-10-28 10:00:00 +0300
description: A Hack The Box Sherlock writeup. One packet capture investigated in Wireshark.
image:
  path: /assets/images/PCAP_Analysis_blog/banner.png
  alt: The Hack The Box Sherlock card for PCAP Analysis, rated Very Easy, with 165 XP.
categories: [ Security, HTB Sherlocks ]
tags: [ HTB, Sherlocks, Wireshark, tshark, Pcap Analysis, Network Forensics, HTTP, DFIR ]
---

**Prepared by:** Mulandii · **Difficulty:** Very Easy

## Description

A capture from a user's computer holds a plain-text chat and a file upload among thousands of encrypted packets. Find who talked to whom and where the file went.

## Scenario

> We have captured this traffic from P13's computer. Can you help him?

## Artifacts Provided

`PCAP_Analysis.zip` (SHA-256 `1c30999cc3473342db6f6a0c655a8f90cf499980111a4c545104b02e963bb500`), password `hacktheblue`, containing `Pcap_Analysis.pcapng`.

## Skills Learnt

* Triage of a large capture with the Protocol Hierarchy
* Wireshark display filters and Follow TCP Stream
* Reading HTTP requests and responses
* Measuring connection duration

## Initial Analysis

```bash
unzip -P hacktheblue PCAP_Analysis.zip
capinfos Pcap_Analysis.pcapng
```

The capture has 25,262 packets over 337 seconds, taken on 2023-05-23 from a VMware NAT adapter (VMnet8). Start with **Statistics → Protocol Hierarchy**:

![Desktop View](/assets/images/PCAP_Analysis_blog/protocol-hierarchy.png)
_Protocol Hierarchy_

Most traffic is encrypted (QUIC 78%, TLS 16%). Two rows are readable and worth a look:

* **Data** (25 packets): payload Wireshark could not identify.
* **HTTP** (126 packets): 118 are OCSP checks. One request carries a 107,671-byte multipart body, which is a file upload.

## Questions

### 1. In network communication, what are the IP addresses of the sender and receiver?

Filter for the unidentified traffic with `data`:

![Desktop View](/assets/images/PCAP_Analysis_blog/data-filter-ports.png)
_`data` packets with TCP ports as columns_

25 of the 26 packets are one TCP stream on port **250**. The 26th is the file upload from Question 2. **Follow → TCP Stream** shows a chat:

![Desktop View](/assets/images/PCAP_Analysis_blog/chat-follow-stream.png)
_Follow TCP Stream, port 250_

```
P13: Hey Cu713! It's been a while. How have you been?
Cu713: Hey P13! I'm good, thanks. I've been working on something cool lately.
P13: Oh, really? What is it?
Cu713: I've created a new file encryption script. It's pretty awesome.
```

`192.168.235.131` opened the connection, so it is the TCP client. The first data packet (frame 2398) comes from `192.168.235.137` (P13), and the capture is from P13's computer. So `.137` is the sender.

**Answer:** `192.168.235.137` (sender) and `192.168.235.131` (receiver)

### 2. P13 uploaded a file to the web server. What is the IP address of the server?

An upload is an HTTP `POST`. Exclude the OCSP background checks:

```
http.request.method == "POST" && !ocsp
```

![Desktop View](/assets/images/PCAP_Analysis_blog/post-request.png)
_The only non-OCSP POST_

One request remains: frame 3513, `POST /panel.php` from `192.168.235.137` to `192.168.1.7`.

**Answer:** `192.168.1.7`

### 3. What is the name of the file that was sent through the network?

Expand **MIME Multipart Media Encapsulation** in the request:

![Desktop View](/assets/images/PCAP_Analysis_blog/multipart-filename.png)
_Multipart section_

```
Content-Disposition: form-data; name="file"; filename="file"
Content-Type: =----=
```

`name` is the form field. `filename` is the file. The exported body is 107,391 bytes with entropy 7.99, which looks encrypted or compressed. That does not prove what it contains.

**Answer:** `file`

### 4. What web server software is running on the target machine?

Filter the reply with `http.response && ip.src == 192.168.1.7` (frame 3518) and expand the HTTP header:

![Desktop View](/assets/images/PCAP_Analysis_blog/response-server-header.png)
_Server header in frame 3518_

```
Server: Apache/2.4.54 (Win64) OpenSSL/1.1.1p PHP/8.0.25
```

**Answer:** `Apache`

### 5. What directory was the file uploaded to?

The body of the same response says where the file went:

![Desktop View](/assets/images/PCAP_Analysis_blog/response-body-directory.png)
_Response body_

```
file uploaded at uploads/file
```

**Answer:** `uploads`

### 6. How long did it take the sender to send the encrypted file?

The upload is one TCP connection. Use **Statistics → Conversations → TCP**, or:

```bash
tshark -r Pcap_Analysis.pcapng -q -z conv,tcp | grep '192.168.1.7:80'
```

```
192.168.235.137:40740 <-> 192.168.1.7:80   159 frames   117 kB   252.852088   0.0073
```

Check: the SYN is at 252.852088 s (frame 3365) and the last ACK at 252.859398 s (frame 3523). That is 0.0073 s.

**Answer:** `0.0073`

## Summary

P13 chatted with Cu713 in plain text on port 250. P13's machine uploaded a 107,391-byte file named `file`, which looks encrypted, to Apache at `192.168.1.7`. It was stored in `uploads/` and the upload took 7.3 ms. The capture does not show where the file came from, and the names P13 and Cu713 come from the chat only.

![Desktop View](/assets/images/PCAP_Analysis_blog/solved.png)
_PCAP Analysis solved_
