"""Entry point for the non-destructive player and modular outerwear exporter."""
import pathlib
script = pathlib.Path(__file__).with_name('player_modular_export.py')
exec(compile(script.read_text(encoding='utf8'), str(script), 'exec'))
