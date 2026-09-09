# Privio Privacy Policy

Version 2.1, effective 1 September 2026.

This is an English translation. In case of any discrepancy, the Polish version
[PRIVACY.md](PRIVACY.md) prevails.

## 1. Controller and contact details

The controller of personal data received in connection with the distribution, sale and support of
Privio is **mintstudio Jakub Koncewicz**, an entrepreneur entered in the Polish Central Register and
Information on Economic Activity (CEIDG), Polish tax identification number NIP 6881285861 (the
“Controller”).

- privacy email: **kontakt@mintstudio.pl**;
- correspondence address: **ul. Pełczyńskiego 22A/24, 01-471 Warsaw, Poland**.

The Controller has not appointed a data protection officer because the statutory conditions requiring
one do not apply.

## 2. Core principle: application data stays local

Privio requires no account and contains no usage telemetry, analytics, advertising or cloud
synchronisation. The Controller does not receive application configuration or data created during
normal operation.

The following are stored locally on the Mac:

- protected application and website lists and their settings;
- protection, shortcut, login-item and language settings;
- a history of up to 200 recent protection events, including date, event type, reason, application
  name and bundle identifier;
- information about detected browser-extension installations;
- the Pro License key and its technical identifier;
- files, notes and metadata placed by the user in the Private Vault, together with local vault
  settings;
- the random vault-encryption key protected in the macOS Keychain and the recovery key shown to the
  user;
- optional unsuccessful-authentication photos.

These data reside in Privio’s data directory, application preferences, browser-extension storage or
other local macOS stores. They are not sent to the Controller. They can be removed through Privio, by
clearing extension data or by manually deleting the relevant local data. Uninstalling Privio does not
automatically remove the encrypted vault image, preventing accidental loss of user files.

The Private Vault is an APFS image encrypted with AES-256 by macOS facilities. Privio supplies the
image password to the system tool only through the process’s standard input, not command arguments or
logs. Reading the key from Keychain requires user presence confirmed by macOS. The Controller does
not receive the account password, biometric data, encryption key, recovery key or vault contents.
After unlocking, the contents remain locally available until the image is unmounted.

## 3. Optional unsuccessful-authentication photos

The photo feature is off by default. Privio requests camera access when it is enabled. Once permission
is granted, a photo may be taken when an authentication prompt ends without unlocking, including after
cancellation. No photo is taken when authentication is unavailable.

Photos:

- are stored only in Privio’s local data directory;
- are not sent by Privio to the Controller or any other party;
- can be viewed in Activity and deleted in Settings;
- are automatically limited to the 20 most recent files.

The Controller does not determine the purpose or means of using local photos and cannot access them.
Depending on context, the controller of personal data captured in a photo may be the user, their
employer or another entity. That entity is responsible for a legal basis, transparency information,
retention and compliance with data-protection, image-right, employment and monitoring law. The feature
is not intended for covert monitoring.

## 4. Browser extension and local proxy

The Privio extension needs browser permissions relating to tabs, navigation and website addresses to
recognise a protected domain, redirect blocked navigation and determine when to lock again.
Information about protected domains, the active tab, temporary reveal and protection state is
exchanged only between the extension and the application over the `127.0.0.1` loopback interface and
may be stored in local browser storage. It is not sent to the Controller.

The local proxy relays traffic required to enforce website protection. For HTTPS connections it sees
the destination host name and forwards the encrypted stream without decrypting page content. Ordinary
Internet traffic still reaches websites selected by the user and their providers under their own
privacy notices.

## 5. Protected-website icons

After a website is added, Privio may directly retrieve its `favicon` or Apple Touch icon over HTTPS
for display in the interface. The request is made only to the domain entered by the user, not to the
Controller or an external icon aggregation service. The Controller does not receive the protected
domain list.

The website server may receive standard connection data such as the IP address, request time,
User-Agent and requested file path. The operator of that domain is the controller of those data and
processes them under its own privacy notice.

## 6. Updates

When Check for Updates is selected, Privio uses the Sparkle framework to contact an HTTPS update feed
currently hosted by **GitHub, Inc.** The application may download release information and a signed
update package. Automatic update checks and system profiling are off by default.

Privio does not attach the Pro License key or identifier, hardware identifiers, protected application
or website lists, activity history or photos to the request. GitHub may nevertheless receive standard
technical data required for a connection, particularly the IP address, time, User-Agent and requested
file.

The purposes are to supply the requested update and secure the Software. The Controller’s legal bases
are performance of the agreement or steps requested before entering into it under Article 6(1)(b)
GDPR, and the legitimate interest in secure distribution and prevention of abuse under Article
6(1)(f) GDPR.

## 7. Pro License purchase and support

Where a Pro License is purchased directly from the Controller, the following may be processed:

- purchaser name or business name;
- email address;
- billing and tax details supplied for a sales document;
- order identifier, license identifier, price, currency, date and payment status;
- correspondence about the order, refund or complaint.

The purposes are entering into and performing the agreement, delivering the key, handling payment,
complaints and Consumer rights, complying with accounting and tax duties, and establishing, pursuing
or defending legal claims. The legal bases are Article 6(1)(b), (c) and (f) GDPR, as applicable.

Payment and sale may be handled by a Merchant of Record identified before purchase. That entity may
act as an independent controller of payment, tax and transaction data under its own privacy notice.
The Controller does not receive complete payment-card data. Data supplied to the Controller are
limited to information necessary to deliver and support the license. Where the Controller receives
data from an external seller, that seller is the source and the scope is limited to the order data
listed above.

## 8. Contact, support and complaints

When a user contacts the Controller, data in the message are processed, usually the email address,
name or business name, correspondence and voluntarily provided technical information.

The purposes are responding, providing technical support, handling complaints and preventing abuse.
The legal basis is Article 6(1)(b) GDPR where contact concerns an agreement or pre-contract steps, and
Article 6(1)(f) GDPR - the legitimate interests in correspondence, security and defence of claims.

Do not send passwords, the full license key, unsuccessful-attempt photos or third-party personal data
unless strictly necessary to resolve the matter.

## 9. Recipients

To the extent necessary for the stated purposes, recipients may include:

- email, hosting and secure-storage providers;
- GitHub, Inc. as the update-feed infrastructure provider;
- a payment provider or Merchant of Record identified at purchase;
- accounting, legal and technical-support providers subject to confidentiality;
- public authorities where disclosure is required by law.

The Controller does not sell personal data or use them for behavioural advertising.

## 10. Transfers outside the EEA

GitHub and some providers may process data in the United States or other countries outside the
European Economic Area. GitHub states that it is certified under the EU-U.S. Data Privacy Framework,
covered by European Commission Implementing Decision (EU) 2023/1795, and uses European Commission
standard contractual clauses where needed. Current information and a copy of applicable safeguards
can be obtained from the provider’s privacy notice or by contacting the Controller.

Where another entity participates in a purchase, its identity, location and transfer mechanism are
described in its privacy notice available before data are submitted.

## 11. Retention

- Application and extension data remain local until deleted by the user; history is limited to 200
  entries and photos to 20 files.
- Private Vault contents and its encrypted image remain local until separately deleted by the user;
  the Controller neither determines their retention period nor has access to them.
- Agreement, support and complaint correspondence is retained while the matter is handled and then
  until the applicable limitation period expires, or longer where required by pending proceedings.
- Transaction and tax records are retained for the period required by accounting and tax law.
- Data needed to confirm entitlement under a perpetual Pro License are retained for the license term
  and then until relevant claim periods expire.
- Technical connection data retained by independent providers are subject to the periods in their
  privacy notices.

After the applicable period, data are erased or anonymised unless further retention is required by law
or necessary to establish, pursue or defend legal claims.

## 12. Data-subject rights

Within the limits of the GDPR, a person has the right to:

- access personal data and obtain a copy;
- rectify personal data;
- erase personal data;
- restrict processing;
- receive portable data processed by automated means on the basis of consent or contract;
- object to processing based on a legitimate interest;
- withdraw consent at any time without affecting earlier lawful processing.

A request may be sent to **kontakt@mintstudio.pl**. The Controller may request information necessary
to verify identity. Where data are held only locally and the Controller does not possess them, rights
are exercised through the application or operating-system functions.

A complaint may also be lodged with the **President of the Polish Personal Data Protection Office**
or the competent supervisory authority in the person’s habitual residence, workplace or place of the
alleged infringement.

## 13. Whether data are required and automated decisions

Providing data in correspondence is voluntary, but without contact details or information needed to
understand the matter, a response may be impossible. Data required at checkout are necessary to enter
into and perform the agreement or comply with law; without them a purchase may be unavailable.

The Controller does not make decisions producing legal effects solely through automated processing
and does not profile Privio users.

## 14. Security

The Controller applies measures appropriate to the nature and risks of processing, including data
minimisation, access controls and provider safeguards. Update transmission and icon retrieval use
HTTPS. Update packages are cryptographically verified. No processing method provides absolute
security.

## 15. Cookies

The Privio application does not use cookies. A website, GitHub or a seller’s checkout may use cookies
and similar technologies under the policy presented on that service.

## 16. Changes to this Policy

This Policy may change following a change in law, functionality, provider or processing. A material
change is communicated in a manner appropriate to its impact, and the current version remains
available in the application and official repository. Where consent is required, processing under new
terms begins only after consent is obtained.
