# Totaaloverzicht zichtbare tekst — Nederlands en Engels

_Inventaris van de huidige broncode, opgesteld op 4 juli 2026._

> Historische momentopname van vóór de meertalige lokalisatierefactor. De actuele bron van waarheid is `Localizable.xcstrings`; de eerder gemarkeerde gaten zijn inmiddels gemigreerd.

## Reikwijdte

Dit overzicht bevat ontwikkelaars-gedefinieerde tekst die een gebruiker kan zien of via VoiceOver kan horen: schermkoppen, knoppen, labels, placeholders, uitleg, meldingen, foutteksten, widgettekst en dynamische omschrijvingen. Niet opgenomen zijn door gebruikers ingevoerde inhoud, systeemnamen van SF Symbols, interne identifiers, URL's en automatisch door iOS gelokaliseerde datum-/tijdwaarden.

De code gebruikt drie lokalisatiemechanismen: de String Catalog, directe NL/EN-paren en taalafhankelijke codewaarden. Swift-interpolatie zoals \(waarde) duidt dynamische inhoud aan.

## Belangrijkste lokalisatiegaten

In deze gevallen krijgt een Engelstalige gebruiker momenteel Nederlandse tekst te zien.

| Onderdeel | Nederlands | Huidige Engelse weergave |
|---|---|---|
| Verjaardagsstatus | Is vandaag jarig | ⚠ Is vandaag jarig |
| Verjaardagsstatus | Is vandaag {leeftijd} geworden | ⚠ Is vandaag {leeftijd} geworden |
| Verjaardagsstatus | Is over {dagen} dag/dagen jarig | ⚠ Is over {dagen} dag/dagen jarig |
| Verjaardagsstatus | Wordt over {dagen} dag/dagen {leeftijd} | ⚠ Wordt over {dagen} dag/dagen {leeftijd} |
| Frequentieparser | Voeg frequentie toe | ⚠ Voeg frequentie toe |
| Frequentieparser | Frequentie nog niet herkend | ⚠ Frequentie nog niet herkend |
| Spraakfout | Geen toestemming voor spraakherkenning. | ⚠ Geen toestemming voor spraakherkenning. |
| Spraakfout | Geen toegang tot de microfoon. | ⚠ Geen toegang tot de microfoon. |
| Spraakfout | Spraakherkenning is momenteel niet beschikbaar. | ⚠ Spraakherkenning is momenteel niet beschikbaar. |
| Spraakfout | Spraakopname kon niet starten. | ⚠ Spraakopname kon niet starten. |
| Widget | Geen komende items | ⚠ Geen komende items |
| Widgetgalerij | Eerstvolgende kalenderitems | ⚠ Eerstvolgende kalenderitems |
| Widgetgalerij | Toont automatisch de eerstvolgende items uit je agenda. | ⚠ Toont automatisch de eerstvolgende items uit je agenda. |

Daarnaast hebben **alle feestdagnamen** maar één opgeslagen titel. Nederlandse feestdagen blijven dus Nederlands in de Engelse app; Britse en Amerikaanse namen blijven Engels in de Nederlandse app. Zie de laatste groep.

## Start, account en navigatie

| Nederlands | Engels | Herkomst |
|---|---|---|
| Aan de slag | Get Started | direct taalpaar |
| Afgerond | Finished | taalafhankelijke code |
| Alles wat je niet wilt vergeten, op één plek. | Everything you don't want to forget, in one place. | direct taalpaar |
| Herhalingen | Recurring | taalafhankelijke code |
| iCloud-synchronisatie | iCloud Sync | direct taalpaar |
| Item op %@ | Item at %@ | String Catalog |
| Kalender | Calendar | taalafhankelijke code |
| Selecteer een item | Select an Item | String Catalog |
| Taken | To-do | taalafhankelijke code |
| Voeg item toe | Add Item | String Catalog |
| ↓ | ⚠ ontbreekt | String Catalog |

## Agenda

| Nederlands | Engels | Herkomst |
|---|---|---|
| Afvinken | Mark as Done | String Catalog |
| Bewerken afsluiten | Finish Editing | String Catalog |
| De app varieert de datum deterministisch rond dit interval. Zo blijft het spontaan, maar verspringt de planning niet bij iedere sync. | The app varies the date deterministically around this interval. This keeps it spontaneous without changing the schedule after every sync. | String Catalog |
| Een positie omhoog | Move Up One Position | String Catalog |
| Een positie omlaag | Move Down One Position | String Catalog |
| Geboortedatum | Date of Birth | String Catalog |
| Gebruik de controls, of tik op een andere weekdag om direct te verplaatsen. | Use the controls, or tap another weekday to move it directly. | uitleg/tutorial |
| Iets afgerond? Tik op de cirkel rechts. Het verhuist naar Afgerond. | Finished something? Tap the circle on the right. It moves to Finished. | uitleg/tutorial |
| Ingeklapt | Collapsed | direct taalpaar |
| Item verplaatst ↵ naar Afgerond | Item moved ↵ to Finished | direct taalpaar |
| Ja graag | Yes please | direct taalpaar |
| Je agenda staat klaar voor alles wat komt. | Your calendar is ready for whatever comes next. | direct taalpaar |
| Kalenderweergave | Calendar View | String Catalog |
| Klaar met verplaatsen | Finish Moving | String Catalog |
| Naar agenda | Move to Calendar | String Catalog |
| Naar agenda... | Move to Calendar… | String Catalog |
| Ongedaan maken | Undo | direct taalpaar |
| Opnieuw | Replay | direct taalpaar |
| Regel bewerken | Edit Entry | String Catalog |
| Sluiten | Close | direct taalpaar |
| Stap \(step + 1)/\(Self.stepCount) | Step \(step + 1)/\(Self.stepCount) | direct taalpaar |
| Tik achter een dag om iets te schrijven. Klaar? Tik rechtsboven op ✓. | Tap after a day to write something. Done? Tap ✓ at the top right. | uitleg/tutorial |
| Tik om de uitleg in of uit te klappen | Tap to expand or collapse help | direct taalpaar |
| Tik op de weekdag vóór de lijn om de verplaatsmodus te openen. | Tap the weekday before the line to open move mode. | uitleg/tutorial |
| Uitgeklapt | Expanded | direct taalpaar |
| Uitleg over Agenda | Agenda help | direct taalpaar |
| Verplaats naar: | Move to: | String Catalog |
| Verplaatsmodus afsluiten | Exit Move Mode | String Catalog |
| Verplaatsopties | Move Options | String Catalog |
| Volgende 3 maanden laden… | Loading the Next 3 Months… | direct taalpaar |
| Volgende herhalingen meeverschuiven? | Shift following recurrences too? | direct taalpaar |
| Volgende herhalingen zijn meeverschoven | Following recurrences were shifted | direct taalpaar |
| Volgende stap | Next step | direct taalpaar |
| Vorige stap | Previous step | direct taalpaar |
| ‘\(recentlyRemovedEntryTitle)’ verwijderd | ‘\(recentlyRemovedEntryTitle)’ deleted | direct taalpaar |

