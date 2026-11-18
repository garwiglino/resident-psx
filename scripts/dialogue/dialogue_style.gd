class_name DialogueStyle
extends Resource
@export_group("Fenetre - pixels natifs 320 x 240")
@export var box := Rect2(43,187,233,42)
@export var top_color := Color8(0,20,152)
@export var bottom_color := Color8(0,0,72)
@export var border_color := Color(30.0/31,28.0/31,23.0/31)
## Filet interieur du cadre et de l'encart du locuteur. Alpha a 0 pour le masquer.
@export var inner_border_color := Color(3.0/31,6.0/31,16.0/31)
## Ombre exterieure de la fenetre. Alpha a 0 pour la masquer.
@export var shadow_color := Color(0,0,1.0/31)
@export var text_color := Color(31.0/31,29.0/31,24.0/31)
@export_group("Texte")
@export var font: Font=preload("res://assets/fonts/m5x7.ttf")
@export var name_font: Font=preload("res://assets/fonts/pixel-operator-bold.ttf")
@export_range(8,32,1,"suffix:px") var font_size := 16
@export_range(8,32,1,"suffix:px") var name_font_size := 16
@export_range(8,20,1,"suffix:px") var name_tab_height := 12
@export_range(0,3,1,"suffix:px") var glyph_spacing := 0
@export_range(1,4,1) var lines_per_page := 2
@export_range(0,8,1,"suffix:px") var line_spacing := 0
@export_range(1.0,120.0,1.0,"suffix:lettres/s") var characters_per_second := 32.0
@export_group("Timing")
@export_range(0.0,.5,.01,"suffix:s") var opening_delay := .12
@export_range(0.0,.5,.01,"suffix:s") var speaker_delay := .08
@export_range(0.0,.5,.01,"suffix:s") var punctuation_pause := .12
@export_range(.2,2.0,.1,"suffix:s") var indicator_period := .8
@export_range(1.0,4.0,.5,"suffix:px") var indicator_travel := 3.0
## Part du cycle consacree a la descente ; le reste est la remontee.
@export_range(.1,.45,.01) var indicator_descent_ratio := .28
@export_group("Sons de fenetre")
@export var opening_sound: AudioStream=preload("res://assets/audio/ui/dialogue_open.wav")
@export var closing_sound: AudioStream=preload("res://assets/audio/ui/dialogue_close.wav")
@export_range(-60.0,-6.0,.5,"suffix:dB") var window_volume_db := -25.0
@export_group("Son des lettres")
@export var letter_sound: AudioStream=preload("res://assets/audio/ui/dialogue_tick.wav")
@export_range(-60.0,-6.0,.5,"suffix:dB") var letter_volume_db := -32.0
@export_group("Intercom")
@export var intercom_open_sound: AudioStream=preload("res://assets/audio/dialogs/talkie_start.wav")
@export var intercom_close_sound: AudioStream=preload("res://assets/audio/dialogs/talkie_end.wav")
@export_range(-60,0,.5,"suffix:dB") var intercom_volume_db := -20.0
## Fond radio uniquement pendant la voix. Null permet de le desactiver.
@export var intercom_loop_sound: AudioStream=preload("res://assets/audio/dialogs/talkie_loop.wav")
@export_range(-60,0,.5,"suffix:dB") var intercom_loop_volume_db := -14.0
