# Privio - End-User License Agreement and Electronic Services Terms

Version 11.0, effective 1 September 2026.

This is an English translation. In case of any discrepancy, the Polish version
[EULA.md](EULA.md) prevails.

This document governs use of the official Privio application and, where applicable, constitutes the
terms for services supplied electronically. The source code is made available separately under
[LICENSE.md](LICENSE.md).

## Important: scope of Privio protection

Privio is an additional privacy and access-protection layer, not a complete computer data-security
system. Application locking operates primarily at the interface level: it limits the visibility and
activation of protected windows. It does not lock or encrypt an application's files, databases,
caches, exports, backups or other data accessible on disk, in Finder, through Terminal or through
other software. The exception is content that the user places in the separate Private Vault, which is
encrypted only within the scope described in section 14.

Privio may reduce the risk of accidental or unauthorised viewing, but no software provides 100%
protection against access, circumvention, malware, data loss or user error. Privio is not a substitute
for the macOS screen lock, a strong account password, FileVault, system and application updates,
appropriate permission management, backups or physical control of the computer.

Privio protects the surface of your apps, not the data they hold inside. Even with protection enabled, a
determined, skilled attacker may, with enough effort, reach the data of locked apps "from the inside" -
by exploiting those apps' or the system's own security flaws. For that reason, despite the safeguards in
place, you should not give unwanted people access to your computer.

By accepting these Terms, the user confirms that this information was provided before using Privio
and that the user understands the Software's purpose and technical limits. This acknowledgement does
not waive any mandatory Consumer rights or exclude the Provider's liability where applicable law does
not permit it to be limited.

## 1. Service provider

The service provider, licensor and author of Privio is **mintstudio Jakub Koncewicz**, an entrepreneur
entered in the Polish Central Register and Information on Economic Activity (CEIDG), Polish tax
identification number NIP 6881285861 (the “Provider”).

- electronic contact: **kontakt@mintstudio.pl**;
- correspondence and complaint address: **ul. Pełczyńskiego 22A/24, 01-471 Warsaw, Poland**.

This is an address for service. The Provider has no fixed place of business. No special regulatory
authorisation is required for the services covered by these Terms.

## 2. Formation of the agreement and availability of the Terms

The agreement is formed when the user accepts these Terms in the application. If the user declines,
the application closes. The user should retain a copy; the current text remains available in the
application’s About section and in Privio’s official repository.

A person using Privio for an organisation represents that they are authorised to bind it. A minor may
use Privio only to the extent they can validly enter into this agreement under applicable law or with
the consent of their legal representative.

## 3. Definitions

- **Privio** or **Software** - the Privio macOS application, bundled browser extension, assets and
  documentation.
- **Official Build** - a build prepared and distributed by the Provider through an official channel.
- **Free Features** - features not designated as Pro.
- **Pro Features** - features designated as Pro, in particular website protection.
- **Pro License** - a cryptographically signed key that unlocks Pro Features.
- **Consumer** - a natural person acting for purposes outside their trade, business, craft or
  profession. Consumer provisions also apply to any natural person to whom applicable law grants
  equivalent rights for a particular transaction.

## 4. Official Build license

The Provider grants the user a non-exclusive license to install and use the Official Build on Mac
computers owned by the user or used with their owner’s permission.

Free Features may be used without charge for personal and professional purposes and for an
organisation’s internal purposes. Pro Features require a valid Pro License. The license does not
transfer intellectual-property ownership and, subject to mandatory law, may not be transferred,
resold or sublicensed.

## 5. Nature and scope of electronic services

Privio provides:

- local configuration and enforcement of protection for selected applications;
- the local Privacy Curtain and temporary Reveal functions;
- the local Private Vault: an encrypted APFS image for files and notes, unlocked through macOS
  authentication or a recovery key followed by additional authentication;
- a local protection activity history;
- optional website protection in supported Chromium browsers through the Privio extension and a
  local proxy server;
- local verification and storage of a Pro License;
- manual checking and downloading of updates from a signed update feed;
- optional local photographs after unsuccessful or cancelled authentication.

Core protection functions run locally and require no account. An Internet connection is needed to
download Privio, check for updates, retrieve icons for protected websites and use websites normally.
Processing details are in [PRIVACY.en.md](PRIVACY.en.md).

The user may stop using the services at any time by disabling a function, deleting data in the
application or uninstalling Privio. Uninstalling the application does not automatically delete the
Private Vault image; the user deletes it separately after making any required backup. Removing a
license from the application does not cancel rights
resulting from its purchase, but disables Pro Features on that device until a valid key is entered
again.

## 6. Technical requirements, compatibility and interoperability

The Official Build requires a compatible Mac running **macOS 14 or later**, together with storage
space for the application and its local data. Authentication uses macOS facilities and, depending on
hardware and configuration, may use Touch ID or the macOS account password.

