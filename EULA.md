# Privio - umowa licencyjna użytkownika końcowego i regulamin usług elektronicznych

Wersja 11.0, obowiązuje od 1 września 2026 r.

Dostępna jest również [wersja angielska](EULA.en.md). W razie rozbieżności wiążąca jest wersja polska.

Niniejszy dokument określa zasady korzystania z oficjalnej aplikacji Privio oraz, w zakresie mającym
zastosowanie, stanowi regulamin świadczenia usług drogą elektroniczną. Kod źródłowy jest udostępniany
na odrębnych zasadach opisanych w [licencji kodu źródłowego](LICENSE.md).

## Ważne: zakres ochrony Privio

Privio jest dodatkową warstwą ochrony prywatności i dostępu, a nie kompletnym systemem zabezpieczenia
danych komputera. Blokowanie aplikacji działa przede wszystkim na poziomie ich interfejsu - ogranicza
widoczność i możliwość aktywowania chronionych okien. Nie blokuje ani nie szyfruje plików, baz danych,
pamięci podręcznych, eksportów, kopii zapasowych lub innych danych danej aplikacji dostępnych na dysku,
w Finderze, Terminalu albo za pośrednictwem innego programu. Wyjątkiem jest zawartość umieszczona przez
użytkownika w odrębnym Prywatnym sejfie, szyfrowana w zakresie opisanym w pkt 14.

Privio może zmniejszyć ryzyko przypadkowego lub nieautoryzowanego podglądu, lecz żadne oprogramowanie
nie zapewnia 100% ochrony przed dostępem, obejściem zabezpieczeń, złośliwym oprogramowaniem, utratą
danych lub błędem użytkownika. Privio nie zastępuje blokady ekranu macOS, silnego hasła konta,
FileVault, aktualizacji systemu i aplikacji, właściwego zarządzania uprawnieniami, kopii zapasowych ani
fizycznego zabezpieczenia komputera.

Privio chroni powierzchnię aplikacji, a nie dane, które mają one w środku. Nawet przy włączonej ochronie
zaawansowany atakujący, przy odpowiednim wysiłku, może dotrzeć do danych zablokowanych aplikacji „od
środka" - wykorzystując własne luki bezpieczeństwa tych aplikacji lub systemu. Dlatego mimo stosowanych
zabezpieczeń nie należy udostępniać komputera osobom niepożądanym.

Akceptując umowę, użytkownik potwierdza, że przed rozpoczęciem korzystania z Privio otrzymał powyższą
informację i rozumie przeznaczenie oraz techniczne granice Oprogramowania. Potwierdzenie to nie oznacza
zrzeczenia się praw przyznanych Konsumentowi przez bezwzględnie obowiązujące przepisy ani nie wyłącza
odpowiedzialności Usługodawcy w zakresie, w którym prawo nie pozwala jej ograniczyć.

## 1. Usługodawca

Usługodawcą, licencjodawcą i autorem Privio jest **mintstudio Jakub Koncewicz**, przedsiębiorca
wpisany do Centralnej Ewidencji i Informacji o Działalności Gospodarczej, NIP 6881285861
(„Usługodawca”).

- kontakt elektroniczny: **kontakt@mintstudio.pl**;
- adres do korespondencji i reklamacji: **ul. Pełczyńskiego 22A/24, 01-471 Warszawa, Polska**.

Powyższy adres jest adresem do doręczeń. Usługodawca nie ma stałego miejsca wykonywania działalności.
Świadczenie usług objętych niniejszym dokumentem nie wymaga od Usługodawcy szczególnego zezwolenia.

## 2. Zawarcie umowy i dostępność warunków

Umowa zostaje zawarta, gdy użytkownik zaakceptuje jej treść w aplikacji. Brak akceptacji powoduje
zamknięcie aplikacji. Użytkownik powinien zapisać kopię dokumentu; jego aktualna wersja jest stale
dostępna w aplikacji w sekcji „O programie” oraz w oficjalnym repozytorium Privio.