## Taken

| Nederlands | Engels | Herkomst |
|---|---|---|
| %@, taak verplaatsen | %@, move task | String Catalog |
| Andere datum in agenda... | Different date in calendar... | String Catalog |
| Beschrijf nog een taak, of tik rechtsboven op het vinkje om de invoer af te ronden. | Describe another task, or tap the checkmark at the top right to finish entering tasks. | uitleg/tutorial |
| Binnenkort | Soon | String Catalog |
| Boodschappen | Groceries | String Catalog |
| Groep | Group | String Catalog |
| Ingeklapt | Collapsed | direct taalpaar |
| Je hebt je taken helemaal in de hand. | You’ve got your tasks under control. | direct taalpaar |
| Kies datum | Choose Date | String Catalog |
| Lange termijn | Long term | String Catalog |
| Maak een taak in een categorie door in het invoerveld iets te schrijven. | Create a task in a category by typing something in its input field. | uitleg/tutorial |
| Naar vandaag %@ | To today %@ | String Catalog |
| Nieuw | New | direct taalpaar |
| Nieuwe groep | New Group | String Catalog |
| Nieuwe taak invoeren | Enter New Task | String Catalog |
| Nieuwe to-do | New To-do | String Catalog |
| Ongedaan maken | Undo | direct taalpaar |
| Opnieuw | Replay | direct taalpaar |
| Pas de volgorde van categorieën aan via de chevrons. | Change the category order using the chevrons. | uitleg/tutorial |
| Sluiten | Close | direct taalpaar |
| Stap \(step + 1)/\(Self.stepCount) | Step \(step + 1)/\(Self.stepCount) | direct taalpaar |
| Taak verplaatst ↵ naar Afgerond | Task Moved ↵ to Finished | String Catalog |
| Taak verplaatst ↵ naar Afgerond | Task moved ↵ to Finished | direct taalpaar |
| Tik om de uitleg in of uit te klappen | Tap to expand or collapse help | direct taalpaar |
| Tik op de pijl linksboven om je laatste invoer ongedaan te maken. Dit kan voor maximaal drie invoeren. | Tap the arrow at the top left to undo your latest entry. You can do this for up to three entries. | uitleg/tutorial |
| Tik op het plusje om direct nog een taak aan te maken. | Tap the plus to immediately create another task. | uitleg/tutorial |
| Toetsenbord sluiten | Dismiss Keyboard | String Catalog |
| typ iets | type something | String Catalog |
| Uitgeklapt | Expanded | direct taalpaar |
| Uitleg over Taken | Tasks help | direct taalpaar |
| Volgende stap | Next step | direct taalpaar |
| Voor elke taak staat hoe lang die openstaat. Tik hierop om de taak naar een andere categorie of de kalender te verplaatsen. | Each task shows how long it has been open. Tap this time indicator to move the task to another category or the calendar. | uitleg/tutorial |
| Vorige stap | Previous step | direct taalpaar |
| ‘\(move.text)’ verplaatst naar \(date) | ‘\(move.text)’ moved to \(date) | direct taalpaar |
| ‘\(recentlyRemovedTodoTitle)’ verwijderd | ‘\(recentlyRemovedTodoTitle)’ deleted | direct taalpaar |

## Herhalingen en feestdagen

