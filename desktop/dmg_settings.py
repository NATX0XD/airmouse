import os

application = os.environ["AIRMOUSE_APP_PATH"]
format = "UDZO"
size = "200M"
files = [application]
symlinks = {"Applications": "/Applications"}
icon_locations = {
    "AirMouse Receiver.app": (150, 150),
    "Applications": (390, 150),
}
window_rect = ((100, 100), (640, 420))
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
