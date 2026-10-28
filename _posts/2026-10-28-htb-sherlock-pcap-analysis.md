---
title: "HTB Sherlock: PCAP Analysis"
author: baraka
date: 2026-10-28 10:00:00 +0300
description: A Hack The Box Sherlock walkthrough. Six questions about one packet capture, answered in Wireshark by narrowing 25,000 packets down to a plain-text chat and a single file upload.
image:
  path: /assets/images/Seventeenth_blog/banner.png
  alt: The Hack The Box Sherlock card for PCAP Analysis, rated Very Easy, with 165 XP.
categories: [ Security, HTB Sherlocks ]
tags: [ HTB, Sherlocks, Wireshark, tshark, Pcap Analysis, Network Forensics, HTTP, DFIR ]
---

## Overview

**PCAP Analysis** is a *Very Easy* Sherlock on Hack The Box. The scenario:

> We have captured this traffic from P13's computer. Can you help him?

The download is `PCAP_Analysis.zip` (password `hacktheblue`), which contains one file, `Pcap_Analysis.pcapng`. There are six questions, and every answer is in the capture.

The capture has 25,262 packets, and most of them are encrypted. This post does not read all of them. It uses a short method to find the few packets that matter, and each answer shows the Wireshark steps that produced it.

---

## Setup

```bash
unzip -P hacktheblue PCAP_Analysis.zip
sha256sum Pcap_Analysis.pcapng
capinfos Pcap_Analysis.pcapng
```

| Field | Value |
|---|---|
| Packets | 25,262 |
| Duration | 337 seconds |
| Captured | 2023-05-23, 17:57 to 18:02 UTC |
| Capture interface | VMware Network Adapter VMnet8 |
| SHA256 | `97e9b5e4a2c0e5bbc924f5d4edf5c5f67951f770059d69f5c6f820ecc932865b` |

VMnet8 is the adapter VMware uses for its NAT network, so the capture was taken on a host running virtual machines.

---

## The approach

Reading 25,000 packets one by one is not realistic, so I used four steps:

1. **Orient**: read the capture properties for scale, time and interface.
2. **Triage**: use the Protocol Hierarchy to separate traffic that is encrypted from traffic that is readable.
3. **Pivot**: filter on the readable traffic and follow it.
4. **Verify**: check the server's reply, not only the request.

---

## Triage: Protocol Hierarchy

**Statistics → Protocol Hierarchy** shows every protocol and how much of the capture it takes up.

![Desktop View](/assets/images/Seventeenth_blog/protocol-hierarchy.png)
_Protocol Hierarchy of the capture_

| Protocol | Packets | Share of bytes | Readable? |
|---|---|---|---|
| QUIC | 16,338 | 78.0% | No, encrypted |
| TLS | 2,693 | 15.8% | No, encrypted |
| DNS | 1,010 | 0.5% | Yes |
| HTTP | 126 | 0.2% | Yes |
| MIME Multipart | 1 | 0.6% | Yes |
| Data | 25 | under 0.1% | Unidentified |

Almost everything is encrypted browsing, which I skipped. Two rows are worth following:

* **Data** (25 packets): payload that Wireshark could not identify as a known protocol.
* **HTTP** (126 packets): 118 of them are OCSP certificate checks, so 8 are something else. One of those carries a **MIME Multipart** body of 107,671 bytes in a single request, which is the signature of a file upload.

---

## Task 1: The sender and receiver

> In network communication, what are the IP addresses of the sender and receiver?

I started with the unidentified traffic. Filtering for it:

```
data
```

![Desktop View](/assets/images/Seventeenth_blog/data-filter-ports.png)
_The 25 `data` packets, with the TCP ports added as columns_

The filter shows 26 packets, one more than the Protocol Hierarchy listed under `Data`. 25 of them are TCP segments between the same two endpoints on port **250**. The 26th is frame 3513, the file upload from Task 2: its file part has an unknown content type (`=----=`), so Wireshark labels those bytes `data` too. Port 250 is the part to follow now, and the upload comes back in Task 2.