Osoba korzystająca z Privio w imieniu organizacji oświadcza, że jest uprawniona do związania tej
organizacji niniejszą umową. Osoba niepełnoletnia może korzystać z Privio wyłącznie w zakresie, w
którym może skutecznie zawrzeć umowę zgodnie z właściwym prawem albo za zgodą przedstawiciela
ustawowego.

## 3. Definicje

- **Privio** lub **Oprogramowanie** - aplikacja Privio na macOS wraz z dołączonym rozszerzeniem
  przeglądarki, zasobami i dokumentacją.
- **Oficjalny Build** - wersja zbudowana i udostępniona przez Usługodawcę oficjalnym kanałem
  dystrybucji.
- **Funkcje Darmowe** - funkcje, które nie są oznaczone jako Pro.
- **Funkcje Pro** - funkcje oznaczone jako Pro, w szczególności ochrona stron internetowych.
- **Licencja Pro** - podpisany kryptograficznie klucz odblokowujący Funkcje Pro.
- **Konsument** - osoba fizyczna dokonująca czynności niezwiązanej bezpośrednio z jej działalnością
  gospodarczą lub zawodową. Postanowienia dotyczące Konsumenta stosuje się także do osoby fizycznej,
  której właściwe przepisy przyznają w danym zakresie prawa konsumenta.

## 4. Licencja na Oficjalny Build

Usługodawca udziela użytkownikowi niewyłącznej licencji na instalowanie i używanie Oficjalnego Buildu
na komputerach Mac należących do użytkownika albo używanych przez niego za zgodą właściciela.

Funkcje Darmowe mogą być używane bez opłat do celów osobistych, zawodowych i wewnętrznych celów
organizacji. Funkcje Pro wymagają ważnej Licencji Pro. Licencja nie przenosi praw własności
intelektualnej do Privio i, z zastrzeżeniem praw bezwzględnie obowiązujących, nie może być przenoszona,
odsprzedawana ani sublicencjonowana.

## 5. Rodzaj i zakres usług elektronicznych

Privio udostępnia następujące usługi i funkcje:

- lokalne konfigurowanie i egzekwowanie ochrony wybranych aplikacji;
- lokalną Zasłonę prywatności i funkcje chwilowego odsłaniania;
- lokalny Prywatny sejf: szyfrowany obraz APFS na pliki i notatki, odblokowywany mechanizmami
  uwierzytelniania macOS albo kluczem odzyskiwania po dodatkowym uwierzytelnieniu;
- lokalną historię zdarzeń ochrony;
- opcjonalną ochronę stron w obsługiwanych przeglądarkach Chromium z użyciem rozszerzenia Privio i
  lokalnego serwera proxy;
- lokalną weryfikację i przechowywanie Licencji Pro;
- ręczne sprawdzanie i pobieranie aktualizacji z podpisanego kanału aktualizacji;
- opcjonalne wykonywanie lokalnych zdjęć po nieudanym lub anulowanym uwierzytelnieniu.

Podstawowe funkcje ochronne działają lokalnie i nie wymagają konta. Połączenie z Internetem jest
potrzebne do pobrania aplikacji, sprawdzenia aktualizacji, pobrania ikon chronionych stron oraz do
normalnego korzystania ze stron internetowych. Szczegóły przetwarzania danych opisuje
[Polityka prywatności](PRIVACY.md).

Użytkownik może zakończyć korzystanie z usług w każdej chwili przez wyłączenie odpowiedniej funkcji,
usunięcie danych w aplikacji albo odinstalowanie Privio. Odinstalowanie aplikacji nie usuwa
automatycznie obrazu Prywatnego sejfu; użytkownik usuwa go odrębnie po wykonaniu potrzebnej kopii.
Usunięcie licencji z aplikacji nie anuluje
praw wynikających z jej zakupu, ale wyłącza Funkcje Pro na danym urządzeniu do czasu ponownego
wprowadzenia ważnego klucza.

## 6. Wymagania techniczne, kompatybilność i interoperacyjność