| Nederlands | Engels | Herkomst |
|---|---|---|
| 2000 | 2000 | String Catalog |
| \(annualOrdinalName(item.monthlyOrdinal).capitalized) \(weekdayName(item.monthlyWeekday)) van \(AppCalendar.monthName(item.annualMonth)) | \(annualOrdinalName(item.monthlyOrdinal).capitalized) \(weekdayName(item.monthlyWeekday)) of \(AppCalendar.monthName(item.annualMonth)) | direct taalpaar |
| \(annualOrdinalName(item.monthlyOrdinal).capitalized) \(weekdayName(item.monthlyWeekday)) van de maand | \(annualOrdinalName(item.monthlyOrdinal).capitalized) \(weekdayName(item.monthlyWeekday)) of the month | direct taalpaar |
| \(Self.ordinalName(ordinal).capitalized) \(Self.weekdayName(weekday)) van \(AppCalendar.monthName(month)) | \(Self.ordinalName(ordinal).capitalized) \(Self.weekdayName(weekday)) of \(AppCalendar.monthName(month)) | direct taalpaar |
| Aantal dagen vooraf | Number of Days Before | String Catalog |
| Algemeen | General | String Catalog |
| Annuleer | Cancel | direct taalpaar |
| België | Belgium | taalafhankelijke code |
| Bewaar | Save | String Catalog |
| Cadeau-idee of andere herinnering... | Gift idea or another reminder… | direct taalpaar |
| Compacte categorieën tonen alleen de titel en eerstvolgende datum. Feestdagen staan standaard compact. | Compact categories show only the title and next date. Holidays are compact by default. | String Catalog |
| Compacte rij voor %@ | Compact Row for %@ | String Catalog |
| Compacte rijen | Compact Rows | String Catalog |
| Dag van maand | Day of Month | String Catalog |
| Dagelijks | Daily | direct taalpaar |
| Dagen vooraf | Days Before | String Catalog |
| De app varieert de datum voorspelbaar rond deze gekozen periode. Zo blijft het spontaan, maar verspringt de planning niet bij iedere synchronisatie. | The app varies the date predictably around the selected period. This keeps it spontaneous without changing the schedule after every sync. | direct taalpaar |
| De bovenste link verschijnt klikbaar in het overzicht. Na het invullen verschijnt automatisch een volgend veld, tot maximaal vijf links. | The first link appears as a clickable link in the overview. A new field appears automatically after entry, up to five links. | direct taalpaar |
| De standaardselectie van het nieuwe land vervangt je huidige geselecteerde feestdagen. Eigen feestdagen worden niet verwijderd. | The new country’s default selection replaces your currently selected holidays. Custom holidays are not deleted. | direct taalpaar |
| De standaardselectie van het nieuwe land vervangt je huidige geselecteerde feestdagen. Eigen feestdagen worden niet verwijderd. | The default selection for the new country will replace your currently selected holidays. Custom holidays will not be deleted. | String Catalog |
| Derde | Third | String Catalog |
| Deselecteer alles | Deselect All | String Catalog |
| Deze reminder gebruikt dezelfde kleur als de verjaardagscategorie. | This reminder uses the same color as the birthday category. | String Catalog |
| Duitsland | Germany | taalafhankelijke code |
| Een landwissel vervangt deze selectie. Eigen feestdagen blijven bewaard. Data uit de islamitische kalender kunnen door lokale maanwaarneming één dag verschillen. | Changing countries replaces this selection. Custom holidays are preserved. Islamic calendar dates may differ by one day due to local moon sightings. | String Catalog |
| Eenheid | Unit | String Catalog |
| Eerste | First | String Catalog |
| Eerste herhaling toevoegen | Add First Recurrence | String Catalog |
| Eerste verjaardag toevoegen | Add First Birthday | String Catalog |
| Eerstvolgende datum | Next Date | String Catalog |
| Eerstvolgende datum | Next date | direct taalpaar |
| Eigen feestdag toevoegen | Add Custom Holiday | String Catalog |
| Eigen feestdagen kun je ook toevoegen met de plusknop bij de oranje categorie. | You can also add custom holidays with the plus button in the orange category. | String Catalog |
| Elk kwartaal | Every Quarter | String Catalog |
| Elk kwartaal | Quarterly | direct taalpaar |
| Elk kwartaal op de \(day) | Every quarter on the \(day) | direct taalpaar |
| Elke %lld | Every %lld | String Catalog |
| Elke %llde van de maand | Every %lldth of the Month | String Catalog |
| Elke \(amount) dagen | Every \(amount) days | direct taalpaar |
| Elke \(amount) jaar op \(date) | Every \(amount) years on \(date) | direct taalpaar |
| Elke \(amount) maanden op de \(day) | Every \(amount) months on the \(day) | direct taalpaar |
| Elke \(amount) weken op \(weekday) | Every \(amount) weeks on \(weekday) | direct taalpaar |
| Elke \(parity) week op \(weekday) | Every \(parity) week on \(weekday) | direct taalpaar |
| even | even | direct taalpaar |
| Extra notitie... | Additional note… | direct taalpaar |
| Eén dag meer | One Day More | String Catalog |
| Eén dag minder | One Day Less | String Catalog |
| Feestdag op vaste dag | Holiday on a Fixed Date | String Catalog |
| Feestdagen | Holidays | String Catalog |
| Feestdagen kiezen | Choose Holidays | String Catalog |
| Flexibel (ongeveer) | Flexible (approximate) | direct taalpaar |
| Frankrijk | France | taalafhankelijke code |
| Frequentie | Frequency | String Catalog |
| Ga terug naar de kalender om je herhaling te vinden. Een herhaling wordt steeds opnieuw vooruit gepland. | Return to the calendar to find your recurrence. It will keep being scheduled into the future. | uitleg/tutorial |
| Geboortejaar | Birth year | direct taalpaar |
| Herhaling toevoegen aan %@ | Add Recurrence to %@ | String Catalog |
| Herhalingen beheren | Manage Recurrences | String Catalog |
| Huidige selectie overschrijven? | Replace Current Selection? | direct taalpaar |
| In niet-schrikkeljaren wordt de verjaardag op 28 februari getoond. | In non-leap years, the birthday is shown on February 28. | String Catalog |
| Ingeklapt | Collapsed | direct taalpaar |
| Islamitische kalender | Islamic calendar | direct taalpaar |
| Jaar | Year | direct taalpaar |
| Jaarlijks (jubileum) | Yearly (anniversary) | direct taalpaar |
| Jaarlijks op \(date) | Annually on \(date) | direct taalpaar |
| Jaren | Years | String Catalog |
| Je herhalingen regelen voortaan zichzelf. | Your recurring items now take care of themselves. | direct taalpaar |
| Je land is automatisch gekozen op basis van je regio. Zet de schakelaar uit om ook feestdagen en vieringen uit andere landen te zien. | Your country was selected automatically based on your region. Turn off the switch to also see holidays and observances from other countries. | String Catalog |
| Kleur voor %@ | Color for %@ | String Catalog |
| Laat alleen lokale feestdagen zien | Show Local Holidays Only | String Catalog |
| Leeg linkveld verwijderen | Delete empty link field | direct taalpaar |
| Link verwijderen | Delete link | direct taalpaar |
| Linknaam aanpassen | Edit link name | direct taalpaar |
| Links | Links | direct taalpaar |
| Maak binnen je categorie een nieuwe herhaling door op het plusje te tikken. | Create a recurrence in your category by tapping its plus button. | uitleg/tutorial |
| Maak zelf een categorie. Tik op de tekst in het nieuwe blok en kies een naam. | Create your own category. Tap the text in the new block and choose a name. | uitleg/tutorial |
| Maandelijks op datum | Monthly on a date | direct taalpaar |
| Maandelijks op de \(day) | Monthly on the \(day) | direct taalpaar |
| Maandelijks op weekdag | Monthly on a weekday | direct taalpaar |
| Maanden | Months | String Catalog |
| Marokko | Morocco | taalafhankelijke code |
| Naam | Name | direct taalpaar |
| Nederland | Netherlands | taalafhankelijke code |
| Nieuw | New | direct taalpaar |
| Nieuwe herhaling | New Recurrence | direct taalpaar |
| Notitie | Note | String Catalog |
| oneven | odd | direct taalpaar |
| Ongedaan maken | Undo | direct taalpaar |
| Ongeveer dagelijks | Approximately daily | direct taalpaar |
| Ongeveer elke \(amount) dagen | Approximately every \(amount) days | direct taalpaar |
| Ongeveer elke \(amount) jaar | Approximately every \(amount) years | direct taalpaar |
| Ongeveer elke \(amount) maanden | Approximately every \(amount) months | direct taalpaar |
| Ongeveer elke \(amount) weken | Approximately every \(amount) weeks | direct taalpaar |
| Ongeveer jaarlijks | Approximately annually | direct taalpaar |
| Ongeveer maandelijks | Approximately monthly | direct taalpaar |
| Ongeveer wekelijks | Approximately weekly | direct taalpaar |
| Onzeker | Uncertain | direct taalpaar |
| Opnieuw | Replay | direct taalpaar |
| Overschrijf | Replace | direct taalpaar |
| Overzicht | Overview | String Catalog |
| Pas het icoon en de kleur van je categorie aan door op het logo te tikken. | Change your category’s icon and color by tapping its logo. | uitleg/tutorial |
| Plak link | Paste link | direct taalpaar |
| Reminder vooraf | Reminder in Advance | String Catalog |
| Rond Pasen | Around Easter | direct taalpaar |
| Selecteer alles | Select All | String Catalog |
| Selectie | Selection | String Catalog |
| Sluiten | Close | direct taalpaar |
| Sorteer eerstvolgende bovenaan | Sort Next Date First | String Catalog |
| Standaardland | Default Country | String Catalog |
| Stap \(step + 1)/\(Self.stepCount) | Step \(step + 1)/\(Self.stepCount) | direct taalpaar |
| Startdatum | Start date | direct taalpaar |
| Suriname | Suriname | taalafhankelijke code |
| Tik linksboven op de pijlen om de instellingen voor herhalingen aan te passen. | Tap the arrows at the top left to adjust recurrence settings. | uitleg/tutorial |
| Tik om de uitleg in of uit te klappen | Tap to expand or collapse help | direct taalpaar |
| Tik op de gekleurde stip om de kleur te wijzigen. Compacte categorieën tonen alleen de titel en eerstvolgende datum. | Tap the colored dot to change the color. Compact categories show only the title and next date. | String Catalog |
| Titel | Title | direct taalpaar |
| Toon feestdagen in overzicht | Show Holidays in Overview | String Catalog |
| Toon volgende datum | Show Next Date | String Catalog |
| Turkije | Türkiye | taalafhankelijke code |
| Tweede | Second | String Catalog |
| Uitgeklapt | Expanded | direct taalpaar |
| Uitleg over herhalingen | Recurring help | direct taalpaar |
| Vaste regelmaat | Fixed schedule | direct taalpaar |
| Verenigd Koninkrijk | United Kingdom | taalafhankelijke code |
| Verenigde Staten | United States | taalafhankelijke code |
| Verjaardagen | Birthdays | String Catalog |
| Verwijder herhaling | Delete Recurrence | String Catalog |
| Vierde | Fourth | String Catalog |
| Volgende stap | Next step | direct taalpaar |
| Vorige stap | Previous step | direct taalpaar |
| Vul een geldig geboortejaar in. | Enter a valid birth year. | direct taalpaar |
| Wat | What | direct taalpaar |
| Weekdag | Weekday | String Catalog |
| Weekdag van een maand | Weekday of a Month | String Catalog |
| Weekdag van maand | Weekday of Month | String Catalog |
| Wekelijks op \(weekday) | Weekly on \(weekday) | direct taalpaar |
| Weken | Weeks | String Catalog |
| Welke | Which | String Catalog |
| Wie | Who | direct taalpaar |
| Wijzig herhaling | Edit Recurrence | direct taalpaar |
| Wordt ieder jaar herhaald op de datum hierboven. | Repeats every year on the date above. | direct taalpaar |
| Wordt iedere drie maanden herhaald vanaf de eerstvolgende datum. | Repeats every three months from the next date. | String Catalog |
| · herinnering %lld | · reminder %lld | String Catalog |
| ‘\(title)’ verwijderd | ‘\(title)’ deleted | direct taalpaar |

