# Privio — model bezpieczeństwa i granice ochrony

Dokument transparentności. Opisuje **wszystkie** zabezpieczenia Privio, sposób ich działania oraz
ich **granice** — co Privio chroni, a czego **nie**. Wiążące warunki prawne (brak gwarancji,
ograniczenie odpowiedzialności) zawiera [licencja kodu źródłowego](../LICENSE.md); ten dokument tłumaczy je
zwykłym językiem.

## W skrócie (przeczytaj to)

> **Privio zapewnia PODSTAWOWĄ ochronę przed przypadkowym lub nieautoryzowanym dostępem osoby, która
> ma fizyczny dostęp do Twojego odblokowanego Maca** (np. domownik, współpracownik, ktoś kto podejdzie
> do biurka). **Privio NIE jest zabezpieczeniem przed „hakerami"**, zdeterminowanym atakującym,
> złośliwym oprogramowaniem, atakami zdalnymi ani dostępem na poziomie systemu. To wygodna warstwa
> prywatności, a nie zabezpieczenie przed manipulacją w aplikacji lub systemie.
>
> **Żadne zabezpieczenie nie daje 100% pewności.** Skuteczność zależy od Ciebie (silne hasło konta,
> FileVault, aktualny system). Moduły ochrony aplikacji chronią ich **powierzchnię** (okno/aktywację),
> a nie dane —
> do zawartości można próbować dotrzeć **„od drugiej strony"** (bezpośrednio z plików aplikacji; nie
> mamy wpływu na to, jak inne programy zabezpieczają swoje dane), a przy starcie chronionej aplikacji
> możliwy jest **ułamek sekundy** widoczności ekranu, zanim Privio zdąży ją ukryć. **Privio zwiększa
> prywatność, ale nie eliminuje wszystkich sposobów podejrzenia chronionych aplikacji.**

## Zabezpieczenia i ich działanie

| Mechanizm | Jak działa | Chroni przed | Granice / czego NIE robi |
|-----------|-----------|--------------|--------------------------|
| **Ukrycie po aktywacji** | Wykrycie aktywacji chronionej apki (`NSWorkspace`) → natychmiastowe `hide()`, potem żądanie auth | Zerknięciem/otwarciem apki przez osobę przy biurku | Brak API do przechwycenia startu → możliwy **krótki błysk** okna; `hide()` nie jest natychmiastowe ani gwarantowane wobec złośliwej apki |
| **Touch ID / hasło Maca** | `LocalAuthentication` (`LAContext`) oraz `SecAccessControl.devicePasscode` dla trybu Password only | Dostępem bez wybranej metody uwierzytelnienia | Fallback hasła jest konfigurowalny; Password only nie używa Touch ID; mechanizm nie zastępuje logowania do macOS |
| **Secure Enclave** | Klucz w Secure Enclave podpisuje krótkotrwałe wyzwanie jako dowód obecności | Podrobieniem wyniku uwierzytelnienia | Best-effort; przy braku SE spada do wyniku `LocalAuthentication` |
| **Zapasowe hasło macOS** | Opcja „Użyj hasła" → hasło konta systemowego | Sytuacją, gdy Touch ID jest niedostępny | Kto zna hasło konta, ten przejdzie |
| **Blokada po bezczynności** | Timery od utraty fokusu; po czasie lock (opcjonalnie quit) | Pozostawieniem otwartej apki bez nadzoru | Działa w ramach uruchomionego Privio |
| **Blokada po wygaszeniu/uśpieniu** | Nasłuch `screenIsLocked` / sleep → apki wracają zablokowane | Dostępem po odejściu i zablokowaniu ekranu | — |
| **Prywatny sejf** | `hdiutil` tworzy pakiet sparse APFS szyfrowany AES‑256; w podpisanej wersji losowy 256-bitowy klucz jest chroniony w Data Protection Keychain flagą `userPresence`. Lokalny build testowy bez profilu Apple używa systemowego Pęku kluczy i wymusza `LocalAuthentication` przed każdym odczytem. Wolumin jest montowany dopiero po uwierzytelnieniu | Odczytem plików i notatek z obrazu pozostającego w stanie zablokowanym | Po zamontowaniu dane są dostępne dla bieżącego konta i jego procesów; otwarte pliki mogą zatrzymać bezpieczne odmontowanie; nie chroni przed administratorem systemu ani złośliwym oprogramowaniem działającym podczas sesji |
| **Klucz odzyskiwania sejfu** | Ta sama 256-bitowa tajemnica jest jednorazowo pokazana w grupach znaków; jej użycie nadal wymaga lokalnego auth macOS | Utratą chronionego wpisu Keychain | Utrata zarówno Keychain, jak i klucza odzyskiwania jest nieodwracalna; osoba znająca klucz i przechodząca auth macOS może odszyfrować sejf |
| **Zdjęcie po błędnym auth (opcjonalne)** | Po faktycznie nieudanym uwierzytelnieniu kamera zapisuje lokalne zdjęcie; funkcja jest domyślnie wyłączona | Ustaleniem, kto próbował odblokować aplikację | Wymaga jawnej zgody na kamerę; brak zdjęcia po anulowaniu; maksimum 20 zdjęć; może podlegać przepisom o prywatności i monitoringu |
| **Brak stanu „odblokowane" na dysku** | Po starcie wszystko ładuje się jako zablokowane (lock-all-on-launch) | Odczytaniem „odblokowania" po restarcie | — |
| **Autostart (opcjonalny)** | `SMAppService` uruchamia Privio po zalogowaniu, jeśli użytkownik włączy tę opcję | Pozostawieniem ochrony wyłączonej po ponownym logowaniu | Nie uruchamia ponownie procesu po ręcznym `kill`/Force Quit; administrator lub Terminal może zatrzymać aplikację |
| **Ochrona ustawień Privio** | Uwierzytelnienie przed wyłączeniem ochrony, zamknięciem aplikacji i zmianami osłabiającymi zabezpieczenia | Szybkim rozbrojeniem przez osobę przy biurku | Administrator, root lub proces działający z odpowiednimi uprawnieniami może zatrzymać albo obejść Privio |
| **Blokada stron WWW** *(Pro)* | Rozszerzenie Chromium współpracuje z lokalnym proxy; wejście na chronioną domenę wymaga uwierzytelnienia | Przypadkowym lub nieautoryzowanym otwarciem skonfigurowanej strony w obsługiwanej przeglądarce | Zależy od działania rozszerzenia, proxy i konfiguracji przeglądarki; nie obejmuje innych przeglądarek ani dostępu do danych strony poza chronioną nawigacją |
| **Lokalność** | Brak chmury, telemetrii, kont; sekrety w Keychain / Secure Enclave; historia lokalnie | Wyciekiem danych do sieci/chmury | Szyfrowanie obejmuje wyłącznie zawartość Prywatnego sejfu; resztę dysku powinien chronić FileVault |

