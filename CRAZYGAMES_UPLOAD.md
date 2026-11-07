# WILDZONE — cum urci jocul pe CrazyGames

## Ce e gata în folder
- `build/wildzone_crazygames.zip` — jocul web, gata de urcat (≈8 MB arhivat, ~35 MB dezarhivat; limita CrazyGames e 50 MB).
- `build/web/` — aceleași fișiere, dezarhivate (le poți testa local).
- `store_assets/` — cele 3 coperți cerute: 1920×1080, 800×1200, 800×800.
- SDK-ul CrazyGames v3 e deja inclus: jocul trimite `gameplayStart` / `gameplayStop` (meniu, inventar, magazin), `loadingStop` și `happytime` (la fiecare al 10-lea nivel). Pe alte site-uri sau pe desktop SDK-ul se ignoră singur.

## Pași
1. Intră pe https://developer.crazygames.com și creează contul de dezvoltator.
2. „Add game” → tip **HTML5** → încarcă `build/wildzone_crazygames.zip`.
3. Orientare: **Landscape**. Dispozitive: **Desktop** (jocul cere tastatură + mouse).
4. Încarcă cele 3 coperți din `store_assets/`.
5. Descriere scurtă (exemplu):
   *Hunt deer, wolves and bears, mine gold, chop trees and build your own cabin and bridges. Level up to 99, unlock new building pieces and sell your loot to Trader Ion.*
6. Controale: WASD move • Shift sprint • Space jump • 1-4 tools • LMB use • E interact • I inventory • H medkit • B/R build piece/rotate • T chat.
7. Trimite pentru „Basic Launch”. Reclamele se pot adăuga mai târziu (Full Launch).

## Când modifici jocul
În Godot: **Project → Export → „Web (CrazyGames)” → Export Project** în `build/web/index.html`, apoi faci zip doar cu fișierele din `build/web/` (index.html trebuie să fie în rădăcina arhivei, nu într-un subfolder).
Prima dată Godot îți cere „Export Templates”: Editor → Manage Export Templates → Download and Install (4.3).

## Multiplayer
În browser jocul merge **solo** (cu salvare automată în browser). Pentru prieteni pe CrazyGames trebuie un server dedicat (un VPS) pornit cu:
`godot --headless --path wildzone -- --server --port 24560`, pus în spatele unui certificat HTTPS, iar jucătorii intră cu `wss://adresa-ta`.
Pe Mac, butonul **HOST GAME** merge pentru prietenii din aceeași rețea.
