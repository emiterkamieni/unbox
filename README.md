# Debox

Aplikacja w pasku menu macOS, która pokazuje foldery i pliki oznaczone w Box Drive jako dostępne offline i pozwala je odznaczać.

- Ikona chmurki w pasku menu z liczbą elementów offline.
- Lista pogrupowana według folderów najwyższego poziomu (klientów), z miejscem zajmowanym na dysku.
- Sortowanie (ikona ⇅): według nazwy (A–Z) albo rozmiaru (od największych). Dotyczy grup i elementów w grupach, a wybór jest zapamiętywany.
- Odznacz pole i kliknij **Zastosuj**: element przechodzi w tryb „tylko online”, a pobrane pliki są usuwane z dysku. W Finderze nadal są widoczne i pobiorą się przy otwarciu.
- Ustawienia (ikona zębatki): uruchamianie przy logowaniu, usuwanie plików po odznaczeniu, częstotliwość odświeżania.

## Budowanie

Wystarczą Command Line Tools (Xcode nie jest potrzebny).

```bash
scripts/build.sh            # buduje build/Debox.app i build/debox-cli
scripts/build.sh --install  # dodatkowo instaluje do /Applications i uruchamia
```

## Narzędzie wiersza poleceń

```bash
build/debox-cli list --sizes             # co jest offline i ile zajmuje
build/debox-cli status <ścieżka>         # stan elementu
build/debox-cli unmark <ścieżka>         # tylko online + zwolnienie miejsca
build/debox-cli unmark <ścieżka> --keep-local
build/debox-cli mark <ścieżka>           # oznacz offline (diagnostyka)
```

## Jak to działa

- **Odczyt**: Box zapisuje oznaczenia offline w swojej bazie `~/Library/Application Support/Box/Box/data/streemfs.db`. Box blokuje ją na wyłączność, więc Debox kopiuje bazę razem z dziennikiem WAL do katalogu tymczasowego i czyta tylko kopię. Każdy wynik jest potwierdzany w macOS. Jeśli Box zmieni format bazy, Debox przegląda pobrane foldery przez macOS (wolniej).
- **Odznaczanie**: Debox wywołuje akcję Boxa `UnmarkForOffline`, tę samą co „Make Available Online Only” w Finderze. Robi to przez wewnętrzne klasy frameworka FileProvider, bo macOS nie ma do tego publicznego API.
- **Zwalnianie miejsca**: publiczne `FileManager.evictUbiquitousItem` (odpowiednik „Usuń pobrane” w Finderze). macOS nie usuwa plików ze zmianami, których jeszcze nie wysłano do Box.
- Debox nigdy nie zapisuje niczego do plików Boxa i sam nie pobiera plików z chmury (blokada `IOPOL_MATERIALIZE_DATALESS_FILES_OFF`).

## Ograniczenia

- Aktualizacja macOS może zmienić wewnętrzne API FileProvider. Wtedy Debox pokaże komunikat i nadal będzie wyświetlał listę, a odznaczać trzeba będzie w Finderze.
- Box Drive musi działać, żeby dało się zmieniać oznaczenia.
- Narzędzie do użytku prywatnego (podpis ad-hoc, nie nadaje się do App Store).