## Afgerond en historie

| Nederlands | Engels | Herkomst |
|---|---|---|
| over de app | of the app | direct taalpaar |
| %lld afgerond | %lld completed | String Catalog |
| Acties voor %@ | Actions for %@ | String Catalog |
| Afgelopen 10 weken | Last 10 Weeks | direct taalpaar |
| Afgelopen 12 maanden | Last 12 Months | direct taalpaar |
| Afgelopen 7 dagen | Last 7 Days | direct taalpaar |
| Afgeronde items verschijnen hier automatisch en kun je altijd weer terugzetten. | Completed items appear here automatically and can always be restored. | direct taalpaar |
| Agenda | Calendar | direct taalpaar |
| Alles | All | direct taalpaar |
| Definitief verwijderen | Delete Permanently | String Catalog |
| Demodata activeren | Enable Demo Data | String Catalog |
| Demodata verwijderen | Remove Demo Data | String Catalog |
| Doorzoek je afgeronde items met de zoekbalk. Zoek nu op ‘example’. | Search your finished items with the search bar. Search for ‘example’ now. | uitleg/tutorial |
| Gebruik de filterknoppen om alleen afgeronde items van een bepaalde tab te zien. | Use the filters to show only finished items from a specific tab. | uitleg/tutorial |
| Geen afgeronde %@-items | No Completed %@ Items | String Catalog |
| Geen afgeronde \(filter.title(for: locale).lowercased())-items | No completed \(filter.title(for: locale).lowercased()) items | direct taalpaar |
| Geen zoekresultaten | No search results | direct taalpaar |
| Gisteren | Yesterday | direct taalpaar |
| Grafieken inklappen | Collapse Charts | String Catalog |
| Grafieken uitklappen | Expand Charts | String Catalog |
| Herhalingen | Recurring | direct taalpaar |
| Houd 3 seconden ingedrukt om demodata te activeren. | Press and hold for 3 seconds to activate demo data. | direct taalpaar |
| Hulp nodig? Stuur ons een | Need help? Send us an | direct taalpaar |
| Hulp nodig? Stuur ons een email | Need help? Send us an email | direct taalpaar |
| Ingeklapt | Collapsed | direct taalpaar |
| Je weet nu precies hoe Afgerond werkt. | You now know exactly how Finished works. | direct taalpaar |
| Laad oudere items (\(min(Self.pageSize, remainingRowCount))) | Load Older Items (\(min(Self.pageSize, remainingRowCount))) | direct taalpaar |
| Nog niets afgerond | Nothing finished yet | direct taalpaar |
| Nog niets afgerond | Nothing Finished Yet | String Catalog |
| Nog veel meer handige instellingen vind je achter het menu rechtsbovenin. | You’ll find many more useful options in the menu at the top right. | uitleg/tutorial |
| Ongedaan maken | Undo | direct taalpaar |
| Opnieuw | Replay | direct taalpaar |
| Periode | Period | String Catalog |
| Probeer een andere zoekopdracht of wis de zoekbalk. | Try another search or clear the search bar. | direct taalpaar |
| Schrijf een | Write a | direct taalpaar |
| Schrijf een review over de app | Write a review of the app | direct taalpaar |
| Sluiten | Close | direct taalpaar |
| Stap \(step + 1)/\(Self.stepCount) | Step \(step + 1)/\(Self.stepCount) | direct taalpaar |
| Taken | Tasks | direct taalpaar |
| Terugzetten | Restore | String Catalog |
| Tik eerst op het icoon van het item. Tik daarna op het prullenbakje om het definitief te verwijderen. | First tap the item icon. Then tap the trash button to delete it permanently. | uitleg/tutorial |
| Tik nu op het prullenbakje om het item definitief te verwijderen. | Now tap the trash button to delete the item permanently. | direct taalpaar |
| Tik om de uitleg in of uit te klappen | Tap to expand or collapse help | direct taalpaar |
| Tik om demodata te verwijderen. | Tap to remove demo data. | direct taalpaar |
| Toch niet? Tik onderin op Ongedaan maken. Normaal heb je hiervoor 5 seconden; tijdens deze uitleg blijft de melding staan. | Changed your mind? Tap Undo at the bottom. Normally you have 5 seconds; during this guide the message stays visible. | uitleg/tutorial |
| Uitgeklapt | Expanded | direct taalpaar |
| Uitleg over Afgerond | Finished help | direct taalpaar |
| Vandaag | Today | direct taalpaar |
| Volgende stap | Next step | direct taalpaar |
| Vorige stap | Previous step | direct taalpaar |
| Zet een item terug naar waar het vandaan kwam met de terugzetknop. | Return an item to where it came from with the restore button. | uitleg/tutorial |
| Zet terug naar %@ | Restore to %@ | String Catalog |
| Zet terug naar \(row.source.title(for: locale)) | Restore to \(row.source.title(for: locale)) | direct taalpaar |
| Zoek in Afgerond | Search Finished | direct taalpaar |
| Zoekopdracht wissen | Clear search | direct taalpaar |
| ‘\(title)’ definitief verwijderd | ‘\(title)’ permanently deleted | direct taalpaar |
| ‘\(title)’ teruggezet | ‘\(title)’ restored | direct taalpaar |

