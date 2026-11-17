<p align="center">
  <img src="Support/AppIcon.iconset/icon_256x256.png" width="128" alt="Ikona unbox">
</p>

# unbox

**Zobacz, co Box Drive trzyma offline na Twoim Macu – i zwolnij miejsce jednym kliknięciem.**

Box Drive pozwala oznaczać foldery i pliki jako *dostępne offline*, ale nigdzie nie pokazuje ich listy.
unbox działa w pasku menu, pokazuje wszystko, co jest oznaczone offline, razem z zajmowanym miejscem,
i pozwala przełączyć elementy z powrotem na „tylko online”, usuwając pobrane kopie.

**[Pobierz dla Apple Silicon](https://github.com/emiterkamieni/unbox/releases/latest)**
 · [English](README.md)

## Funkcje

- Lista folderów i plików offline pogrupowana według folderów najwyższego poziomu (np. klientów), z miejscem
  zajmowanym na dysku. Sortowanie według nazwy lub rozmiaru.
- Odznacz elementy i kliknij **Zastosuj**: unbox wywołuje akcję Box Drive *Make Available Online Only*
  i usuwa pobrane kopie. Pliki zostają widoczne w Finderze i pobiorą się przy otwarciu.
- Pliki z niewysłanymi zmianami nigdy nie są usuwane. unbox niczego nie zapisuje do plików Box Drive
  i sam niczego nie pobiera z chmury.
- 15 języków (domyślnie język systemu), uruchamianie przy logowaniu.
- Powiadomienia o nowych wersjach (co 24 godziny) i aktualizacja z poziomu aplikacji (Sparkle, podpisy EdDSA).

## Wymagania i instalacja

Mac z Apple Silicon, macOS 13 lub nowszy, Box Drive w trybie File Provider (folder `~/Library/CloudStorage/Box-Box`).

1. Pobierz `unbox-<wersja>-macos-arm64.zip` z [najnowszego wydania](https://github.com/emiterkamieni/unbox/releases/latest).
2. Rozpakuj i przenieś `unbox.app` do `/Applications`.
3. Aplikacja jest podpisana ad hoc i nie jest notaryzowana przez Apple, więc pierwsze uruchomienie zostanie
   zablokowane. Otwórz **Ustawienia systemowe → Prywatność i ochrona**, kliknij **Otwórz mimo to** przy unbox
   i potwierdź.

Kolejne wersje instalują się z poziomu aplikacji.

Szczegóły techniczne, budowanie i wydawanie nowych wersji opisuje [README po angielsku](README.md).

## Licencja

[GPL-3.0-only](LICENSE). Zawiera [Sparkle](https://github.com/sparkle-project/Sparkle) na licencji MIT.
