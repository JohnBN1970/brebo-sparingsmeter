# BREBO Sparingsmeter

Eerste iOS MVP voor automatische sparingsmeting.

## Harde productregels

- De gebruiker prikt **geen meetpunten** aan.
- Meting gebeurt door de iPhone/iPad rustig langs de sparing te bewegen.
- ARKit/LiDAR levert diepte + tracking; camerabeeld wordt gebruikt voor verdere verfijning.
- Een maat wordt alleen vrijgegeven wanneer de geschatte meetafwijking **maximaal ±2 mm** is.
- Productiemaat = maatgevende vrije sparingsmaat minus **5 mm per zijde**.
  - breedte: `vrije breedte - 10 mm`
  - hoogte: `vrije hoogte - 10 mm`
- Gemeten, gedetecteerde, berekende en handmatig ingevoerde gegevens blijven als verschillende bronnen opgeslagen.

## Status van deze eerste versie

Dit is de eerste bouwbare architectuur/scaffold. De app:
- start een ARKit world-tracking sessie;
- schakelt scene depth in wanneer het toestel dit ondersteunt;
- verzamelt cameratransforms + depth confidence;
- bewaakt scandekking en kwaliteitsstatus;
- bevat het domeinmodel voor sparingsgeometrie;
- berekent de veilige kozijnmaat op basis van minimum vrije maat en 5 mm rondom;
- weigert productiemaat-vrijgave boven ±2 mm onzekerheid.

v0.2 voegt automatische Vision-contourdetectie en multi-frame beeldtracking toe. De volgende bouwslag is terugprojectie van de gedetecteerde contour naar LiDAR/world-space en robuuste 3D line/plane fitting.

## Build

Project is opgezet voor XcodeGen.

```bash
brew install xcodegen
xcodegen generate
open Sparingsmeter.xcodeproj
```

Voor Codemagic staat een eerste `codemagic.yaml` in de root.

## Ondersteuning

Doelhardware: iPhone/iPad Pro met LiDAR.
Minimum iOS: 17.0.


## v0.3 geometriekern

Toegevoegd:
- pixel + depth -> 3D cameraruimte;
- cameraruimte -> ARKit wereldruimte;
- robuuste 3D lijnfit voor sparingsranden;
- outlierfiltering;
- RMS-residu in millimeters als basis voor de latere onzekerheidsberekening.

De volgende stap is de Vision-contour automatisch bemonsteren tegen de depth-map, zodat links/rechts/boven/onder echte 3D-puntenwolken worden en de lijnfit live gevoed wordt.


## v0.5 live 3D maatketen

Toegevoegd:
- Vision-hoekpunten worden behouden i.p.v. alleen bounding box;
- elke van de vier sparingsranden wordt automatisch langs de LiDAR depth-map bemonsterd;
- alleen medium/high-confidence depth wordt gebruikt;
- depth pixels worden naar camera- en daarna wereldcoordinaten teruggeprojecteerd;
- links/rechts/boven/onder krijgen ieder een eigen 3D-puntenwolk;
- robuuste lijnfit + outlierfiltering wordt live toegepast;
- eerste live breedte/hoogte ontstaat uit de 3D-puntenwolken;
- de app toont die live maat, maar productievrijgave blijft bewust geblokkeerd tot metrologische kalibratie de <= +/-2 mm eis aantoont.

Volgende stap:
1. kalibratie tegen bekende maatlat/referentiekader;
2. correctie van depth-systematiek per toestel/afstand;
3. meerdere doorsneden i.p.v. alleen centrale globale maat;
4. scheefstand, minimum vrije maat en negge/diepte.


## v0.6 metrologie en maatgevende doorsneden

Toegevoegd:
- affine kalibratie tegen bekende referentiematen;
- schaal- en offsetcorrectie per kalibratieprofiel;
- validatie-RMS in millimeters;
- harde metrology gate: geen productie-vrijgave zonder gevalideerde <= +/-2 mm kalibratie;
- 11 automatische doorsneden over breedte en hoogte;
- kleinste vrije breedte/hoogte wordt maatgevend;
- productiemaat blijft kleinste vrije maat minus 10 mm totaal (5 mm per zijde).

Hiermee is de softwarestructuur klaar voor echte toestelkalibratie in de praktijk.


## v0.7 fysieke kalibratie-workflow

Toegevoegd:
- kalibratiescherm in de app;
- live gemeten breedte kan direct aan een bekende referentiemaat worden gekoppeld;
- vanaf 3 referentiepunten wordt automatisch schaal + offset + RMS-validatiefout opgelost;
- zichtbaar akkoord/niet-akkoord tegen de harde +/-2 mm eis;
- resetbare kalibratieset;
- ValidationRecord-model voorbereid voor praktijkproeven en latere BREBO Office/MJOP data-analyse.

Praktijktest:
gebruik bij voorkeur meerdere bekende maten en verschillende afstanden/hoeken. Een goede fit op slechts één maat bewijst geen algemene +/-2 mm nauwkeurigheid.
