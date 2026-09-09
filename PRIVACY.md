# Polityka prywatności Privio

Wersja 2.1, obowiązuje od 1 września 2026 r.

Dostępna jest również [wersja angielska](PRIVACY.en.md). W razie rozbieżności wiążąca jest wersja polska.

## 1. Administrator i kontakt

Administratorem danych osobowych otrzymywanych w związku z dystrybucją, sprzedażą i obsługą Privio
jest **mintstudio Jakub Koncewicz**, przedsiębiorca wpisany do CEIDG, NIP 6881285861
(„Administrator”).

- e-mail w sprawach prywatności: **kontakt@mintstudio.pl**;
- adres do korespondencji: **ul. Pełczyńskiego 22A/24, 01-471 Warszawa, Polska**.

Administrator nie wyznaczył inspektora ochrony danych, ponieważ nie zachodzą ustawowe przesłanki
takiego obowiązku.

## 2. Najważniejsza zasada: dane aplikacji pozostają lokalnie

Privio nie wymaga konta i nie zawiera telemetrii, analityki użycia, reklam ani synchronizacji w
chmurze. Administrator nie otrzymuje konfiguracji aplikacji ani danych tworzonych podczas jej
zwykłego działania.

Lokalnie na Macu przechowywane są w szczególności:

- lista chronionych aplikacji i stron oraz ich ustawienia;
- ustawienia ochrony, skrótów, autostartu i języka;
- historia maksymalnie 200 ostatnich zdarzeń ochrony, obejmująca datę, rodzaj zdarzenia, przyczynę,
  nazwę aplikacji i jej identyfikator pakietu;
- informacje o wykrytych instalacjach rozszerzenia przeglądarki;
- klucz Licencji Pro i jej techniczny identyfikator;
- pliki, notatki i metadane umieszczone przez użytkownika w Prywatnym sejfie oraz lokalne ustawienia
  sejfu;
- losowy klucz szyfrowania sejfu chroniony w systemowym Pęku kluczy macOS i klucz odzyskiwania
  wyświetlany użytkownikowi;
- opcjonalne zdjęcia po nieudanym uwierzytelnieniu.

Dane te znajdują się w katalogu danych Privio, ustawieniach aplikacji, pamięci rozszerzenia
przeglądarki albo innych lokalnych magazynach macOS. Nie są przesyłane Administratorowi. Można je
usunąć za pomocą funkcji dostępnych w Privio, przez wyczyszczenie danych rozszerzenia albo ręczne
usunięcie odpowiednich danych lokalnych. Odinstalowanie Privio nie usuwa automatycznie zaszyfrowanego
obrazu sejfu, aby nie spowodować przypadkowej utraty plików.

Prywatny sejf jest obrazem APFS szyfrowanym AES‑256 przez mechanizmy macOS. Privio przekazuje hasło
obrazu do systemowego narzędzia wyłącznie przez standardowe wejście procesu, a nie w argumentach
polecenia ani logach. Odczyt klucza z Pęku kluczy wymaga obecności użytkownika potwierdzonej przez
macOS; Administrator nie otrzymuje hasła konta, danych biometrycznych, klucza szyfrowania, klucza
odzyskiwania ani zawartości sejfu. Po odblokowaniu zawartość jest dostępna lokalnie do odmontowania.

## 3. Opcjonalne zdjęcia po nieudanym uwierzytelnieniu

Funkcja zdjęć jest domyślnie wyłączona. Privio prosi o dostęp do kamery w chwili jej włączania. Po
udzieleniu uprawnienia zdjęcie może zostać wykonane, gdy prompt uwierzytelnienia kończy się bez
odblokowania, również po anulowaniu. Zdjęcie nie jest wykonywane, gdy uwierzytelnienie jest
niedostępne.

Zdjęcia:

- są zapisywane wyłącznie lokalnie w katalogu danych Privio;
- nie są wysyłane Administratorowi ani innym podmiotom przez Privio;
- są dostępne w sekcji Aktywność i mogą zostać usunięte w Ustawieniach;
- są automatycznie ograniczane do 20 najnowszych plików.