The Private Vault requires APFS, the disk-image tools supplied with macOS and additional storage
corresponding to the stored data. The image has a logical capacity selected when it is created, while
its sparse-bundle storage use grows with its contents.

Some functions require permissions identified by macOS, including camera access for optional photos.
Website protection requires a current supported Chromium browser, the Privio extension and permission
for local proxy configuration. The extension is currently intended for Google Chrome, Microsoft Edge,
Brave, Opera and Vivaldi. Changes to macOS or a browser may temporarily affect compatibility until an
update is made available.

## 7. Pro License

The Pro License is verified entirely on the device using an Ed25519 signature. Privio creates no
account, performs no online activation, uses no hardware identifier and does not send the license key
or license identifier to the Provider.

A Pro License is assigned to its purchaser on a per-user basis. An individual may use it on their Mac
computers. An organisation requires a separate entitlement for each user of Pro Features unless the
purchase offer expressly provides otherwise. The key may be stored in Privio’s local data directory.
Reinstalling or updating the application does not invalidate a valid key.

Pro Features may not be used without a valid Pro License, including by bypassing, disabling or
modifying the licensing mechanism. The technical ability to alter publicly visible code is not
permission. This restriction does not limit rights that cannot be excluded by contract, including
statutory rights to observe, study or test a program and rights necessary for interoperability.

## 8. Purchasing a Pro License

Where a Pro License is offered for payment, the transaction is governed by
[SALES.en.md](SALES.en.md) and by the information presented immediately before the order is placed.
The total price, taxes, currency, payment method, scope of the license, seller identity and delivery
method are shown before the user incurs an obligation to pay.

The seller may be the Provider or an external Merchant of Record identified at checkout. Where that
entity is the seller, it handles payment, invoicing, taxes, withdrawal and refunds under the terms
shown in its checkout. This EULA continues to govern use of Privio.

## 9. Right of withdrawal

A Consumer entering into a distance contract generally has 14 days to withdraw without giving a
reason. For paid digital content not supplied on a tangible medium, that right may expire once supply
begins before the 14-day period ends only where the Consumer gave prior express consent, acknowledged
the loss of the right, and the seller provided confirmation of the agreement and consent on a durable
medium. If those conditions are not met, the Consumer does not lose a statutory right.

## 10. Acceptable use

The user must:

- use Privio lawfully, in accordance with these Terms and third-party rights;
- not supply unlawful content through Privio services;
- not use the camera feature for covert or unlawful monitoring;
- not distribute the Official Build or modified binaries outside an official channel;
- not sell, rent or sublicense the Software;
- not remove copyright or license notices;
- not use the Privio name, logo or marks in a manner suggesting a non-existent affiliation or
  endorsement.

These restrictions concern the Provider’s rights in Privio and do not alter third-party component
licenses.

## 11. Privacy and local data

Privio contains no telemetry, advertising analytics or cloud synchronisation. Configuration, lists of
protected applications and websites, activity history, the license key, photos and Private Vault
contents remain on the Mac.
The Provider has no access to them. Network connections, contact and purchase are described in
[PRIVACY.en.md](PRIVACY.en.md).

## 12. Optional unsuccessful-authentication photos

This feature is off by default. Enabling it requires a deliberate user action and macOS camera
permission. Once enabled, Privio may take a photo when an authentication prompt ends without unlocking,
including after cancellation. No photo is taken when authentication is unavailable. Privio retains no
more than the 20 newest photos locally; the user can view and delete them in the application.

The user is solely responsible for establishing a legal basis, providing any required notice and
complying with data-protection, image-right, employment and monitoring laws. macOS camera permission
does not replace those duties. The feature is not intended for covert observation of employees,
household members or any other person.

## 13. Updates and conformity of digital content

Updates are checked through Sparkle when the user selects Check for Updates. Production update
packages should be cryptographically signed, signed with an Apple Developer ID certificate and
notarised by Apple. Development builds may lack those properties and are not intended for public
distribution.

Consumers receive updates, including security updates, required by mandatory law for the period they
may reasonably expect, taking into account Privio’s nature and purpose and the circumstances of the
agreement. Users should install available updates within a reasonable time. Failure to install an
update after being properly informed of its availability and the consequences of not installing it
may have the effects provided by law.

Consumers retain statutory rights concerning delivery and conformity of digital content, including -
where the statutory conditions are met - the right to have content brought into conformity, receive a
price reduction or terminate the agreement. These Terms do not shorten statutory liability periods or
shift the burden of proof against a Consumer.

## 14. Nature and limits of protection

