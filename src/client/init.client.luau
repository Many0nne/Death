-- Point d'entrée client : démarre les modules du prototype v0 (chaque module vit à côté de ce script).
-- LightPrompts d'abord : il masque au plus tôt les invites réservées à l'autre rôle (DeathView attend le PlayerGui).
require(script.LightPrompts).start()
require(script.ResetControl).start()
require(script.DeathView).start()
require(script.CloakAnimator).start()
require(script.CameraController).start()
require(script.DeathViewmodel).start()
require(script.TrapCues).start()
require(script.DeathTrapPrompts).start()
require(script.AgonyClient).start()
require(script.Flashlight).start()
require(script.Hud).start()

print("Death : client prêt")