Administrator nie ustala celu ani sposobu wykorzystania lokalnych zdjęć i nie ma do nich dostępu.
Zależnie od kontekstu administratorem danych utrwalonych na zdjęciu może być użytkownik, jego
pracodawca albo inny podmiot. Taki podmiot odpowiada za podstawę prawną, obowiązek informacyjny,
retencję i poszanowanie przepisów o ochronie danych, wizerunku, prawie pracy i monitoringu. Funkcja nie
jest przeznaczona do ukrytego monitoringu.

## 4. Rozszerzenie przeglądarki i lokalny proxy

Rozszerzenie Privio potrzebuje uprawnień przeglądarki do kart, nawigacji i adresów stron, aby rozpoznać
chronioną domenę, przekierować zablokowaną nawigację oraz ustalić moment ponownej blokady. Informacje o
chronionych domenach, aktywnej karcie, tymczasowym odsłonięciu i stanie ochrony są wymieniane wyłącznie
między rozszerzeniem a aplikacją przez interfejs loopback pod adresem `127.0.0.1` i mogą być
przechowywane w lokalnej pamięci przeglądarki. Nie są przesyłane Administratorowi.

Lokalny proxy pośredniczy w ruchu wymaganym do egzekwowania ochrony stron. Dla połączeń HTTPS widzi
docelową nazwę hosta i przekazuje zaszyfrowany strumień bez odszyfrowywania treści strony. Zwykły ruch
internetowy nadal trafia do wybranych przez użytkownika stron i ich dostawców na zasadach określonych
w ich politykach prywatności.

## 5. Pobieranie ikon chronionych stron

Po dodaniu strony Privio może bezpośrednio pobrać jej plik `favicon` lub ikonę Apple Touch przez HTTPS,
aby wyświetlić ją w interfejsie. Żądanie jest kierowane wyłącznie do domeny wpisanej przez użytkownika,
a nie do Administratora ani zewnętrznej usługi agregującej ikony. Administrator nie otrzymuje listy
chronionych domen.

Serwer danej strony może otrzymać standardowe dane połączenia, takie jak adres IP, czas żądania,
User-Agent i żądana ścieżka pliku. Administratorem tych danych jest operator odwiedzanej domeny, a
zasady przetwarzania określa jego polityka prywatności.

## 6. Aktualizacje

Po wybraniu „Sprawdź aktualizacje” Privio używa frameworka Sparkle do połączenia z kanałem aktualizacji
HTTPS hostowanym obecnie przez **GitHub, Inc.** Aplikacja może pobrać opis wydania i podpisany pakiet
aktualizacji. Automatyczne sprawdzanie aktualizacji i profilowanie systemu są domyślnie wyłączone.

Privio nie dołącza do żądania klucza ani identyfikatora Licencji Pro, identyfikatorów sprzętu, listy
chronionych aplikacji lub stron, historii aktywności ani zdjęć. GitHub może jednak otrzymać standardowe
dane techniczne niezbędne do połączenia, w szczególności adres IP, czas, User-Agent i żądany plik.

Celem tego przetwarzania jest dostarczenie żądanej aktualizacji i zapewnienie bezpieczeństwa
Oprogramowania. Podstawą prawną po stronie Administratora jest wykonanie umowy lub działanie na żądanie
użytkownika przed jej zawarciem - art. 6 ust. 1 lit. b RODO - oraz prawnie uzasadniony interes w
bezpiecznej dystrybucji i obronie przed nadużyciami - art. 6 ust. 1 lit. f RODO.

## 7. Zakup i obsługa Licencji Pro

Jeżeli Licencja Pro jest kupowana bezpośrednio od Administratora, mogą być przetwarzane:

- imię i nazwisko lub firma nabywcy;
- adres e-mail;
- dane rozliczeniowe i podatkowe podane do dokumentu sprzedaży;
- identyfikator zamówienia, identyfikator licencji, cena, waluta, data i status płatności;
- korespondencja dotycząca zamówienia, zwrotu lub reklamacji.