In the 25 chat packets, one side always uses the fixed port **250** and the other uses the same random high port (59576). The random high port is the client. The fixed port is the listener. Right-clicking a packet and choosing **Follow → TCP Stream** shows the conversation:

```
P13: Hey Cu713! It's been a while. How have you been?
Cu713: Hey P13! I'm good, thanks. I've been working on something cool lately.
P13: Oh, really? What is it?
Cu713: I've created a new file encryption script. It's pretty awesome.
P13: That sounds interesting! Can I check it out?
Cu713: Well, I actually hid the script somewhere. It's like a little treasure hunt. ...
```

![Desktop View](/assets/images/Seventeenth_blog/chat-follow-stream.png)
_Follow TCP Stream on port 250_

The footer of the window agrees with the Protocol Hierarchy: 13 client packets and 12 server packets make the 25 `data` packets, and the conversation totals 1,128 bytes, the same figure as the `Data` row. The dropdown at the bottom splits the bytes by direction:

| Direction | Bytes |
|---|---|
| `192.168.235.131:59576` → `192.168.235.137:250` (client, Cu713) | 714 |
| `192.168.235.137:250` → `192.168.235.131:59576` (server, P13) | 414 |

The chat ends with a message from Cu713 that matters for the rest of the case:

```
Cu713: Oh Before I got I just want to let you know that I left the country. and don't
ask for prove I'll just send something for you. bye!
```

The TCP handshake shows who started it:

```bash
tshark -r Pcap_Analysis.pcapng -Y 'tcp.port==250 && tcp.flags.syn==1' \
  -T fields -e ip.src -e ip.dst -e tcp.flags
```

```
192.168.235.131   192.168.235.137   0x0002   (SYN)
192.168.235.137   192.168.235.131   0x0012   (SYN, ACK)
```

`192.168.235.131` opened the connection to `192.168.235.137:250`, so it is the TCP client. But "sender" is not the same as "client". The first data packet in the conversation is frame 2398, sent by `192.168.235.137` (P13) to `192.168.235.131` (Cu713), and the scenario says the traffic was captured from P13's computer. I treat the host that sent the data first as the sender.

**Answer:** `192.168.235.137` (sender) and `192.168.235.131` (receiver)

> The question does not say which conversation it means. If the platform rejects this pair, the other pair in the capture is the upload in Task 2.
{: .prompt-info }

---

## Task 2: The web server's IP address

> P13 uploaded a file to the web server. What is the IP address of the server?

An upload sends data, and HTTP sends data with `POST`:

```
http.request.method == "POST" && !ocsp
```

I added `!ocsp` because most POSTs in this capture are certificate checks that the browser makes in the background. One request remains:

![Desktop View](/assets/images/Seventeenth_blog/post-request.png)
_The only non-OCSP POST in the capture_

```bash
tshark -r Pcap_Analysis.pcapng -Y 'http.request.method == "POST" && !ocsp' \
  -T fields -e frame.number -e ip.src -e ip.dst -e http.request.uri
```

```
3513   192.168.235.137   192.168.1.7   /panel.php
```

The request uses a bare IP address as its `Host`, and `192.168.1.7` appears in no other connection in the capture. That means the whole story with this server is a single TCP stream.

**Answer:** `192.168.1.7`

---

## Task 3: The name of the file

> What is the name of the file that was sent through the network?

I selected the request and expanded **MIME Multipart Media Encapsulation** in the Packet Details pane:

![Desktop View](/assets/images/Seventeenth_blog/multipart-filename.png)
_The multipart section of the request_

```
------WebKitFormBoundary4BIlFVC7HcRhJCay
Content-Disposition: form-data; name="file"; filename="file"
Content-Type: =----=
```

`name="file"` is the name of the HTML form field. The name of the uploaded file is `filename="file"`. The server confirms it in its reply in Task 5.

I also exported the body with **File → Export Objects → HTTP** (or `tshark --export-objects http,obj`) and checked the file inside the wrapper:

| Property | Value |
|---|---|
| Size | 107,391 bytes |
| Known file signature | none (`file` reports `data`) |
| Entropy | 7.99 bits per byte |

An entropy that close to 8 means the bytes look random, which is what compressed or encrypted data looks like. That matches the "encrypted file" in the question, but this check alone does not prove what the file contains.

**Answer:** `file`

---

## Task 4: The web server software

> What web server software is running on the target machine?

The server describes itself in the response headers. I filtered for the reply with `http.response && ip.src == 192.168.1.7`, which leaves one packet (frame 3518), and expanded **Hypertext Transfer Protocol**:

![Desktop View](/assets/images/Seventeenth_blog/response-server-header.png)
_The server's 200 OK response, frame 3518, with the `Server` header selected_

```
HTTP/1.1 200 OK
Date: Tue, 23 May 2023 18:01:22 GMT
Server: Apache/2.4.54 (Win64) OpenSSL/1.1.1p PHP/8.0.25
X-Powered-By: PHP/8.0.25
```

The web server is **Apache 2.4.54**, built for 64-bit Windows, running PHP 8.0.25.

**Answer:** `Apache` (full banner: `Apache/2.4.54 (Win64) OpenSSL/1.1.1p PHP/8.0.25`)

---

## Task 5: The upload directory

> What directory was the file uploaded to?

The body of the same response says where the file went. It is in **Line-based text data** at the bottom of the details pane:

![Desktop View](/assets/images/Seventeenth_blog/response-body-directory.png)
_The body of the response_

```
file uploaded at uploads/file
```

The page that follows is a simple form titled "My Corp. Panel". The status `200 OK` and the message together show that the upload succeeded.

**Answer:** `uploads`

---

## Task 6: How long the upload took

> How long did it take the sender to send the encrypted file?

The upload is one TCP connection, so its duration is the answer. **Statistics → Conversations → TCP**, with **Limit to display filter** ticked and the filter `ip.addr == 192.168.1.7`:

```bash
tshark -r Pcap_Analysis.pcapng -q -z conv,tcp | grep '192.168.1.7:80'
```

```
192.168.235.137:40740 <-> 192.168.1.7:80   159 frames   117 kB   252.852088   0.0073
```

I cross-checked it against the packet timestamps:

| Event | Frame | Seconds since capture start |
|---|---|---|
| SYN (connection opens) | 3365 | 252.852088 |
| First part of the request | 3368 | 252.852844 |
| Server `200 OK` | 3518 | 252.857885 |
| Last ACK (connection closes) | 3523 | 252.859398 |

The connection lasted 0.0073 seconds, about 7.3 milliseconds.

**Answer:** `0.0073` seconds

---

## Answers at a glance

| # | Question | Answer |
|---|---|---|
| 1 | Sender and receiver | `192.168.235.137`, `192.168.235.131` |
| 2 | Web server IP | `192.168.1.7` |
| 3 | File name | `file` |
| 4 | Web server software | Apache |
| 5 | Upload directory | `uploads` |
| 6 | Upload duration | `0.0073` seconds |

---

## What I learned

* **Rank traffic by how readable it is.** Most of the capture was encrypted and could be skipped. The answers were in the small cleartext rows.
* **An unusual port is a lead.** Traffic on port 250 had no protocol label, and Follow TCP Stream turned it into a readable chat.
* **Match the filter to the question.** "Uploaded" means POST, and removing the OCSP noise leaves one request.
* **Read the response, not only the request.** The server's own reply gave the software, the success status and the directory.
* **Use Statistics for duration questions.** The Conversations table measures a connection consistently.

## Limits of this analysis

* The capture shows the file being uploaded. It does not show where the file came from.
* The file's contents are unreadable. Its size and entropy are consistent with encryption, but I did not decrypt it.
* The names P13 and Cu713 come from the chat text and cannot be verified from the network.

## Tools used

* Wireshark: Protocol Hierarchy, Conversations, Follow TCP/HTTP Stream, Export Objects
* `unzip`, `sha256sum`, `capinfos`, `tshark` for the command-line checks