## Instellingen

| Nederlands | Engels | Herkomst |
|---|---|---|
| Laatste sync: | Last sync: | direct taalpaar |
| 1 jaar | 1 year | direct taalpaar |
| 1 januari in week 1 | January 1 in week 1 | taalafhankelijke code |
| 1,5 jaar | 1.5 years | direct taalpaar |
| 2 jaar | 2 years | direct taalpaar |
| 3 maanden | 3 months | direct taalpaar |
| 6 maanden | 6 months | direct taalpaar |
| 9 maanden | 9 months | direct taalpaar |
| Aantal weergeven | Number to Show | String Catalog |
| Actieknop | Action Button | String Catalog |
| Actieknop configureren | Configure Action Button | String Catalog |
| Afgerond opschonen | Clear Finished | direct taalpaar |
| Afgerond verwijderen? | Delete Finished? | direct taalpaar |
| Agenda vooruit laden | Load Calendar Ahead | direct taalpaar |
| Agenda-items kunnen naar je standaard iPhone-kalender worden geschreven. | Calendar items can be written to your default iPhone calendar. | direct taalpaar |
| Alle afgeronde en verwijderde items worden definitief verwijderd. Dit kan niet ongedaan worden gemaakt. | All finished and deleted items will be permanently deleted. This cannot be undone. | direct taalpaar |
| Alle afgeronde items downloaden als CSV | Download all Finished items as CSV | direct taalpaar |
| Alle agenda-items, taken, herhalingen, afgeronde items en instellingen worden definitief verwijderd. De app start daarna alsof je hem voor het eerst hebt gedownload. | All calendar items, tasks, recurrences, finished items, and settings will be permanently deleted. The app will then start as if you downloaded it for the first time. | direct taalpaar |
| Alleen snel invoerveld | Quick entry field only | direct taalpaar |
| Alleen vandaag | Today only | direct taalpaar |
| Als je apparaat kwijt raakt, zijn je gegevens niet terug te halen. | If you lose your device, your data cannot be recovered. | direct taalpaar |
| Annuleer | Cancel | direct taalpaar |
| App-taal | App Language | String Catalog |
| Automatische iCloud-synchronisatie | Automatic iCloud Sync | String Catalog |
| Bij indrukken | When Pressed | String Catalog |
| Blauw | Blue | taalafhankelijke code |
| Bovenste taken | Top tasks | direct taalpaar |
| Bruin | Brown | taalafhankelijke code |
| Cyaan | Cyan | taalafhankelijke code |
| Dagen tellen | Day count | direct taalpaar |
| Dagen tellen (0 = vandaag) | Day count (0 = today) | direct taalpaar |
| Datum | Date | direct taalpaar |
| Datum (dd/mm) | Date (mm/dd) | direct taalpaar |
| De Actieknop is alleen beschikbaar op iPhone 15 Pro en nieuwere modellen. Stel op je iPhone bij Instellingen › Actieknop › Opdracht de opdracht ‘Nieuwe taak’ in. | The Action Button is only available on iPhone 15 Pro and newer models. On your iPhone, go to Settings › Action Button › Shortcut and select the ‘New Task’ shortcut. | direct taalpaar |
| De lockscreen-widget is beschikbaar op iPhone 11 en nieuwere modellen en op iPhone SE (2e generatie) en nieuwer. Houd het toegangsscherm ingedrukt en tik op Pas aan › Toegangsscherm › Voeg widgets toe. Kies daarna de widget van Don’t forget. | The Lock Screen widget is available on iPhone 11 and newer models and on iPhone SE (2nd generation) and newer. Touch and hold the Lock Screen, then tap Customize › Lock Screen › Add Widgets. Then select the Don’t forget widget. | direct taalpaar |
| De wijziging wordt actief nadat je de app volledig hebt afgesloten en opnieuw hebt geopend. | The change takes effect after you fully close and reopen the app. | direct taalpaar |
| Direct spraak opnemen | Start Voice Recording Immediately | String Catalog |
| Einde-dagherinnering | End-of-Day Reminder | direct taalpaar |
| English | English | taalafhankelijke code |
| Exporteert afgeronde en verwijderde items met inhoud, soort, categorie, datumtijd en verwijderstatus. | Exports completed and deleted items with content, type, category, date and time, and deletion status. | direct taalpaar |
| Exporteren mislukt | Export failed | direct taalpaar |
| Geef ‘Don’t forget’ toestemming voor meldingen via de iOS-instellingen. | Allow notifications for ‘Don’t forget’ in iOS Settings. | direct taalpaar |
| Geel | Yellow | taalafhankelijke code |
| Geen openstaande taken voor vandaag | No unfinished tasks for today | direct taalpaar |
| Geen toegang. Je kunt dit later wijzigen in iOS-instellingen. | Access denied. You can change this later in iOS Settings. | direct taalpaar |
| Grijs | Gray | taalafhankelijke code |
| Groen | Green | taalafhankelijke code |
| Hele app openen | Open full app | direct taalpaar |
| Hele app resetten | Reset the entire app | direct taalpaar |
| Hele app resetten? | Reset the Entire App? | direct taalpaar |
| Heropen de app | Reopen the App | direct taalpaar |
| Houd 3 seconden ingedrukt om de hele app te resetten. | Press and hold for 3 seconds to reset the entire app. | direct taalpaar |
| iCloud moet op dit apparaat zijn ingeschakeld. Zonder iCloud blijven gegevens alleen op dit apparaat beschikbaar. | iCloud must be enabled on this device. Without iCloud, data remains available only on this device. | String Catalog |
| iCloud-synchronisatie | iCloud Sync | direct taalpaar |
| Indigo | Indigo | taalafhankelijke code |
| Inhoud | Content | String Catalog |
| ISO 8601 | ISO 8601 | taalafhankelijke code |
| Je gegevens worden privé via iCloud bewaard en automatisch teruggezet op je Apple-apparaten. | Your data is stored privately in iCloud and restored automatically on your Apple devices. | String Catalog |
| Je krijgt een overzicht van de openstaande taken van vandaag. Zijn er geen openstaande taken, dan wordt op de geplande tijd niets verstuurd. De melding is mogelijk niet zichtbaar als je telefoon in slaap- of nachtmodus staat. | You’ll receive a summary of today’s unfinished tasks. If there are no unfinished tasks, nothing is sent at the scheduled time. The notification may not appear while your phone is in Sleep or another Focus mode. | direct taalpaar |
| Kalender synchroniseren… | Syncing Calendar… | String Catalog |
| Kalender vandaag | Calendar Today | String Catalog |
| Later aanpasbaar in Instellingen | You Can Change This Later in Settings | String Catalog |
| Lockscreen-widget | Lock Screen Widget | String Catalog |
| Lockscreen-widget configureren | Configure Lock Screen Widget | String Catalog |
| Maandag | Monday | taalafhankelijke code |
| Melding | Message | String Catalog |
| Meldingen niet beschikbaar | Notifications Unavailable | direct taalpaar |
| Met - | With - | direct taalpaar |
| Met … | With … | direct taalpaar |
| Na 1 jaar | After 1 year | direct taalpaar |
| Na 1 maand | After 1 month | direct taalpaar |
| Na 1 week | After 1 week | direct taalpaar |
| Nederlands | Dutch | taalafhankelijke code |
| Niet | None | direct taalpaar |
| Nooit | Never | direct taalpaar |
| OK | OK | String Catalog |
| Om de kalender soepel te laten scrollen, synchroniseert de app bij het opstarten. Je kunt hierboven ook handmatig synchroniseren. | To keep the calendar scrolling smoothly, the app syncs at launch. You can also sync manually above. | direct taalpaar |
| Openen | Open | String Catalog |
| Opnieuw testen over \(testReminderCountdown) sec. | Test again in \(testReminderCountdown) sec. | direct taalpaar |
| Oranje | Orange | taalafhankelijke code |
| Paars | Purple | taalafhankelijke code |
| Reset alles | Reset Everything | direct taalpaar |
| Resetten mislukt | Reset Failed | direct taalpaar |
| Rood | Red | taalafhankelijke code |
| Roze | Pink | taalafhankelijke code |
| Spraakinvoer | Voice Input | String Catalog |
| Standaardbestemming | Default Destination | String Catalog |
| Synchroniseer met iPhone Kalender | Sync with iPhone Calendar | String Catalog |
| Synchroniseer nu | Sync Now | String Catalog |
| Synchroniseren is mislukt: \(error.localizedDescription) | Sync failed: \(error.localizedDescription) | direct taalpaar |
| Systeem | System | taalafhankelijke code |
| Systeemtaal | System Language | String Catalog |
| Taal en invoer | Language and Input | String Catalog |
| Teal | Teal | taalafhankelijke code |
| Testmelding versturen | Send Test Notification | direct taalpaar |
| Testmelding versturen… | Sending Test Notification… | direct taalpaar |
| Tijd | Time | direct taalpaar |
| Vandaag & morgen | Today & tomorrow | direct taalpaar |
| Verwijder | Delete | direct taalpaar |
| Verwijder alle afgeronde taken | Delete all finished tasks | direct taalpaar |
| Verwijderde items tonen | Show Deleted Items | String Catalog |
| Verwijderen mislukt | Deletion failed | direct taalpaar |
| Voorvoegsel | Prefix | String Catalog |
| Week begint op | Week Starts On | String Catalog |
| Weeknummering | Week Numbering | String Catalog |
| Weergave | Display | String Catalog |
| Woorden afsnijden | Truncate Words | String Catalog |
| Zondag | Sunday | taalafhankelijke code |

