# Death

Jeu Roblox d'horreur asymétrique : on joue la Mort, qui arme des accidents dans le décor, contre 4 mortels qui doivent
fuir avant la fin de la nuit.

```bash
rokit install                          # outils (rojo, stylua, selene, luau-lsp, lune)
rojo serve                             # port 34930, puis Connect dans le plugin Rojo de Studio
bash tools/check.sh                    # lint, format, typecheck, tests
rojo build -o Death.rbxlx              # place autonome
```

Conception : `docs/design.md`, `docs/parcours-joueur.md`. Règles de travail : `CLAUDE.md`.