Privio improves privacy but cannot guarantee complete security. Application locking is not data-at-
rest protection: it mainly covers the visibility and activation of an application's interface, not
its files, databases, caches, exports, backups, system notifications or content accessible through
other software. The Private Vault encrypts only files and notes placed in its image; it does not
encrypt the rest of the disk. FileVault serves the system-disk encryption purpose.

In particular:

- a protected application’s window may be briefly visible while launching before Privio reacts;
- a person with administrator or root access, Terminal access, malware or sufficient skill may stop
  or bypass Privio;
- website protection depends on correct operation of the browser, extension and local proxy;
- macOS notification previews may reveal content from a protected application;
- after the vault is unlocked and mounted, its contents are available to the current user account and
  processes running with that user’s privileges until safe unmounting;
- an open or unsaved file may prevent safe unmounting; Privio does not force an eject that risks data
  corruption;
- loss of both the protected Keychain item and recovery key permanently prevents access to the vault.

The user is responsible for securely retaining the recovery key and a backup of the encrypted image.
Privio is not a substitute for screen lock, a strong password, system updates, backups or FileVault.
The full security model is in [Docs/Security-Model.md](Docs/Security-Model.md).

## 15. Third-party components

Privio includes components provided under separate licenses. The component list and required notices
are in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). Those licenses apply to their respective
components and do not extend rights in Privio’s own code.

## 16. Intellectual property and source code

Rights in Privio, except for third-party components, belong to the Provider. The Privio name, logo,
fingerprint-ridge “P”, application icon and marketing assets are not licensed for unrestricted use.

Privio source code is source-available: it may be inspected and audited and used within the limits of
[LICENSE.md](LICENSE.md). It is not an OSI-approved open-source license.

## 17. Warranties and liability

For Consumers, mandatory rules on conformity of digital content, liability for damage and unfair
contract terms apply. Nothing in these Terms excludes or limits a right that cannot lawfully be
excluded.

For users who are not Consumers, Privio is supplied “as is” and “as available”. To the fullest extent
permitted by law, the Provider disclaims implied warranties and is not liable for lost profits, loss
of data, interruption of business, or indirect or consequential loss arising from use or inability to
use Privio. This limitation does not apply to intentional harm or where limitation is prohibited by
law.

## 18. Complaints and alternative dispute resolution

A complaint may be sent to **kontakt@mintstudio.pl** or to the correspondence address in section 1.
It is helpful to include a description, the macOS and Privio versions, the requested remedy and - for
a purchase complaint - the order or license identifier. Do not send passwords, the complete license
key or unnecessary third-party personal data.

The Provider responds to a Consumer complaint within 14 days of receipt. Where digital content lacks
conformity, remedies are available under section 13 and applicable consumer law.

Consumers may obtain free assistance from Polish municipal or district consumer ombudsmen and may use
an appropriate authorised consumer alternative-dispute-resolution entity. The President of the Polish
Office of Competition and Consumer Protection maintains the entity list. The Provider does not commit
in advance to a particular ADR procedure, but may agree after a dispute arises. The former EU ODR
platform has been discontinued and is not identified as a complaint channel.

## 19. Changes to the Software and Terms

The Provider may develop Privio and amend these Terms for a valid reason such as a change in law,
security, technology, functionality or distribution model. An amendment has no retroactive effect and
does not remove acquired rights.

A material change requires clear notice and renewed acceptance in the application. Where paid digital
content is modified beyond what is necessary to maintain conformity, the modification is made without
additional cost, for a valid reason described above, with any notice on a durable medium and right to
terminate required by law where the modification significantly and adversely affects access or use.

## 20. Duration and termination

The agreement applies from acceptance until the user stops using Privio. The user may terminate it at
any time by uninstalling the Software and ceasing use.

The Provider may terminate the license after a material and culpable breach if the user fails to cure
it within an appropriate period specified in a notice, unless the breach is incapable of cure or
intentional. Termination does not affect statutory Consumer rights or claims accrued earlier.

## 21. Governing law and severability

The agreement is governed by Polish law. This choice does not deprive a Consumer of protection under
mandatory provisions of the country of their habitual residence. Disputes are heard by a court having
jurisdiction under applicable law; these Terms do not impose exclusive jurisdiction on a Consumer.

If a provision is invalid or unenforceable, the remaining provisions continue in effect.

## 22. Related documents

- [PRIVACY.en.md](PRIVACY.en.md) - Privacy Policy;
- [SALES.en.md](SALES.en.md) - direct Pro License sales terms;
- [LICENSE.en.md](LICENSE.en.md) - source-code license translation;
- [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) - third-party licenses;
- [Docs/Security-Model.md](Docs/Security-Model.md) - technical security model.

Copyright © 2026 mintstudio Jakub Koncewicz. All rights reserved except for rights expressly granted
by these Terms and third-party component licenses.