Oficjalny Build wymaga kompatybilnego komputera Mac z systemem **macOS 14 lub nowszym** oraz miejsca
na instalację i dane lokalne. Uwierzytelnianie wykorzystuje mechanizmy macOS i, zależnie od sprzętu i
konfiguracji, może używać Touch ID albo hasła konta macOS.

Prywatny sejf wymaga systemu plików APFS, narzędzi obrazów dysku dostarczanych z macOS oraz dodatkowego
miejsca odpowiadającego przechowywanym danym. Obraz ma pojemność logiczną określoną przy utworzeniu,
ale jako pakiet sparse zajmuje na dysku przestrzeń rosnącą wraz z zawartością.

Wybrane funkcje wymagają nadania uprawnień wskazanych przez macOS, w tym dostępu do kamery dla
opcjonalnych zdjęć. Ochrona stron wymaga aktualnej, obsługiwanej przeglądarki Chromium, rozszerzenia
Privio oraz zgody na lokalną konfigurację proxy. Obecnie rozszerzenie jest przeznaczone dla Google
Chrome, Microsoft Edge, Brave, Opera i Vivaldi. Zmiany w macOS lub przeglądarce mogą przejściowo
ograniczyć kompatybilność do czasu udostępnienia aktualizacji.

## 7. Licencja Pro

Licencja Pro jest weryfikowana wyłącznie lokalnie za pomocą podpisu Ed25519. Privio nie tworzy konta,
nie aktywuje licencji online, nie stosuje identyfikatora sprzętowego i nie wysyła klucza ani
identyfikatora licencji do Usługodawcy.

Licencja Pro jest przypisana do jej nabywcy w modelu „per user”. Osoba fizyczna może
używać jej na swoich komputerach Mac. Organizacja potrzebuje odrębnego uprawnienia dla każdego
użytkownika Funkcji Pro, chyba że oferta zakupu wyraźnie stanowi inaczej. Klucz może być przechowywany
lokalnie w katalogu danych Privio. Reinstalacja i aktualizacja aplikacji nie unieważniają ważnego
klucza.

Nie wolno korzystać z Funkcji Pro bez ważnej Licencji Pro, w tym przez obejście, wyłączenie albo
modyfikację mechanizmu licencyjnego. Techniczna możliwość zmiany jawnego kodu nie stanowi zezwolenia.
Zakaz ten nie ogranicza uprawnień, których nie można wyłączyć umową, w szczególności ustawowych praw
do obserwowania, badania lub testowania działania programu oraz do interoperacyjności.

## 8. Zakup Licencji Pro

Jeżeli Licencja Pro jest oferowana odpłatnie, szczegóły transakcji określa
[Warunki sprzedaży bezpośredniej](SALES.md) oraz informacje przedstawione bezpośrednio przed złożeniem zamówienia. Cena
całkowita, podatki, waluta, sposób płatności, zakres licencji, dane sprzedawcy i sposób dostarczenia są
pokazywane przed powstaniem obowiązku zapłaty.

Sprzedaż może prowadzić Usługodawca albo wskazany przy zakupie zewnętrzny sprzedawca typu Merchant of
Record. Jeżeli sprzedawcą jest taki podmiot, odpowiada on za płatność, fakturę, podatki, odstąpienie i
zwrot na zasadach przedstawionych w jego procesie zakupu. EULA nadal reguluje sposób korzystania z
Privio.

## 9. Prawo odstąpienia

Konsument zawierający umowę na odległość ma co do zasady 14 dni na odstąpienie bez podania przyczyny.
W przypadku odpłatnej treści cyfrowej niedostarczanej na materialnym nośniku prawo to może wygasnąć
po rozpoczęciu dostarczania przed upływem 14 dni tylko wtedy, gdy Konsument uprzednio wyraził wyraźną
zgodę, przyjął do wiadomości utratę prawa odstąpienia, a sprzedawca przekazał potwierdzenie umowy i
zgody na trwałym nośniku. Brak spełnienia tych warunków nie pozbawia Konsumenta ustawowego prawa.

