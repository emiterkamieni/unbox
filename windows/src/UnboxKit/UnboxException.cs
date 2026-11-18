namespace Unbox.Kit;

public sealed class UnboxException(string message) : Exception(message)
{
    public static UnboxException BoxNotInstalled() =>
        new(L10n.Text("Box Drive data was not found on this PC.", "Nie znaleziono danych Box Drive na tym komputerze."));

    public static UnboxException LegacyBoxDrive() =>
        new(L10n.Text("unbox needs the new Box Drive for Windows (version 2.47 or later). Update Box Drive and try again.",
                      "unbox wymaga nowego Box Drive dla Windows (wersja 2.47 lub nowsza). Zaktualizuj Box Drive i spróbuj ponownie."));

    public static UnboxException SyncRootMissing(string path) =>
        new(L10n.Format("The Box folder does not exist: %@", "Folder Box nie istnieje: %@", path));

    public static UnboxException DatabaseUnavailable(string reason) =>
        new(L10n.Format("Could not read the Box Drive database: %@", "Nie udało się odczytać bazy Box Drive: %@", reason));

    public static UnboxException UnsupportedDatabase() =>
        new(L10n.Text("This version of Box Drive uses an unsupported database format.",
                      "Ta wersja Box Drive ma nieobsługiwany format bazy danych."));

    public static UnboxException ItemNotInBox(string path) =>
        new(L10n.Format("This item is not in Box: %@", "Element nie należy do Box: %@", path));

    public static UnboxException ActionFailed(string reason) =>
        new(L10n.Format("Box rejected the change: %@", "Box odrzucił operację: %@", reason));

    public static UnboxException BoxDidNotApply(string name) =>
        new(L10n.Format("Box did not change “%@”. Try again or use File Explorer.",
                        "Box nie zmienił stanu „%@”. Spróbuj ponownie lub użyj Eksploratora plików.", name));
}