Zdjęcia nieudanych prób, jeśli funkcja została świadomie włączona, trafiają wyłącznie do
`~/Library/Application Support/Privio/Failed Attempts/`. Katalog i pliki mają uprawnienia tylko dla
właściciela, aplikacja zachowuje 20 najnowszych zdjęć i pozwala usunąć wszystkie w Ustawieniach.
macOS pokazuje standardowy wskaźnik użycia kamery. Użytkownik powinien używać tej funkcji zgodnie z
lokalnymi przepisami i poinformować osoby, jeśli prawo tego wymaga.

## Czego Privio NIE chroni (świadomie poza zakresem)

- **Zdeterminowany atakujący** z dostępem do Twojego konta, hasła lub uprawnień administratora.
- **Złośliwe oprogramowanie, keyloggery, ataki zdalne.**
- **Dostęp na poziomie systemu** (administrator systemowy lub jądro systemu), `kill` albo wymuszone zakończenie z Terminala na odblokowanym Macu.
- **Odczyt danych spoza Prywatnego sejfu** — Privio nie szyfruje plików innych aplikacji ani całego
  dysku. Do ochrony pozostałych danych służy **FileVault**.
- **Odczyt zamontowanego sejfu przez proces bieżącego użytkownika** — po odblokowaniu wolumin zachowuje
  się jak zwykły dysk. Złośliwy proces działający z tymi samymi uprawnieniami może wtedy czytać pliki.
- **Inżynieria wsteczna** — kod jest dostępny do wglądu, więc mechanizmy są znane z założenia.
- **Atak fizyczny na sprzęt** (np. DMA, demontaż).

## Zależności i ograniczenia macOS

- Możliwy **krótki błysk** treści chronionej apki, zanim zostanie ukryta (brak API do przechwycenia
  startu). Minimalizowany, nie wyeliminowany.
- `hide()` nie jest natychmiastowy ani gwarantowany wobec apki, która aktywnie się temu opiera.
- Przywracanie okien po restarcie („Reopen windows…") może na moment pokazać okna, zanim Privio
  wystartuje.

## Ryzyko utraty dostępu — ważne

Privio **celowo blokuje dostęp**. Możesz stracić dostęp, jeśli:
- **czytnik Touch ID** ulegnie awarii,
- utracisz jednocześnie chroniony wpis Keychain i **klucz odzyskiwania Prywatnego sejfu**.

Co to łagodzi po naszej stronie: zależnie od wybranej metody uwierzytelniania może pozostać
**zapasowa możliwość użycia hasła konta macOS**.
Klucz odzyskiwania należy przechowywać poza sejfem, a zaszyfrowany obraz uwzględnić w kopiach
zapasowych. Mimo to **korzystasz na własną odpowiedzialność**; obowiązujące zasady odpowiedzialności
opisuje [Umowa EULA](../EULA.md).

## Zalecenia (ochrona warstwowa)

Privio to jedna warstwa. Dla realnego bezpieczeństwa używaj go **razem z**:
- **FileVault** (szyfrowanie dysku),
- **silnym hasłem konta** i blokadą ekranu z wymogiem hasła,
- **aktualnym systemem macOS**.

## Odpowiedzialność

Oprogramowanie dostarczane jest „tak jak jest", bez gwarancji, a odpowiedzialność Autora jest
ograniczona w najszerszym zakresie dozwolonym prawem — wiążące sformułowania w
[licencji kodu źródłowego](../LICENSE.md) (pkt 6–7). Nie narusza to bezwzględnie obowiązujących praw konsumenta.
