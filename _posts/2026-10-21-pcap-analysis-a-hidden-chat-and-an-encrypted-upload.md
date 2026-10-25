---
title: "Pcap Analysis: A Hidden Chat and an Encrypted Upload"
author: baraka
date: 2026-10-21 14:00:00 +0300
description: Working through a practice capture in Wireshark, from counting the machines to finding a plaintext chat on port 250 and a disguised file uploaded to a PHP panel, and what the encrypted traffic still gave away.
image:
  path: /assets/images/Fourteenth_blog/chat-follow-tcp-stream.png
  alt: Wireshark's Follow TCP Stream window showing a plaintext chat between P13 and Cu713 on port 250.
categories: [ Networking, Wireshark ]
tags: [ Wireshark, Pcap Analysis, Network Forensics, HTTP, DNS, TLS, QUIC, NAT ]
---

## Overview

After learning Wireshark on my own home network, I wanted to practise on a capture where I did not already know the story. This post works through `Pcap_Analysis.pcapng`, a practice capture, from the first question (who is in here?) to the interesting part: a chat sent in plain text and a disguised file uploaded to a web panel.

Most of the 25,000 packets are encrypted, so the work was mostly about finding the small parts that are not, and reading what the encrypted parts still reveal.

---

## The capture

I started with **Statistics → Capture File Properties**:

| Field | Value |
|---|---|
| Packets | 25,262 |
| Duration | 337 seconds (about 5.6 minutes) |
| Start | 2023-05-23 17:57:09 UTC |
| Captured on | Windows 10 22H2, Wireshark 4.0.3 |
| Interface | **VMware Network Adapter VMnet8** |

![Desktop View](/assets/images/Fourteenth_blog/capture-properties.png)
_Capture File Properties_

The interface already says a lot. VMnet8 is VMware's **NAT network**, so this capture was taken on a Windows host, looking at the traffic of the virtual machines running on it.

---

## Step 1: Who is in the capture

**Statistics → Endpoints → Ethernet** showed four MAC addresses, all starting with VMware's prefixes (`00:0c:29` for virtual machines and `00:50:56` for VMware's own virtual devices):

