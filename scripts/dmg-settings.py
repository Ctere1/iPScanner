"""Finder presentation; dmgbuild is a build-time dependency only."""
from pathlib import Path
app = str(Path(defines['app']).resolve())
files = [(app, 'iPScanner.app')]
symlinks = {'Applications': '/Applications'}
background = str(Path(defines['background']).resolve())
format = 'UDZO'
filesystem = 'HFS+'
window_rect = ((180, 160), (660, 452))
icon_locations = {'iPScanner.app': (175, 205), 'Applications': (485, 205)}
icon_size = 96
text_size = 14
label_pos = 'bottom'
arrange_by = None
default_view = 'icon-view'
show_status_bar = False
show_toolbar = False
show_sidebar = False
show_pathbar = False
show_tab_view = False
# Never set FinderInfo on the signed app: strict codesign rejects it.
hide_extensions = []
include_icon_view_settings = True
include_list_view_settings = False