## Snelle invoer en spraak

| Nederlands | Engels | Herkomst |
|---|---|---|
| Categorie in Taken kiezen | Choose Category in Tasks | String Catalog |
| Datum in agenda kiezen | Choose Calendar Date | String Catalog |
| Er is geen tekst ingevoerd. | No text was entered. | String Catalog |
| kalender vandaag | calendar today | direct taalpaar |
| Kies een datum | Choose a Date | String Catalog |
| Luistert… | Listening… | String Catalog |
| Opent direct een invoerveld voor een nieuwe taak. | Immediately opens an input field for a new task. | String Catalog |
| Sla snelle invoer op | Save Quick Entry | String Catalog |
| Snel toevoegen | Quick Add | String Catalog |
| Snelle invoer | Quick Entry | String Catalog |
| Spraakopname starten | Start Voice Recording | String Catalog |
| Spraakopname stoppen | Stop Voice Recording | String Catalog |
| Toegevoegd | Added | String Catalog |
| Toegevoegd aan \(destinationDescription) | Added to \(destinationDescription) | direct taalpaar |
| Toegevoegd. | Added. | String Catalog |
| Voeg toe | Add | String Catalog |
| Wat wil je niet vergeten? | What Don't You Want to Forget? | String Catalog |

## Meldingen