Celem jest zawarcie i wykonanie umowy, dostarczenie klucza, obsługa płatności, reklamacji i praw
konsumenta, wykonanie obowiązków rachunkowych i podatkowych oraz ustalenie, dochodzenie lub obrona
roszczeń. Podstawami są odpowiednio art. 6 ust. 1 lit. b, c i f RODO.

Płatność i sprzedaż mogą być obsługiwane przez sprzedawcę typu Merchant of Record wskazanego przed
zakupem. Taki podmiot może działać jako odrębny administrator danych płatniczych, podatkowych i
transakcyjnych na zasadach własnej polityki. Administrator nie otrzymuje pełnych danych karty
płatniczej. Zakres danych przekazanych Administratorowi ogranicza się do informacji potrzebnych do
dostarczenia i obsługi licencji. Jeżeli dane trafiają do Administratora od zewnętrznego sprzedawcy,
ich źródłem jest ten sprzedawca, a zakres obejmuje dane zamówienia wskazane powyżej.

## 8. Kontakt, pomoc i reklamacje

Gdy użytkownik kontaktuje się z Administratorem, przetwarzane są dane podane w wiadomości, zwykle adres
e-mail, imię lub nazwa, treść korespondencji i dobrowolnie przekazane informacje techniczne.

Celem jest odpowiedź, pomoc techniczna, obsługa reklamacji i ochrona przed nadużyciami. Podstawą jest
art. 6 ust. 1 lit. b RODO, gdy kontakt dotyczy umowy lub działań przed jej zawarciem, oraz art. 6 ust. 1
lit. f RODO - prawnie uzasadniony interes polegający na prowadzeniu korespondencji, zapewnieniu
bezpieczeństwa i obronie roszczeń.

Nie należy przesyłać haseł, pełnego klucza licencyjnego, zdjęć z funkcji nieudanych prób ani danych
osób trzecich, jeżeli nie są niezbędne do rozwiązania sprawy.

## 9. Odbiorcy danych

W zakresie niezbędnym do wskazanych celów odbiorcami mogą być:

- dostawcy poczty elektronicznej, hostingu i bezpiecznego przechowywania danych;
- GitHub, Inc. jako dostawca infrastruktury kanału aktualizacji;
- operator płatności lub Merchant of Record wskazany przy zakupie;
- dostawcy księgowości, obsługi prawnej i technicznej związani obowiązkiem poufności;
- organy publiczne, jeżeli obowiązek udostępnienia wynika z prawa.

Administrator nie sprzedaje danych osobowych i nie wykorzystuje ich do reklamy behawioralnej.

## 10. Przekazywanie danych poza EOG

GitHub i niektórzy dostawcy mogą przetwarzać dane w Stanach Zjednoczonych lub innych państwach poza
Europejskim Obszarem Gospodarczym. GitHub deklaruje certyfikację w ramach EU-U.S. Data Privacy
Framework, objętego decyzją wykonawczą Komisji Europejskiej (UE) 2023/1795, oraz stosowanie
standardowych klauzul umownych Komisji Europejskiej tam, gdzie są potrzebne. Aktualne informacje i
kopię właściwych zabezpieczeń można uzyskać w polityce prywatności danego dostawcy albo kontaktując
się z Administratorem.

Jeżeli przy zakupie uczestniczy inny podmiot, jego tożsamość, lokalizacja i mechanizm transferu są
przedstawiane w jego polityce prywatności dostępnej przed przekazaniem danych.

## 11. Okresy przechowywania

- Dane aplikacji i rozszerzenia pozostają lokalnie do usunięcia przez użytkownika; historia obejmuje
  maksymalnie 200 wpisów, a zdjęcia maksymalnie 20 plików.
- Zawartość i zaszyfrowany obraz Prywatnego sejfu pozostają lokalnie do ich odrębnego usunięcia przez
  użytkownika; Administrator nie określa ich okresu przechowywania i nie ma do nich dostępu.
