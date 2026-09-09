# Privio - komponenty zewnętrzne i licencje / Third-Party Notices

Stan na 6 września 2026 r. / Current as of 6 September 2026.

Privio (aplikacja macOS i strona **priviolock.com**) korzysta z komponentów firm trzecich
wymienionych poniżej. Ich licencje przytoczono w oryginalnym (angielskim) brzmieniu - to one są
wiążące dla tych komponentów. Ten plik ma charakter informacyjny i **nie zmienia** licencji samego
Privio ([licencja kodu źródłowego](LICENSE.md) / [Umowa EULA](EULA.md) / [EULA (EN)](EULA.en.md)).

Ten sam rejestr obejmuje aplikację i stronę; `Website/NOTICES.md` odsyła do tego pliku. Dodając nową
zależność (w aplikacji lub na stronie), dopisz ją tutaj i utrzymuj teksty aktualnymi.

## Podsumowanie

| Komponent | Wersja | Rola | Gdzie jest dołączony | Licencja |
| --- | --- | --- | --- | --- |
| Sparkle | 2.9.6 | Automatyczne aktualizacje aplikacji | Aplikacja (framework w bundlu) | MIT (+ komponenty wewnętrzne) |
| Nunito | - | Krój całego tekstu interfejsu | Aplikacja i strona (self-host) | SIL OFL 1.1 |
| Font Awesome Free | 6.7.2 | Ikonografia interfejsu | Aplikacja i strona (self-host) | CC BY 4.0 / SIL OFL 1.1 / MIT |
| Frameworki Apple | - | Funkcje systemowe | Część macOS/SDK - nie redystrybuowane | Warunki Apple |

**Zakres - co jest, a czego nie ma:**

- Jedyną zewnętrzną biblioteką linkowaną do aplikacji (wg `Package.resolved`) jest **Sparkle**.
- Weryfikacja licencji Pro używa **CryptoKit (`Curve25519`) z systemu Apple** - Privio **nie**
  dołącza własnej biblioteki kryptograficznej Ed25519. Odrębna implementacja Ed25519 w języku C
  wymieniona niżej jest komponentem *wewnątrz* Sparkle.
- Rozszerzenie przeglądarki dołączone do Privio (`ChromeExtension/`) jest **kodem własnym** - nie
  zawiera pakietów npm, zewnętrznych skryptów, bibliotek CDN ani innego kodu dostawców.
- **Strona nie ładuje żadnych zasobów z zewnętrznych CDN.** Font Awesome i Nunito są
  **self-hostowane** z domeny priviolock.com; strona nie używa Google Fonts ani cdnjs, więc nie
  przekazuje adresów IP odwiedzających do dostawców zewnętrznych (istotne dla RODO).

Pełne teksty licencji krojów są dołączone obok plików czcionek: w aplikacji
`Resources/Fonts/OFL-Nunito.txt` i `Resources/Fonts/LICENSE-FontAwesome.txt`, na stronie
`assets/fonts/OFL-Nunito.txt` i `assets/vendor/fontawesome/LICENSE.txt`. Pliki czcionek zawierają
też osadzone komentarze atrybucyjne, których nie usuwamy.

Frameworki systemowe Apple używane przez Privio to m.in.: **Foundation**, **SwiftUI**, **AppKit**,
**AVFoundation**, **Carbon.HIToolbox**, **CoreGraphics**, **CoreImage**, **CryptoKit**,
**LocalAuthentication**, **Network**, **Observation**, **QuartzCore**, **Security**,
**ServiceManagement**, **UniformTypeIdentifiers** oraz **os**. Są częścią macOS/Apple SDK, nie są
zewnętrznymi bibliotekami redystrybuowanymi przez Privio i podlegają warunkom Apple.

---

## Sparkle (2.9.6) - MIT

Framework automatycznych aktualizacji dla aplikacji macOS, dołączony do aplikacji jako wbudowany
framework (Swift Package Manager). Strona projektu: https://sparkle-project.org -
źródło: https://github.com/sparkle-project/Sparkle

Copyright (c) 2006-2013 Andy Matuschak. Copyright (c) 2009-2013 Elgato Systems GmbH.
Copyright (c) 2011-2014 Kornel Lesiński. Copyright (c) 2015-2017 Mayur Pawashe.
Copyright (c) 2014 C.W. Betts. Copyright (c) 2014 Petroules Corporation.
Copyright (c) 2014 Big Nerd Ranch. All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial
portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

### Komponenty dołączone wewnątrz Sparkle

Sparkle zawiera dodatkowo poniższy kod na własnych licencjach.

