# BREBO Sparingsmeter - eerste iPhone build

## Doel

De eerste fysieke build moet aantonen dat:

1. de app op een LiDAR iPhone/iPad start;
2. camera + ARKit + scene depth actief worden;
3. de sparing automatisch wordt gevonden zonder punten aan te klikken;
4. 3D edge samples worden verzameld;
5. live breedte/hoogte verschijnt;
6. kalibratiepunten kunnen worden opgeslagen.

De +/-2 mm eis is pas geslaagd na fysieke validatie.

## Codemagic

De repository bevat een `codemagic.yaml` die:

- XcodeGen installeert;
- het Xcode-project genereert;
- tests draait;
- een echte `iphoneos` Release archive compileert.

Deze archive-validatie gebruikt nog geen signing. Daarmee kunnen compileerfouten eerst los van Apple signing worden opgelost.

## Daarna: installeren op toestel

Voor een installeerbare IPA/TestFlight build moeten in Codemagic de Apple Developer / App Store Connect signing credentials worden gekoppeld voor bundle id:

`nl.brebo.sparingsmeter`

Na signing kan dezelfde archive worden geëxporteerd als IPA of naar TestFlight.

## Eerste praktijktest

Gebruik minimaal drie nauwkeurig bekende referenties, bijvoorbeeld circa:

- 500 mm
- 1000 mm
- 2000 mm

Scan iedere referentie vanaf meerdere afstanden en kijkhoeken. Noteer niet alleen gemiddelde fout, maar ook maximale fout en herhaalbaarheid.