| Nederlands | Engels | Herkomst |
|---|---|---|
| Niet vergeten | Don't Forget | taalafhankelijke code |

## Widget

| Nederlands | Engels | Herkomst |
|---|---|---|
| Don't forget | Don't forget | widgetkop |
| Eerstvolgende kalenderitems | ⚠ Eerstvolgende kalenderitems | widgetgalerij |
| Geen komende items | ⚠ Geen komende items | lege widget |
| Toont automatisch de eerstvolgende items uit je agenda. | ⚠ Toont automatisch de eerstvolgende items uit je agenda. | widgetgalerij |

## Algemeen en gedeeld

| Nederlands | Engels | Herkomst |
|---|---|---|
| %@, %lld items | %1$@, %2$lld items | String Catalog |
| %lld | %lld | String Catalog |
| %lld in afgelopen 7 dagen | %lld in the last 7 days | String Catalog |
| %llde | %lldth | String Catalog |
| 7 | 7 | String Catalog |
| Aantal | Number | String Catalog |
| Account | Account | String Catalog |
| Afgerond | Finished | String Catalog |
| Algemeen | General | String Catalog |
| Alles bij de hand. Ook als je je telefoon verliest. | Keep everything close at hand, even if you lose your phone. | String Catalog |
| Annuleer | Cancel | String Catalog |
| Apple ID | Apple ID | String Catalog |
| Bestemming | Destination | String Catalog |
| Categorie | Category | String Catalog |
| Categorie verwijderen | Delete Category | String Catalog |
| Dag | Day | String Catalog |
| Dagen | Days | String Catalog |
| Datum | Date | String Catalog |
| Deze leeftijd hoort niet bij een geboortejaar met 29 februari. Kies een passende leeftijd. | This age does not correspond to a leap year with February 29. Choose an appropriate age. | String Catalog |
| Don't forget | Don't forget | String Catalog |
| Doorgaan | Continue | String Catalog |
| Doorgaan zonder Apple ID | Continue Without Apple ID | String Catalog |
| Feestdagen | Holidays | String Catalog |
| Geboortejaar onzeker | Birth Year Uncertain | String Catalog |
| Gereed | Done | String Catalog |
| Herhalingen | Recurring | String Catalog |
| Huidige leeftijd | Current Age | String Catalog |
| Icoon | Icon | String Catalog |
| Instellingen | Settings | String Catalog |
| Invoer | Input | String Catalog |
| Kalender | Calendar | String Catalog |
| Kleur | Color | String Catalog |
| Kleur en icoon van %@ aanpassen | Change Color and Icon for %@ | String Catalog |
| Kleuren | Colors | String Catalog |
| Koppel Don't forget veilig aan je Apple-account. Je kunt deze koppeling later weer uitschakelen. | Securely connect Don't forget to your Apple Account. You can disconnect it later. | String Catalog |
| Laatste | Last | String Catalog |
| Laatste wijziging terugdraaien | Undo Last Change | String Catalog |
| Log in met Apple ID | Sign in with Apple ID | String Catalog |
| Maand | Month | String Catalog |
| Nieuwe categorie | New Category | String Catalog |
| Nieuwe categorie invoeren | Enter New Category | String Catalog |
| Nieuwe taak | New Task | String Catalog |
| Nu %lld jaar | Now %lld Years Old | String Catalog |
| Omhoog verplaatsen | Move Up | String Catalog |
| Omlaag verplaatsen | Move Down | String Catalog |
| Ongedaan maken | Undo | String Catalog |
| Ongeveer / spontaan | Approximate / Spontaneous | String Catalog |
| Regel | Rule | String Catalog |
| Tekst | Text | String Catalog |
| Toon details | Show Details | String Catalog |
| Type | Type | String Catalog |
| Vast interval | Fixed Interval | String Catalog |
| Verbonden | Connected | String Catalog |
| Verjaardag | Birthday | String Catalog |
| Verplaats | Move | String Catalog |
| Verwijderen | Delete | String Catalog |
| Volgorde van %@ aanpassen | Reorder %@ | String Catalog |
| Wat | What | String Catalog |
| · | · | String Catalog |
| ‘%@’ definitief verwijderd | ‘%@’ permanently deleted | String Catalog |
| ‘%@’ teruggezet | ‘%@’ restored | String Catalog |
| ‘%@’ verwijderd | ‘%@’ deleted | String Catalog |

## Feestdagnamen (huidige, niet vertaalde inhoud)