## 10. Zasady prawidłowego korzystania

Użytkownik jest zobowiązany:

- korzystać z Privio zgodnie z prawem, niniejszą umową i prawami osób trzecich;
- nie dostarczać za pomocą usług Privio treści bezprawnych;
- nie używać funkcji kamery do ukrytego albo bezprawnego monitoringu;
- nie rozpowszechniać Oficjalnego Buildu ani jego zmodyfikowanych binariów poza oficjalnym kanałem;
- nie sprzedawać, wynajmować ani sublicencjonować Oprogramowania;
- nie usuwać informacji o prawach autorskich i licencjach;
- nie używać nazwy, logo ani znaków Privio w sposób sugerujący nieistniejące powiązanie lub aprobatę.

Ograniczenia dotyczą praw Usługodawcy do Privio i nie zmieniają licencji komponentów zewnętrznych.

## 11. Prywatność i dane lokalne

Privio nie zawiera telemetrii, analityki reklamowej ani synchronizacji w chmurze. Konfiguracja, lista
chronionych aplikacji i stron, historia aktywności, klucz licencji, zdjęcia oraz zawartość Prywatnego
sejfu pozostają lokalnie na Macu. Usługodawca nie ma do nich dostępu. Wyjątki związane z połączeniami sieciowymi, kontaktem i
zakupem opisuje [Polityka prywatności](PRIVACY.md).

## 12. Opcjonalne zdjęcia po nieudanym uwierzytelnieniu

Funkcja jest domyślnie wyłączona. Jej włączenie wymaga świadomej decyzji użytkownika i uprawnienia
kamery w macOS. Po włączeniu Privio może wykonać zdjęcie, gdy prompt uwierzytelnienia kończy się bez
odblokowania, również po anulowaniu. Zdjęcie nie jest wykonywane, gdy uwierzytelnienie jest
niedostępne. Privio przechowuje lokalnie maksymalnie 20 najnowszych zdjęć; użytkownik może je
przeglądać i usuwać w aplikacji.

Użytkownik samodzielnie odpowiada za ustalenie podstawy prawnej, spełnienie obowiązku informacyjnego i
zgodność użycia tej funkcji z przepisami o ochronie danych, wizerunku, prawie pracy i monitoringu.
Uprawnienie systemowe do kamery nie zastępuje tych obowiązków. Funkcja nie jest przeznaczona do
niejawnej obserwacji pracowników, domowników ani innych osób.

## 13. Aktualizacje i zgodność treści cyfrowej

Aktualizacje są sprawdzane za pośrednictwem Sparkle po wybraniu przez użytkownika polecenia „Sprawdź
aktualizacje”. Produkcyjne pakiety aktualizacji powinny być podpisane kryptograficznie, podpisane
certyfikatem Developer ID i notaryzowane przez Apple. Buildy deweloperskie mogą nie mieć tych cech i
nie są przeznaczone do publicznej dystrybucji.

Konsument otrzymuje aktualizacje, w tym aktualizacje bezpieczeństwa, wymagane przez bezwzględnie
obowiązujące przepisy w okresie, którego może rozsądnie oczekiwać, biorąc pod uwagę rodzaj i cel
Privio oraz okoliczności umowy. Użytkownik powinien instalować udostępnione aktualizacje w rozsądnym
terminie. Brak instalacji aktualizacji, o której dostępności i skutkach zaniechania użytkownik został
prawidłowo poinformowany, może mieć skutki przewidziane prawem.

Konsument zachowuje ustawowe prawa dotyczące dostarczenia i zgodności treści cyfrowej, w tym - gdy
spełnione są przesłanki ustawowe - prawo żądania doprowadzenia do zgodności, obniżenia ceny albo
odstąpienia od umowy. Niniejsza umowa nie skraca ustawowych okresów odpowiedzialności ani nie zmienia
ciężaru dowodu na niekorzyść Konsumenta.

## 14. Charakter i granice ochrony