**bspatch.c i bsdiff.c - z bsdiff 4.3** (http://www.daemonology.net/bsdiff/):

Copyright 2003-2005 Colin Percival. All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted
providing that the following conditions are met: (1) Redistributions of source code must retain the
above copyright notice, this list of conditions and the following disclaimer. (2) Redistributions in
binary form must reproduce the above copyright notice, this list of conditions and the following
disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING,
BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
SUCH DAMAGE.

**sais.c i sais.h - z sais-lite (2010/08/07)** (https://sites.google.com/site/yuta256/sais):

Copyright (c) 2008-2010 Yuta Mori All Rights Reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial
portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

**Portable C implementation of Ed25519** (https://github.com/orlp/ed25519):

Copyright (c) 2015 Orson Peters <orsonpeters@gmail.com>

This software is provided 'as-is', without any express or implied warranty. In no event will the
authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial
applications, and to alter it and redistribute it freely, subject to the following restrictions:
(1) The origin of this software must not be misrepresented; you must not claim that you wrote the
original software. If you use this software in a product, an acknowledgment in the product
documentation would be appreciated but is not required. (2) Altered source versions must be plainly
marked as such, and must not be misrepresented as being the original software. (3) This notice may
not be removed or altered from any source distribution.

**SUSignatureVerifier.m:**

Copyright (c) 2011 Mark Hamlin. All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted
providing that the following conditions are met: (1) Redistributions of source code must retain the
above copyright notice, this list of conditions and the following disclaimer. (2) Redistributions in
binary form must reproduce the above copyright notice, this list of conditions and the following
disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING,
BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
SUCH DAMAGE.

---

## Nunito - SIL Open Font License 1.1

Krój marki Privio i **całego tekstu interfejsu** - ten sam font w aplikacji i na stronie.
Źródło: Google Fonts - https://fonts.google.com/specimen/Nunito
Tekst licencji: https://scripts.sil.org/OFL

Copyright: „Copyright 2014 The Nunito Project Authors (https://github.com/googlefonts/nunito)".

**Co wolno wg OFL:** używać na stronie oraz **osadzać i dystrybuować w oprogramowaniu** (także
komercyjnym), pod warunkiem dołączenia noty praw autorskich i tekstu licencji oraz niesprzedawania
samego fontu osobno. Plik OFL Nunito **nie deklaruje Reserved Font Name**; niezależnie od tego Privio
fontu nie modyfikuje.

**Zgodność Privio:** dołączamy niezmodyfikowany font zmienny (`Nunito-VariableFont_wght.ttf`,
`Nunito-Italic-VariableFont_wght.ttf`) wraz z pełnym tekstem licencji - w aplikacji
(`Resources/Fonts/OFL-Nunito.txt`) i na stronie (`assets/fonts/OFL-Nunito.txt`, ładowany przez
`@font-face` w `assets/css/styles.css`).

---

## Font Awesome Free (6.7.2) - CC BY 4.0 / SIL OFL 1.1 / MIT

Ikonografia interfejsu aplikacji i strony. Producent: Fonticons, Inc. - https://fontawesome.com
Używamy **wyłącznie wersji Free** - bez ikon i zestawów Pro. W interfejsie i na stronie występują
tylko style dostępne w wersji Free (`solid`, `brands`); dobór ikon zweryfikowano względem metadanych
Font Awesome.

**Gdzie dołączone:**

- **Aplikacja** - niezmodyfikowane pliki czcionek desktop OTF: `FontAwesome6Free-Solid-900.otf`,
  `FontAwesome6Free-Regular-400.otf`, `FontAwesome6Brands-Regular-400.otf` (`Resources/Fonts/`);
  mapowanie ikon → glify jest w `FontAwesomeCatalog.swift`.
- **Strona** - self-hostowany oficjalny build Free (`assets/vendor/fontawesome/`): `css/all.min.css`
  oraz webfonty `webfonts/fa-solid-900.*`, `fa-brands-400.*`, `fa-regular-400.*`. Bez CDN.

**Zakres licencji** (cytaty wprost z pliku LICENSE Font Awesome):

- **Ikony (pliki SVG i JS):** „The Font Awesome Free download is licensed under a Creative Commons
  Attribution 4.0 International License and applies to all icons packaged as SVG and JS file types."
  → **CC BY 4.0** - https://creativecommons.org/licenses/by/4.0/
- **Czcionki (web i desktop font):** „In the Font Awesome Free download, the SIL OFL license applies
  to all icons packaged as web and desktop font files." → **SIL OFL 1.1** - https://scripts.sil.org/OFL
- **Kod (pozostałe pliki):** „In the Font Awesome Free download, the MIT license applies to all
  non-font and non-icon files." → **MIT**

**Atrybucja** (cytat wprost): „Attribution is required by MIT, SIL OFL, and CC BY licenses. Downloaded
Font Awesome Free files already contain embedded comments with sufficient attribution, so you
shouldn't need to do anything additional when using these files normally."

**Znaki towarowe marek** (cytat wprost): „All brand icons are trademarks of their respective owners.
The use of these trademarks does not indicate endorsement of the trademark holder by Font Awesome,
nor vice versa." Ikon z zestawu Brands (np. Apple, GitHub) używamy wyłącznie do oznaczenia danej
firmy/platformy.

**Zgodność Privio:** tylko wersja Free; niezmodyfikowane pliki z zachowanymi komentarzami
licencyjnymi; pełny tekst licencji dołączony obok czcionek (aplikacja:
`Resources/Fonts/LICENSE-FontAwesome.txt`, strona: `assets/vendor/fontawesome/LICENSE.txt`);
atrybucja realizowana przez ten rejestr oraz kredyt „Icons by Font Awesome (Free)" w stopce strony.