| IP | MAC | What it is |
|---|---|---|
| `192.168.235.137` | `00:0c:29:55:9d:d4` | **VM 1**, the busiest host (19 MB). Its browser identifies as Firefox 113 on Ubuntu. |
| `192.168.235.131` | `00:0c:29:39:70:04` | **VM 2**, also Ubuntu (it runs Ubuntu's connectivity check). Very little traffic. |
| `192.168.235.2` | `00:50:56:fd:27:94` | VMware's **NAT gateway and DNS server**. Every DNS query in the capture goes here. |
| `192.168.235.1` | `00:50:56:c0:00:08` | The **Windows host's** VMnet8 adapter. It only sends ARP and NetBIOS. |

![Desktop View](/assets/images/Fourteenth_blog/endpoints-ethernet.png)
_Four VMware MAC addresses: two VMs, the NAT gateway and the host_

---

## Step 2: What protocols are in it

**Statistics → Protocol Hierarchy** showed that almost everything is encrypted:

* **QUIC**: 16,338 packets, 15.7 MB. Most of this is a YouTube video from `googlevideo.com`.
* **TLS**: 2,753 packets
* **DNS**: 1,010 packets
* **HTTP**: only 126 packets, and 118 of those are OCSP (certificate revocation checks)
* **Data**: 25 TCP packets that Wireshark could not match to any protocol

![Desktop View](/assets/images/Fourteenth_blog/protocol-hierarchy.png)
_Protocol Hierarchy: the small "Data" and "HTTP" rows are the interesting ones_

The big rows are the boring part. The small rows are traffic I can actually read, so I started there.

---

## Step 3: A chat on port 250

I filtered for the packets Wireshark could not identify:

```
tcp && data
```

All but one were on **TCP port 250** between the two VMs. Right-clicking one and choosing **Follow → TCP Stream** showed a plain-text conversation.

![Desktop View](/assets/images/Fourteenth_blog/chat-follow-tcp-stream.png)
_The chat between P13 and Cu713 in Follow TCP Stream_

The TCP handshake shows that `.131` connected to port 250 on `.137` at 17:58:54 UTC. There is no protocol on top, just lines of text, which is what a tool like netcat produces. The two people call themselves **P13** (`.137`) and **Cu713** (`.131`):

```
P13:   Hey Cu713! It's been a while. How have you been?
Cu713: Hey P13! I'm good, thanks. I've been working on something cool lately.
Cu713: I've created a new file encryption script. It's pretty awesome.
Cu713: Well, I actually hid the script somewhere. It's like a little treasure hunt.
       But sure, I'm confident you'll find it.
...
Cu713: Oh Before I got I just want to let you know that I left the country.
       and don't ask for prove I'll just send something for you. bye!
```

> Port 250 has no standard service, so Wireshark has no dissector for it and labels the payload "Data". That label is worth checking in any capture: it means **traffic that does not match any protocol Wireshark knows**.
{: .prompt-tip }

The connection never closes (there is no FIN or RST), so it was still open when the capture stopped.

---

## Step 4: The upload to "My Corp. Panel"

The one remaining "Data" packet led to the only interesting HTTP request. I filtered for it:

```
http.request.method == "POST"
```

At 18:01:22 UTC, `.137` sent `POST /panel.php` to **`192.168.1.7`**. That address is not on the VMnet8 network, so the request went out through VMware's NAT, probably to a machine on the host's real network.

![Desktop View](/assets/images/Fourteenth_blog/panel-post-follow-stream.png)
_The POST request and the server's reply_

The request headers:

```
POST /panel.php HTTP/1.1
Host: 192.168.1.7
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) ... Chrome/112.0.5615.50 Safari/537.36
Accept-Encoding: gzip, deflate
Accept: */*
Connection: keep-alive
Content-Type: multipart/form-data; boundary=----WebKitFormBoundary4BIlFVC7HcRhJCay
Cookie: PHPSESSID=a2kttlfv0k65t5g1c0s32lpit8
Content-Length: 107671
```

The server replied `200 OK` with `file uploaded at uploads/file`, followed by a simple upload page titled **"My Corp. Panel"**. The `Server` header says `Apache/2.4.54 (Win64) OpenSSL/1.1.1p PHP/8.0.25`, which looks like a XAMPP setup on Windows.

### The request does not look like it came from the browser

* Every other web request from `.137` says it is **Firefox on Ubuntu**. This one claims to be **Chrome on Windows**.
* The headers are exactly the four defaults of Python's `requests` library, in its order (`User-Agent`, `Accept-Encoding: gzip, deflate`, `Accept: */*`, `Connection: keep-alive`). A real browser sends many more.
* The boundary uses Chrome's `WebKitFormBoundary` style, but the file part has a meaningless `Content-Type: =----=`.

My reading is that this was a **script made to look like a Chrome upload**. I cannot prove which tool sent it, only that the browser on this machine did not send it the way the browser sends everything else.

The request also carries a `PHPSESSID` cookie, but there is no earlier visit to `192.168.1.7` in the capture. So someone used the panel before the capture started.

---

## Step 5: The uploaded file

**File → Export Objects → HTTP** saved the request body. The file inside the multipart wrapper is **107,391 bytes**, and:

* it does not start with any known file signature (JPEG, PNG, ZIP, PDF and so on)
* its entropy is **7.99 bits per byte**, which means it looks like random data: it is either compressed or encrypted
* it does not decode as a simple repeating-key XOR

![Desktop View](/assets/images/Fourteenth_blog/export-http-objects.png)
_Export Objects → HTTP, with panel.php as the largest object_

This fits the chat: Cu713 wrote a **file encryption script** and said they would "send something" as proof of leaving the country. The upload is most likely that something, encrypted. I have not decrypted it yet.

---

## Step 6: The treasure hunt in DNS and SNI

The browsing is encrypted, but the **DNS queries** and the **TLS server names (SNI)** still show which sites `.137` visited, and when. I filtered with `dns.flags.response == 0` and `tls.handshake.extensions_server_name`:

| Time (UTC) | Site |
|---|---|
| 18:01:05 | `twitter.com` |
| 18:01:22 | *(the upload to panel.php)* |
| 18:01:41 | `www.youtube.com`, then a video over QUIC |
| 18:02:14 | `github.com` (DNS lookup only, no connection appears in the capture) |
| 18:02:23 | `medium.com` |
| 18:02:32 | `pastebin.com` |

![Desktop View](/assets/images/Fourteenth_blog/dns-timeline.png)
_DNS queries showing the order of the sites visited_

Twitter, YouTube, GitHub, Medium, Pastebin: this looks like someone following a trail of clues across sites, which is the "treasure hunt" from the chat. Because these are HTTPS, I can see **which sites** but not **which pages**, so the capture alone does not say where the script is.

---

## Things that confused me

* **Every packet from the internet has TTL 128.** TTL is the time-to-live counter that each router decreases by one. Google, Cloudflare and `192.168.1.7` all arrived with exactly 128, which is the starting value Windows uses. VMware's NAT service on the Windows host opens its own connections and sends new packets to the VM, so here the TTL describes the NAT, not the server at the other end.
* **ICMP "Port unreachable" from `.137` to Cloudflare.** These are replies to QUIC packets that arrived after Firefox had already closed the UDP port, not a sign of scanning.
* **Plain HTTP in an HTTPS session.** Firefox checks certificates using OCSP over plain HTTP (`r3.o.lencr.org`, `status.rapidssl.com`). Even fully encrypted browsing leaves these unencrypted requests behind.
* **The Windows host keeps asking for `.2`.** The Windows host sent 72 ARP requests for `192.168.235.2`. That is VMware's virtual networking, not an attack.

---

## Timeline

| Time (UTC) | Event |
|---|---|
| 17:57:09 | Capture starts |
| 17:58:54 | `.131` (Cu713) connects to `.137` (P13) on TCP 250 |
| 17:58:59 to 18:00:58 | Plain-text chat about a hidden file encryption script |
| 18:01:05 | `.137` visits Twitter |
| 18:01:22 | `.137` uploads a 107 KB encrypted file to `192.168.1.7/panel.php` |
| 18:01:41 to 18:02:32 | YouTube, GitHub, Medium, Pastebin |
| 18:02:46 | Capture ends |

---

## What this does not prove

* **Who P13 and Cu713 are.** The names come from the chat text, not from anything the network can verify.
* **How the file got onto `.137`.** The capture shows the upload, but not where the file came from before that.
* **What the file contains.** It is encrypted, and I have not found the script yet.
* **What `192.168.1.7` is.** I only see it through VMware's NAT, so its address, TTL and timing are all shaped by the host.

---

## Outcome

* Four hosts identified from their MAC addresses and behaviour
* A plain-text chat found by filtering for traffic Wireshark could not identify
* A disguised upload to a PHP panel, with headers that do not match the machine's browser
* A browsing trail recovered from DNS and SNI, even though the pages themselves are encrypted

## What I would do differently

I would open **Statistics → Protocol Hierarchy** first. It took me a while to notice that the interesting traffic was hiding in the smallest rows, and the hierarchy shows that immediately.

## Next

Following the trail myself to find Cu713's encryption script, and decrypting the uploaded file.
