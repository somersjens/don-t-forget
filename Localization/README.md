# Lokalisaties beheren

De app en widget gebruiken ieder een Xcode String Catalog. Gebruik het script in
`tools/localization.py` als vaste ingang voor controle, export en import.

## Controleren

```sh
python3 tools/localization.py validate
```

De controle meldt ontbrekende of onafgemaakte vertalingen en afwijkende
format-placeholders. Standaard worden Nederlands (`nl`) en Engels (`en`)
gecontroleerd.

## Nederlands en Engels exporteren

```sh
python3 tools/localization.py export
```

Dit maakt in `Localization/Exports`:

- `all-localizations.csv`: Nederlands en Engels naast elkaar;
- `all-nl.csv` en `all-en.csv`: één bestand per taal;
- `new-language-template.csv`: invulbestand voor een vertaler.

De bestanden zijn UTF-8 met BOM, zodat Excel accenten en leestekens goed opent.

## Een nieuwe taal importeren

1. Exporteer de bestanden.
2. Hernoem `new-language-template.csv`, bijvoorbeeld naar `de.csv`.
3. Laat de kolommen `catalog`, `key` en `source_en` ongewijzigd en vul iedere
   cel in `translation` in.
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