- Korespondencja dotycząca umowy, wsparcia i reklamacji jest przechowywana przez czas obsługi sprawy,
  a następnie do upływu właściwego terminu przedawnienia roszczeń lub dłużej, jeżeli wymaga tego
  toczące się postępowanie.
- Dokumentacja transakcyjna i podatkowa jest przechowywana przez okres wymagany przepisami
  rachunkowymi i podatkowymi.
- Dane potrzebne do potwierdzenia uprawnienia z bezterminowej Licencji Pro są przechowywane przez czas
  obowiązywania licencji, a następnie do upływu terminów dochodzenia roszczeń.
- Dane techniczne połączeń przechowywane przez niezależnych dostawców podlegają okresom określonym w
  ich politykach.

Po upływie właściwego okresu dane są usuwane albo anonimizowane, chyba że dalsze przechowywanie jest
wymagane przez prawo lub potrzebne do ustalenia, dochodzenia bądź obrony roszczeń.

## 12. Prawa osób, których dane dotyczą

W granicach przewidzianych przez RODO osobie przysługuje prawo do:

- dostępu do danych i otrzymania ich kopii;
- sprostowania danych;
- usunięcia danych;
- ograniczenia przetwarzania;
- przenoszenia danych przetwarzanych na podstawie zgody lub umowy w sposób zautomatyzowany;
- sprzeciwu wobec przetwarzania opartego na prawnie uzasadnionym interesie;
- cofnięcia zgody w dowolnym momencie, bez wpływu na zgodność wcześniejszego przetwarzania.

Żądanie można wysłać na **kontakt@mintstudio.pl**. Administrator może poprosić o informacje niezbędne
do potwierdzenia tożsamości. Jeżeli dane są przechowywane wyłącznie lokalnie i Administrator ich nie
posiada, prawa wykonuje się za pomocą funkcji aplikacji lub systemu.

Można również wnieść skargę do **Prezesa Urzędu Ochrony Danych Osobowych** albo właściwego organu
nadzorczego w państwie zwykłego pobytu, miejsca pracy lub domniemanego naruszenia.

## 13. Dobrowolność podania danych i decyzje automatyczne

Podanie danych w korespondencji jest dobrowolne, ale brak danych kontaktowych lub informacji
koniecznych do zrozumienia sprawy może uniemożliwić odpowiedź. Dane wymagane w procesie zakupu są
niezbędne do zawarcia i wykonania umowy lub spełnienia obowiązków prawnych; bez nich zakup może nie być
możliwy.

Administrator nie podejmuje wobec użytkowników decyzji wywołujących skutki prawne wyłącznie na
podstawie zautomatyzowanego przetwarzania i nie profiluje użytkowników Privio.

## 14. Bezpieczeństwo

Administrator stosuje środki odpowiednie do charakteru i ryzyka przetwarzania, w tym ograniczenie
zakresu danych, kontrolę dostępu i zabezpieczenia dostawców. Transmisja aktualizacji oraz pobieranie
ikon korzystają z HTTPS. Pakiety aktualizacji są weryfikowane kryptograficznie. Żaden sposób
przetwarzania nie zapewnia jednak bezpieczeństwa absolutnego.

## 15. Pliki cookie

Aplikacja Privio nie używa plików cookie. Strona internetowa, GitHub albo strona sprzedawcy może używać
plików cookie i podobnych technologii zgodnie z własną polityką przedstawioną na danej stronie.

## 16. Zmiany Polityki

Polityka może zostać zmieniona, gdy zmieni się prawo, funkcjonalność, dostawca albo sposób
przetwarzania. Istotna zmiana jest komunikowana w sposób odpowiedni do jej wpływu, a aktualna wersja
pozostaje dostępna w aplikacji i oficjalnym repozytorium. Jeżeli zmiana wymaga zgody, przetwarzanie na
nowych zasadach rozpocznie się dopiero po jej uzyskaniu.
