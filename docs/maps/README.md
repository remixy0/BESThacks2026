# Mapa nawigacyjna 2D — Field Museum

Gotowy plik: `backend/java-backend/src/main/resources/maps/field-museum-main-level.grid.json`.
Jest samodzielnym plikiem JSON do odczytu w Javie i Swift: zawiera siatkę,
układ współrzędnych, pomieszczenia, drzwi oraz punkty zainteresowania.
Nie wymaga modeli 3D do używania w aplikacji. Rozmiar: około 775 kB.

## Siatka

- **1066 kolumn × 681 wierszy = 725 946 komórek**.
- Każda komórka reprezentuje **0,20 × 0,20 m**.
- `cells` to tablica wierszy zapisanych jako ciągi znaków. Odczyt:
  `cells[row][column]`; w Javie: `cells.get(row).charAt(column)`.
- Do przechodzenia dopuszczony jest wyłącznie znak **`'1'`**.

| Kod | Znaczenie |
|---|---|
| `0` | Poza podłogą / budynkiem |
| `1` | Przestrzeń dostępna do wyznaczania trasy |
| `2` | Przeszkoda wynikająca z geometrii modelu |
| `3` | Pomieszczenie zamknięte lub tylko dla personelu |
| `4` | Margines przy przeszkodzie lub granicy |
| `5` | Wolna przestrzeń odłączona od głównej części mapy |

## Współrzędne z iOS i WebSocketu

Jednostki to metry. Początek układu świata pozostaje w tym samym miejscu co
w dostarczonym modelu 3D, przy środku budynku:

```text
map.x = model.X
map.y = model.Z
```

Wysokość `model.Y` nie trafia do mapy. Dodatnie `x` biegnie w przybliżeniu na
wschód, dodatnie `y` na południe. Wiersze rosną od góry do dołu, kolumny od
lewej do prawej. Model ma już zastosowany obrót z danych źródłowych; nie
obracaj współrzędnych ponownie.

Pozycja powinna zostać przeliczona do układu **modelu muzeum**, zanim aplikacja
wyśle `{ "x": ..., "y": ... }` do istniejącego `/ws/position`.
Surowe współrzędne ARKit odnoszą się do początku sesji AR — wymagają ustalenia
przesunięcia i obrotu względem modelu, np. za pomocą znanego punktu/markera.
Samo zamienienie nazwy osi Z na Y nie wykonuje tej kalibracji.

`origin` w JSON oznacza narożnik siatki, a nie nowe zero pozycji użytkownika:

```text
origin.x = -106.6 m
origin.y = -68.2 m

column = floor((x - origin.x) / 0.2)
row    = floor((y - origin.y) / 0.2)

x środka kratki = origin.x + (column + 0.5) * 0.2
y środka kratki = origin.y + (row + 0.5) * 0.2
```

Użyj `floor`, a nie obcięcia liczby do zera, szczególnie dla współrzędnych
ujemnych. Sprawdź skończoność liczb i zakresy indeksów przed odczytem siatki.
Zakres mapy: `-106.6 <= x < 106.6`, `-68.2 <= y < 68.0`.
Pozycja poza mapą lub w zablokowanej komórce wymaga obsługi błędu/ponownego
ustalenia lokalizacji. Nie należy automatycznie przenosić jej przez ścianę.

## Pathfinding

Siatka jest przygotowana do BFS, Dijkstry lub A* z czterema sąsiadami:
góra, dół, lewo, prawo. Przejście kosztuje 0,2 m; heurystyka A* to odległość
Manhattan pomnożona przez 0,2 m. Ruch po przekątnej jest wyłączony, więc trasa
nie przecina narożników przeszkód. Trasa powinna łączyć środki komórek.

POI zawiera dwie różne pozycje:

- `position`: punkt oryginalnego eksponatu/udogodnienia, często wewnątrz obiektu.
- `approach`: automatycznie wybrana dostępna komórka podejścia, będąca celem
  pathfindingu. Wybierana jest w tej samej strefie/pomieszczeniu i maksymalnie
  6 m od kotwicy; przed użyciem w oprowadzaniu warto zatwierdzić stronę oglądania.

`approach: null` oznacza niedostępny cel; powód zapisano w `unavailableReason`.
Z 25 POI dostępne są 23. **Pawnee Earth Lodge i Mastaba** znajdują się w
pomieszczeniach `closed` według dostarczonego JSON i pozostają zablokowane.
Schody i windy są wyłącznie punktami na tym piętrze, bez połączeń między piętrami.

