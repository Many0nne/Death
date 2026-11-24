-- Point d'entrée client : démarre les modules du prototype v0 (chaque module vit à côté de ce script).
-- LightPrompts d'abord : il masque au plus tôt les invites réservées à l'autre rôle (DeathView attend le PlayerGui).
require(script.LightPrompts).start()
require(script.DeathView).start()
require(script.CameraController).start()

print("Death : client prêt")
