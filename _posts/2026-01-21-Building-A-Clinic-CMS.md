---
title: Clinic Guard
author: baraka
date: 2026-01-21 14:59:33 +0300
description: A custom-built Clinic CMS designed to streamline patient management and appointment scheduling for a local healthcare facility.
image:
  path: /assets/images/Second_blog/loginpage.png
  lqip: data:image/webp;base64,UklGRpoAAABXRUJQVlA4WAoAAAAQAAAADwAABwAAQUxQSDIAAAARL0AmbZurmr57yyIiqE8oiG0bejIYEQTgqiDA9vqnsUSI6H+oAERp2HZ65qP/VIAWAFZQOCBCAAAA8AEAnQEqEAAIAAVAfCWkAALp8sF8rgRgAP7o9FDvMCkMde9PK7euH5M1m6VWoDXf2FkP3BqV0ZYbO6NA/VFIAAAA
  alt: The login page of the clinic CMS.
categories: [ System Development,School Project]
tags: [ Clinic CMS, PostgreSQL, Typescript ]
---
## Overview

Managing a clinic involves coordinating multiple workflows: patient records, appointments, billing, prescriptions, and staff access. This project is a Clinic Content Management System (CMS) designed to centralize these operations into a secure, role-based web application.

The system supports multiple user roles, each with access tailored to their responsibilities, ensuring both usability and data security.

## Authentication & Access Control

The CMS implements a centralized authentication system that controls access across all modules. Every user must authenticate before accessing the system, and permissions are enforced based on assigned roles.

## Login Interface
![Desktop View](/assets/images/Second_blog/loginpage.png){: width="972" height="589" .w-50 .left}
The login page serves as the entry point to the system. After a user account is created either by the admin(staff accounts) or the receptionist(patient accounts),tUsers authenticate using the given registered credentials then reset their passwords before logging in, after which they are redirected to a role-specific dashboard. <br> Key considerations <br> 1.Secure credential handling <br> 2.Clear error feedback <br> 3.Simple, distraction-free UI

## Password Reset Flow
![Desktop View](/assets/images/Second_blog/passresets.png){: width="972" height="589" .w-50 .left}
The system includes a complete password recovery workflow <br>The user clicks Forgot Password  <br>Enters the user email for the Password reset. <br>Gets informed to check the mails if that account is associated with that email address 
<br><br><br><br>

![Desktop View](/assets/images/Second_blog/passresetemails.png){: width="972" height="589" .w-50 .right}
The reset link is sent to the user as an email and appears in the email as a green button.The email contains neccesary information on the password reset.<br>Reset links are secure and expire after an hour ensuring users can regain access without administrative intervention while maintaining security.
## Role-Based Dashboards

Once authenticated, users are redirected to dashboards tailored to their role. This design prevents information overload and enforces the principle of least privilege.

### Admin Dashboard
![Desktop View](/assets/images/Second_blog/admindash.png){: width="972" height="589" }
_Admin Dashboard_
The admin dashboard provides a high-level overview of clinic operations. From here, administrators can: <br>
- Manage users and roles
- Access audit logs
- Oversee billing,inventory and other operational modules

This dashboard acts as the control center of the CMS.
### Receptionist Dashboard
![Desktop View](/assets/images/Second_blog/receptionistdash.png){: width="972" height="589" }
_Receptionist Dashboard_
Receptionists handle the operational front desk tasks, including: <br>

- Patient registration
- Appointment scheduling

This dashboard prioritizes speed and clarity, enabling efficient patient flow management.
### Doctor Dashboard
![Desktop View](/assets/images/Second_blog/doctordash.pngdash.png){: width="972" height="589" }
_Doctor Dashboard_
Doctors interact primarily with:

- Patient medical records like adding patient diagnosis
- Adding patient Prescriptions 
- Requesting lab results from the Lab tech
- Appointment schedules

The interface is optimized for quick access to clinical information, minimizing navigation overhead during consultations
### Lab Yechnician Dashboard
![Desktop View](/assets/images/Second_blog/labdash.pngdash.png){: width="972" height="589" }
_Lab Technician Dashboard_
Laboratory operations are handled through a dedicated Lab Technician Dashboard, designed to allow lab staff to work efficiently without exposing unnecessary patient information.<br> The lab tech: <br> 
- views the reccomended lab tests of the patients
- View pending lab tests
- Adds,Uploads and updates Lab results.