Privio zwiększa prywatność, ale nie gwarantuje pełnego bezpieczeństwa. Blokada aplikacji nie jest
blokadą danych w spoczynku: chroni przede wszystkim widoczność i aktywację interfejsu, a nie pliki,
bazy danych, pamięci podręczne, eksporty, kopie zapasowe, powiadomienia systemowe ani zawartość
dostępną przez inne programy. Prywatny sejf szyfruje wyłącznie pliki i notatki umieszczone w jego
obrazie; nie szyfruje pozostałej części dysku. Do szyfrowania dysku systemowego służy FileVault.

W szczególności:

- przy uruchamianiu chronionej aplikacji jej okno może być krótko widoczne, zanim Privio zareaguje;
- osoba z uprawnieniami administratora, dostępem root, Terminalem, złośliwym oprogramowaniem albo
  odpowiednimi umiejętnościami może zatrzymać lub obejść Privio;
- ochrona stron zależy od poprawnego działania przeglądarki, rozszerzenia i lokalnego proxy;
- podglądy powiadomień macOS mogą ujawniać treść chronionej aplikacji;
- po odblokowaniu i zamontowaniu sejfu jego zawartość jest dostępna dla bieżącego konta użytkownika i
  działających z jego uprawnieniami procesów aż do bezpiecznego odmontowania;
- otwarty lub niezapisany plik może uniemożliwić bezpieczne odmontowanie; Privio nie wymusza
  odmontowania grożącego uszkodzeniem danych;
- utrata chronionego wpisu Pęku kluczy oraz klucza odzyskiwania oznacza trwałą utratę dostępu do
  zawartości sejfu.

Użytkownik odpowiada za bezpieczne przechowanie klucza odzyskiwania i kopii zapasowej zaszyfrowanego
obrazu. Privio nie zastępuje blokady ekranu, silnego hasła, aktualizacji systemu, kopii zapasowych ani
FileVault. Pełny opis modelu bezpieczeństwa znajduje się w
[Modelu bezpieczeństwa](Docs/Security-Model.md).

## 15. Komponenty zewnętrzne

Privio zawiera komponenty udostępniane na odrębnych licencjach. Ich wykaz i wymagane noty znajdują się
w [informacjach o komponentach zewnętrznych](THIRD-PARTY-NOTICES.md). Licencje tych komponentów obowiązują w odniesieniu
do nich i nie rozszerzają praw do kodu własnego Privio.

## 16. Własność intelektualna i kod źródłowy

Prawa do Privio, z wyjątkiem komponentów zewnętrznych, należą do Usługodawcy. Nazwa „Privio”, logo,
znak „P” z linii papilarnych, ikona aplikacji i materiały marketingowe nie są udzielane do swobodnego
użytku.

Kod źródłowy Privio jest dostępny do wglądu: można go przeglądać i audytować oraz korzystać z niego w
granicach [licencji kodu źródłowego](LICENSE.md). Nie jest to licencja open source zatwierdzona przez OSI.

## 17. Gwarancje i odpowiedzialność

Wobec Konsumentów zastosowanie mają bezwzględnie obowiązujące przepisy o zgodności treści cyfrowych,
odpowiedzialności za szkodę i niedozwolonych postanowieniach umownych. Żadne postanowienie umowy nie
wyłącza ani nie ogranicza praw, których nie można skutecznie wyłączyć.

Wobec użytkowników niebędących Konsumentami Privio jest dostarczane „tak jak jest” i „w miarę
dostępności”. W najszerszym zakresie dozwolonym przez prawo Usługodawca nie udziela dorozumianych
gwarancji i nie odpowiada za utracone korzyści, utratę danych, przerwy w działalności ani szkody
pośrednie lub następcze wynikające z używania albo niemożności używania Privio. Ograniczenie nie
dotyczy szkód wyrządzonych umyślnie ani przypadków, w których prawo zakazuje ograniczenia
odpowiedzialności.

## 18. Reklamacje i pozasądowe rozwiązywanie sporów

