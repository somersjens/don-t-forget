# Lokalisaties beheren

De app en widget gebruiken ieder een Xcode String Catalog. Gebruik het script in
`tools/localization.py` als vaste ingang voor controle, export en import.

## Controleren

```sh
python3 tools/localization.py validate
```

De controle meldt ontbrekende of onafgemaakte vertalingen en afwijkende
format-placeholders. Standaard worden Nederlands (`nl`) en Engels (`en`)
gecontroleerd. Enkelvoud/meervoud (plurals) worden per vorm gecontroleerd.

## Twee catalogi

De app en de widget hebben elk een eigen String Catalog:

- `Don't forget/Don't forget/Localizable.xcstrings` (`catalog` = `app`);
- `Don't forget/Don't forgetWidget/Localizable.xcstrings` (`catalog` = `widget`).

Beide worden door alle commando's meegenomen; de `catalog`-kolom in de
CSV-bestanden bepaalt waar een regel bij hoort.

## Enkelvoud en meervoud

Telbare teksten gebruiken een String Catalog-plural in plaats van een
code-switch. In de CSV krijgt zo'n tekst één regel per vorm via de kolom
`variation` (bijvoorbeeld `plural.one` en `plural.other`); gewone teksten hebben
een lege `variation`. Een taal met méér plural-categorieën (bijvoorbeeld Pools:
`one`, `few`, `many`, `other`) vul je het snelst rechtstreeks in de String
Catalog-editor van Xcode aan; de CSV-route dekt de `one`/`other`-talen.

## Nederlands en Engels exporteren

```sh
python3 tools/localization.py export
```

Dit maakt in `Localization/Exports`:

- `all-localizations.csv`: Nederlands en Engels naast elkaar;
- `all-nl.csv` en `all-en.csv`: één bestand per taal;
- `new-language-template.csv`: invulbestand voor een vertaler.

De bestanden zijn UTF-8 met BOM, zodat Excel accenten en leestekens goed opent.

## Talen die al klaarstaan

De taalkiezer toont alle 78 opties (Systeem + 77 talen, elk met vlag). Alleen
Nederlands en Engels zijn echt vertaald; de catalogi blijven daardoor **compact**
(alleen `nl`/`en`). Elke niet-vertaalde taal valt tijdens runtime automatisch
terug op Engels (`localizedCatalogKey` in `AppSettings.swift`), dus er verschijnt
nooit een ruwe key. Zodra je een taal echt vertaalt, verschijnt die tekst; de
rest van die taal blijft Engels tot je meer invult.

De lijst met ondersteunde talen staat op twee plekken die gelijk moeten blijven:
`AppLanguage.supportedCodes` (Swift) en `SUPPORTED_CODES` in `tools/localization.py`.

## Alle talen in één bestand vertalen (aanbevolen)

```sh
python3 tools/localization.py export-matrix
```

Dit maakt `Localization/translations.csv` (puntkomma-gescheiden). Kolommen:

- `instructie`: per regel uitleg — tekenbudget, te behouden plaatshouders
  (`%@`, `%lld`), speciale tekens en meervoudscontext;
- `en` en `nl`: de bestaande bronteksten (referentie, niet wijzigen);
- daarna **één kolom per doeltaal** (75 stuks), leeg om in te vullen;
- `catalog`, `key`, `variation`: technische kolommen — laat ze ongewijzigd, ze
  koppelen elke regel aan de juiste tekst. Regels met `variation` = `plural.one`
  / `plural.other` zijn de enkelvoud/meervoudsvormen.

Vul de talen die je wilt (gedeeltelijk mag: lege cellen blijven Engels) en lever
het bestand in dezelfde vorm terug. Inladen doe je met:

```sh
python3 tools/localization.py import-matrix Localization/translations.csv
```

De import is **transactioneel**: bij een onbekende regel of een afwijkende
plaatshouder wordt er niets gewijzigd. Alleen ingevulde cellen worden geschreven.
Nieuwvertaalde talen worden meteen in de catalogi gezet en verschijnen na een
build automatisch. (Regelafbreken staan in de CSV als `\n`.)

## Een nieuwe taal importeren

1. Exporteer de bestanden.
2. Hernoem `new-language-template.csv`, bijvoorbeeld naar `de.csv`.
3. Laat de kolommen `catalog`, `key`, `variation` en `source_en` ongewijzigd en
   vul iedere cel in `translation` in (ook elke `plural.*`-regel).
4. Importeer het bestand:

```sh
python3 tools/localization.py import --language de Localization/de.csv
```

De import is transactioneel: bij een ontbrekende regel, onbekende key, lege
vertaling of beschadigde placeholder worden de catalogi niet gewijzigd. De
taalcode moet een geldige BCP-47-code zijn, zoals `de`, `fr` of `pt-BR`.

De taalkiezer van de app leest beschikbare String Catalog-talen dynamisch uit
de appbundle. Een correct geïmporteerde taal verschijnt daardoor na een nieuwe
build automatisch. Voeg voor een productierelease ook gelokaliseerde
`InfoPlist.strings` toe wanneer de naam of permissieteksten vertaald moeten
worden.