| Nederlands | Engels | Herkomst |
|---|---|---|
| Allerheiligen | ⚠ Allerheiligen | zelfde titel in beide talen |
| Amazigh Nieuwjaar | ⚠ Amazigh Nieuwjaar | zelfde titel in beide talen |
| Begin van Ramadan | ⚠ Begin van Ramadan | zelfde titel in beide talen |
| Bevrijdingsdag | ⚠ Bevrijdingsdag | zelfde titel in beide talen |
| Boxing Day | ⚠ Boxing Day | zelfde titel in beide talen |
| Christmas Day | ⚠ Christmas Day | zelfde titel in beide talen |
| Columbus Day | ⚠ Columbus Day | zelfde titel in beide talen |
| Dag der Inheemsen | ⚠ Dag der Inheemsen | zelfde titel in beide talen |
| Dag der Marrons | ⚠ Dag der Marrons | zelfde titel in beide talen |
| Dag van de Arbeid | ⚠ Dag van de Arbeid | zelfde titel in beide talen |
| Dag van de Arbeid en Solidariteit | ⚠ Dag van de Arbeid en Solidariteit | zelfde titel in beide talen |
| Dag van de Duitse eenheid | ⚠ Dag van de Duitse eenheid | zelfde titel in beide talen |
| Dag van de Eenheid | ⚠ Dag van de Eenheid | zelfde titel in beide talen |
| Dag van de Jeugd | ⚠ Dag van de Jeugd | zelfde titel in beide talen |
| Dag van de Overwinning | ⚠ Dag van de Overwinning | zelfde titel in beide talen |
| Dag van de Republiek | ⚠ Dag van de Republiek | zelfde titel in beide talen |
| Dag van Democratie en Nationale Eenheid | ⚠ Dag van Democratie en Nationale Eenheid | zelfde titel in beide talen |
| Dag van het Kind | ⚠ Dag van het Kind | zelfde titel in beide talen |
| Dodenherdenking | ⚠ Dodenherdenking | zelfde titel in beide talen |
| Early May bank holiday | ⚠ Early May bank holiday | zelfde titel in beide talen |
| Easter Monday | ⚠ Easter Monday | zelfde titel in beide talen |
| Eerste kerstdag | ⚠ Eerste kerstdag | zelfde titel in beide talen |
| Eerste paasdag | ⚠ Eerste paasdag | zelfde titel in beide talen |
| Eerste pinksterdag | ⚠ Eerste pinksterdag | zelfde titel in beide talen |
| Feestdag van de Duitstalige Gemeenschap | ⚠ Feestdag van de Duitstalige Gemeenschap | zelfde titel in beide talen |
| Feestdag van de Franse Gemeenschap | ⚠ Feestdag van de Franse Gemeenschap | zelfde titel in beide talen |
| Feestdag van de Vlaamse Gemeenschap | ⚠ Feestdag van de Vlaamse Gemeenschap | zelfde titel in beide talen |
| Geboortedag van de profeet (Mawlid) | ⚠ Geboortedag van de profeet (Mawlid) | zelfde titel in beide talen |
| Goede Vrijdag | ⚠ Goede Vrijdag | zelfde titel in beide talen |
| Good Friday | ⚠ Good Friday | zelfde titel in beide talen |
| Groene Mars | ⚠ Groene Mars | zelfde titel in beide talen |
| Hemelvaartsdag | ⚠ Hemelvaartsdag | zelfde titel in beide talen |
| Independence Day | ⚠ Independence Day | zelfde titel in beide talen |
| Islamitisch Nieuwjaar | ⚠ Islamitisch Nieuwjaar | zelfde titel in beide talen |
| Jeugd- en Sportdag | ⚠ Jeugd- en Sportdag | zelfde titel in beide talen |
| Juneteenth | ⚠ Juneteenth | zelfde titel in beide talen |
| Kerstmis | ⚠ Kerstmis | zelfde titel in beide talen |
| Keti Koti | ⚠ Keti Koti | zelfde titel in beide talen |
| Koningsdag | ⚠ Koningsdag | zelfde titel in beide talen |
| Labor Day | ⚠ Labor Day | zelfde titel in beide talen |
| Manifest van de Onafhankelijkheid | ⚠ Manifest van de Onafhankelijkheid | zelfde titel in beide talen |
| Maria-Hemelvaart | ⚠ Maria-Hemelvaart | zelfde titel in beide talen |
| Martin Luther King Jr. Day | ⚠ Martin Luther King Jr. Day | zelfde titel in beide talen |
| Memorial Day | ⚠ Memorial Day | zelfde titel in beide talen |
| Moederdag | ⚠ Moederdag | zelfde titel in beide talen |
| Nationale feestdag | ⚠ Nationale feestdag | zelfde titel in beide talen |
| New Year's Day | ⚠ New Year's Day | zelfde titel in beide talen |
| Nieuwjaar | ⚠ Nieuwjaar | zelfde titel in beide talen |
| Nieuwjaarsdag | ⚠ Nieuwjaarsdag | zelfde titel in beide talen |
| Offerfeest (Eid al-Adha) | ⚠ Offerfeest (Eid al-Adha) | zelfde titel in beide talen |
| Onafhankelijkheidsdag | ⚠ Onafhankelijkheidsdag | zelfde titel in beide talen |
| Onze-Lieve-Heer-Hemelvaart | ⚠ Onze-Lieve-Heer-Hemelvaart | zelfde titel in beide talen |
| Onze-Lieve-Vrouw-Hemelvaart | ⚠ Onze-Lieve-Vrouw-Hemelvaart | zelfde titel in beide talen |
| Paasmaandag | ⚠ Paasmaandag | zelfde titel in beide talen |
| Pinkstermaandag | ⚠ Pinkstermaandag | zelfde titel in beide talen |
| Presidents' Day | ⚠ Presidents' Day | zelfde titel in beide talen |
| Prinsjesdag | ⚠ Prinsjesdag | zelfde titel in beide talen |
| Quatorze Juillet | ⚠ Quatorze Juillet | zelfde titel in beide talen |
| Revolutie van de Koning en het Volk | ⚠ Revolutie van de Koning en het Volk | zelfde titel in beide talen |
| Sinterklaas | ⚠ Sinterklaas | zelfde titel in beide talen |
| Spring bank holiday | ⚠ Spring bank holiday | zelfde titel in beide talen |
| Srefidensi | ⚠ Srefidensi | zelfde titel in beide talen |
| Suikerfeest (Eid al-Fitr) | ⚠ Suikerfeest (Eid al-Fitr) | zelfde titel in beide talen |
| Summer bank holiday | ⚠ Summer bank holiday | zelfde titel in beide talen |
| Terugkeer van Oued Eddahab | ⚠ Terugkeer van Oued Eddahab | zelfde titel in beide talen |
| Thanksgiving | ⚠ Thanksgiving | zelfde titel in beide talen |
| Troonfeest | ⚠ Troonfeest | zelfde titel in beide talen |
| Tweede kerstdag | ⚠ Tweede kerstdag | zelfde titel in beide talen |
| Tweede paasdag | ⚠ Tweede paasdag | zelfde titel in beide talen |
| Tweede pinksterdag | ⚠ Tweede pinksterdag | zelfde titel in beide talen |
| Vaderdag | ⚠ Vaderdag | zelfde titel in beide talen |
| Veterans Day | ⚠ Veterans Day | zelfde titel in beide talen |
| Wapenstilstand | ⚠ Wapenstilstand | zelfde titel in beide talen |

## Opmerkingen voor redactie/QA

- De catalogus bevat één zichtbare sleutel (pijl omlaag) zonder expliciete Nederlandse of Engelse vertaling.
- Er zijn stijlverschillen tussen vergelijkbare Engelse termen, bijvoorbeeld **Calendar/Agenda**, **Tasks/To-do** en **Finished/completed**.
- Zowel drie losse puntjes als het ellipsteken komen voor.
- Variabelen en aantallen verschijnen als Swift-interpolatie of printf-placeholders zoals %lld en %@.