Reklamację można wysłać na **kontakt@mintstudio.pl** albo na adres korespondencyjny z pkt 1. Warto
podać opis problemu, wersję macOS i Privio, oczekiwany sposób rozwiązania oraz - jeżeli reklamacja
dotyczy zakupu - identyfikator zamówienia lub licencji. Nie należy przesyłać haseł, pełnego klucza
licencyjnego ani niepotrzebnych danych osób trzecich.

Usługodawca odpowiada na reklamację Konsumenta w terminie 14 dni od jej otrzymania. Jeżeli treść
cyfrowa jest niezgodna z umową, środki ochrony przysługują na zasadach wskazanych w pkt 13 i przepisach
ustawy o prawach konsumenta.

Konsument może uzyskać bezpłatną pomoc m.in. u miejskiego lub powiatowego rzecznika konsumentów oraz
skorzystać z właściwego podmiotu uprawnionego do pozasądowego rozwiązywania sporów konsumenckich.
Wykaz podmiotów prowadzi Prezes UOKiK. Usługodawca nie zobowiązuje się z góry do udziału w konkretnym
postępowaniu pozasądowym; może wyrazić na nie zgodę po powstaniu sporu. Unijna platforma ODR została
zamknięta i nie jest wskazywana jako kanał składania skarg.

## 19. Zmiany Oprogramowania i warunków

Usługodawca może rozwijać Privio oraz zmieniać niniejsze warunki z ważnej przyczyny, takiej jak zmiana
prawa, bezpieczeństwa, technologii, funkcjonalności albo modelu dystrybucji. Zmiana nie działa wstecz i
nie pozbawia praw nabytych.

Istotna zmiana warunków wymaga wyraźnego poinformowania i ponownej akceptacji w aplikacji. Jeżeli
odpłatna treść cyfrowa ma być zmieniona w sposób wykraczający poza zachowanie jej zgodności, zmiana
następuje bez dodatkowych kosztów, z ważnej przyczyny opisanej wyżej i z zachowaniem wymaganych prawem
informacji na trwałym nośniku oraz prawa do wypowiedzenia, gdy zmiana istotnie i negatywnie wpływa na
dostęp lub korzystanie.

## 20. Czas trwania i rozwiązanie

Umowa obowiązuje od akceptacji do zakończenia korzystania z Privio. Użytkownik może ją rozwiązać w
każdej chwili przez odinstalowanie Oprogramowania i zaprzestanie korzystania.

Usługodawca może wypowiedzieć licencję po istotnym, zawinionym naruszeniu warunków, jeżeli użytkownik
nie usunie naruszenia w odpowiednim terminie wskazanym w wezwaniu, chyba że naruszenie jest
nieusuwalne albo umyślne. Rozwiązanie nie narusza ustawowych praw Konsumenta ani roszczeń powstałych
wcześniej.

## 21. Prawo właściwe i rozdzielność postanowień

Umowa podlega prawu polskiemu. Wybór prawa nie pozbawia Konsumenta ochrony przyznanej przez przepisy,
których nie można wyłączyć umową, obowiązujące w państwie jego zwykłego pobytu. Spory rozstrzyga sąd
właściwy według przepisów prawa; umowa nie narzuca Konsumentowi wyłącznej właściwości sądu.

Jeżeli postanowienie okaże się nieważne lub niewykonalne, pozostałe postanowienia pozostają w mocy.

## 22. Dokumenty powiązane

- [Polityka prywatności](PRIVACY.md);
- [Warunki bezpośredniej sprzedaży Licencji Pro](SALES.md);
- [Licencja kodu źródłowego](LICENSE.md);
- [Informacje o komponentach zewnętrznych](THIRD-PARTY-NOTICES.md);
- [Techniczny model bezpieczeństwa](Docs/Security-Model.md).

Copyright © 2026 mintstudio Jakub Koncewicz. Wszelkie prawa zastrzeżone, z wyjątkiem praw wyraźnie
udzielonych w niniejszej umowie i licencjach komponentów zewnętrznych.
