@tool
extends Resource
## Shared by every dialogue controller, independent of per-line response gaps.
@export_group("Affichage apres la voix")
## Attente avant de masquer la fenetre apres le WAV. Les pages doivent rester
## entierement lisibles. Ce temps ne retarde pas le demarrage de la reponse.
@export_range(0,5,.05,"suffix:s") var delai_disparition_apres_voix := .35
## Les conversations gardent leur validation manuelle, meme fenetre masquee.
@export var masquer_conversations_manuelles := false
@export_group("Intercom")
## Niveau du raccroche seul, avant le volume commun Intercom Effets.
@export_range(-40,0,.5,"suffix:dB") var volume_raccroche_db := -4.0