`doors` przechowuje metadane drzwi; o przejściu decyduje siatka z rzeczywistej
geometrii modelu. `sourceConnects` zachowuje nazwy źródłowe, które nie zawsze
są unikalnymi identyfikatorami pomieszczeń — nie należy traktować ich jako grafu.

Plik `example-route.json` zawiera zweryfikowaną trasę testową od punktu startu
zwiedzania do Tsavo Lions (154 m w siatce czterokierunkowej). To przykład danych,
nie osobny endpoint. Backend wczytuje mapę przy starcie i obsługuje nawigację
przez istniejący WebSocket. Protokół opisano w
`backend/java-backend/NAVIGATION.md`. Algorytm szuka ścieżki po czterech
sąsiadach, następnie usuwa zbędne punkty, sprawdzając przechodniość całych
odcinków. Takie bezpieczne odcinki mogą mieć dowolny kąt względem siatki.

## Jak powstała mapa

Odczytano **790 siatek i 352 454 trójkąty** bezpośrednio z głównego modelu USDZ.
Kod z archiwum przeanalizowano w celu sprawdzenia skali i konwencji modelu;
nie wykonywano go. Modele `Artifacts/` są wariantami detali tych samych
eksponatów; użyto ich już ustawionych kopii z modelu całego piętra.

1. Podłoga określa dostępny obrys.
2. Po transformacjach obiektów trójkąty są przycinane do zakresu wysokości
   **0,02–1,90 m** i rzutowane na płaszczyznę X–Z. Dzięki temu uwzględnione
   są ściany, kolumny, meble, gabloty, szkło i nisko wiszące przeszkody;
   sufity i wysokie nadproża nie zamykają przejść.
3. Raster pomocniczy ma piksele 5 cm. Komórka 20 cm zajęta choć częściowo
   przez raster przeszkody zostaje zablokowana. Podłoga musi pokrywać całą komórkę.
4. Dodano strefy zamknięte oraz konserwatywny margines dla pieszego o promieniu
   **0,30 m**, powiększony o niepewność położenia w komórkach. Wąskie przejścia
   mogą przez to zostać odrzucone. Nie jest to certyfikacja dostępności dla wózków.
5. Pozostawiono największą spójną przestrzeń do przechodzenia. W tej wersji
   po dodaniu marginesu nie pozostały inne odłączone wolne komponenty.

To mapa zgodna z **dostarczoną rekonstrukcją proceduralną**, a nie pomiarem
rzeczywistego muzeum. Źródłowy README wskazuje, że ściany, drzwi i umeblowanie
są przybliżone. Po otrzymaniu zmian w modelu plik należy wygenerować ponownie.

## Podglądy i weryfikacja

- `field-museum-grid.png`: cały rzut i legenda.
- `field-museum-grid-detail.png`: powiększenie z widocznymi kratkami 20 cm.
- `field-museum-route-preview.png`: przykładowa trasa.
- `generation-report.json`: liczności, audyt geometrii i niedostępne POI.
- `validation-report.json`: sprawdzenie pliku, współrzędnych i 23 tras.

Walidacja odczytuje gotowy JSON i niezależnie wyznacza ścieżki BFS. Sprawdzono
spójność wszystkich 387 439 dostępnych komórek, 2043 przeliczenia współrzędnych,
trasy do 23 punktów i brak przechodzenia przez zablokowane komórki. Pięć testów
jednostkowych sprawdza transformacje 3D, wykluczanie nadproży, przycinanie ścian,
margines oraz brak przejścia przez narożniki.

## Ponowne generowanie

Uruchamiaj z katalogu głównego repozytorium. Rozpakuj `resources.rar` do
`map-work`, tak aby zawierał katalog `resources`. Ten katalog wejściowy jest
ignorowany przez Git; archiwum źródłowe nie jest modyfikowane.

```sh
python -m pip install -r tools/maps/requirements.txt
python tools/maps/build_grid.py --source map-work/resources
python tools/maps/test_build_grid.py
python tools/maps/validate_grid.py
```

Czytnik USD obsługuje konkretny tekstowy format emitowany przez dostarczony
generator: trójkąty i transformacje translate/rotateY/scale. Nie jest ogólnym
importerem wszystkich formatów i funkcji USD.

## Uznanie autorstwa

Floor-plan data © 2020 Field Museum of Natural History, **CC BY 4.0**.
Źródło wskazane w dostarczonych plikach:
https://github.com/arcataroger/openlayers_indoor_map.
Mapa 2D została przekształcona z dostarczonego modelu 3D.
Zachowaj informację o autorstwie w aplikacji, np. na ekranie „O aplikacji”.
