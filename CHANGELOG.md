# Changelog

## Niet uitgebracht

- Ondersteuning voor GlobalProtect-portals die eerst gebruikersnaam en wachtwoord en daarna een aparte MFA-code vragen.
- Wachtwoorden en MFA-codes worden alleen in het geheugen gehouden en via stdin aan OpenConnect doorgegeven.
- Browsergebaseerde SAML-login blijft beschikbaar wanneer het wachtwoordveld leeg blijft.
- De enige aangeboden GlobalProtect-gateway wordt automatisch geselecteerd en Nederlandstalige MFA-prompts worden herkend.
- De app herkent een gestarte tunnel direct en blijft niet meer op macOS-toestemming wachten.
- Verbreken wacht tot OpenConnect werkelijk is gestopt en behoudt de tunnelstatus als veilig afsluiten niet lukt.
- De tunnelstarter heft door macOS geërfde signaalblokkades op, zodat veilig verbreken vanuit de GUI werkt.
- Wachtwoorden kunnen na expliciete keuze veilig in macOS Sleutelhanger worden bewaard, zodat een volgende verbinding alleen nog MFA vereist.
- Het menubalkvenster past zijn hoogte aan de ingeklapte inhoud aan; scrollen is pas nodig wanneer technische details zijn geopend.

## 1.0.0, 2026-08-15

- Eerste native Apple Silicon-menubalkapp.
- GlobalProtect-portalconfiguratie en optionele gebruikersnaam.
- SAML en MFA via de standaardbrowser van macOS.
- Veilige tweefasenverbinding met tijdelijke cookie en macOS-beheerdersgoedkeuring.
- Live statusicoon voor actief, inactief, bezig en fout.
- Starten bij inloggen via `SMAppService`.
- Liquid Glass-interface op macOS 26 met material fallback.
- Automatische arm64-build en downloadbaar GitHub Actions-artifact.
