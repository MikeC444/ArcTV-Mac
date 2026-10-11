# Settings for dmgbuild (https://dmgbuild.readthedocs.io): how the disk image looks when it is opened. Run by scripts/package-app.sh.
import os

app = defines["app"]  # noqa: F821 (dmgbuild provides `defines`)
background = defines["background"]  # noqa: F821
icon = defines.get("icon")  # noqa: F821

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
if icon:
    icon = icon  # the picture the mounted disk shows

# 660 by 400 points, the app on the left, Applications on the right, and the arrow between them (drawn in the background picture).
window_rect = ((200, 140), (660, 400))
default_view = "icon-view"
icon_size = 128
text_size = 13
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_locations = {os.path.basename(app): (165, 200), "Applications": (495, 200)}
