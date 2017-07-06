/////////////////////////////////////////////////////////////////////////
// Copyright (c) 2011-2016 by Simon Schneegans
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or (at
// your option) any later version.
//
// This program is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
// General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
/////////////////////////////////////////////////////////////////////////

namespace GnomePie {

/////////////////////////////////////////////////////////////////////
/// This group displays a list of all running application windows.
/////////////////////////////////////////////////////////////////////

public class WindowListGroup : ActionGroup {

    /////////////////////////////////////////////////////////////////////
    /// Used to register this type of ActionGroup. It sets the display
    /// name for this ActionGroup, it's icon name and the string used in
    /// the pies.conf file for this kind of ActionGroups.
    /////////////////////////////////////////////////////////////////////

    public static GroupRegistry.TypeDescription register() {
        var description = new GroupRegistry.TypeDescription();
        description.name = _("Group: Window List");
        description.icon = "preferences-system-windows";
        description.description = _("Shows a Slice for each of your opened Windows. Almost like Alt-Tab.");
        description.id = "window_list";
        return description;
    }

    public bool current_workspace_only { get; set; default=false; }

    /////////////////////////////////////////////////////////////////////
    /// Cached icon names loaded from .desktop files.
    /////////////////////////////////////////////////////////////////////

    private static Gee.HashMap<string, string> cached_icon_name { private get; private set; }

    /////////////////////////////////////////////////////////////////////
    /// Wnck's Screen object, to control the list of opened windows.
    /////////////////////////////////////////////////////////////////////

    private Wnck.Screen screen;

    /////////////////////////////////////////////////////////////////////
    /// C'tor, initializes all members.
    /////////////////////////////////////////////////////////////////////

    public WindowListGroup(string parent_id) {
        GLib.Object(parent_id : parent_id);
    }

    /////////////////////////////////////////////////////////////////////
    /// This one is called when the ActionGroup is saved.
    /////////////////////////////////////////////////////////////////////

    public override void on_save(Xml.TextWriter writer) {
        base.on_save(writer);
        writer.write_attribute("current_workspace_only", this.current_workspace_only.to_string());
    }

    /////////////////////////////////////////////////////////////////////
    /// This one is called when the ActionGroup is loaded.
    /////////////////////////////////////////////////////////////////////

    public override void on_load(Xml.Node* data) {
        for (Xml.Attr* attribute = data->properties; attribute != null; attribute = attribute->next) {
            string attr_name = attribute->name.down();
            string attr_content = attribute->children->content;

            if (attr_name == "current_workspace_only") {
                current_workspace_only = bool.parse(attr_content);
            }
        }

        screen = Wnck.Screen.get_default();
        WindowListGroup.cached_icon_name = new Gee.HashMap<string, string>();

        Gtk.IconTheme.get_default().changed.connect(() => {
            WindowListGroup.cached_icon_name = new Gee.HashMap<string, string>();
            create_actions_for_all_windows();
        });

        screen.active_workspace_changed.connect(create_actions_for_all_windows);
        screen.window_opened.connect(create_action);
        screen.window_closed.connect(remove_action);
    }

    /////////////////////////////////////////////////////////////////////
    /// Remove a Action for a given window
    /////////////////////////////////////////////////////////////////////

    private void remove_action(Wnck.Window window) {
        if (!window.is_skip_pager() && !window.is_skip_tasklist())
            foreach (Action action in actions)
                if (window.get_xid() == uint64.parse(action.real_command)) {
                    actions.remove(action);
                    break;
                }
    }

    /////////////////////////////////////////////////////////////////////
    /// Create Action's for all currently opened windows.
    /////////////////////////////////////////////////////////////////////

    private void create_actions_for_all_windows() {
        delete_all();

        foreach (var window in screen.get_windows())
            create_action(window);
    }

    /////////////////////////////////////////////////////////////////////
    /// Create a Action for a given opened window
    /////////////////////////////////////////////////////////////////////

    private void create_action(Wnck.Window window) {
        if (!window.is_skip_pager() && !window.is_skip_tasklist()
            && (!current_workspace_only || (window.get_workspace() != null
            && window.get_workspace() == screen.get_active_workspace()))) {

            var name = window.get_name();
            var icon_name = get_icon_name(window);
            var xid = "%lu".printf(window.get_xid());

            if (name.length > 30) {
                name = name.substring(0, 30) + "...";
            }

            var action = new SigAction(name, icon_name, xid);
            this.add_action(action);

            window.name_changed.connect(() => {
                action.name = window.get_name();
            });

            action.activated.connect((time_stamp) => {
                if (window.get_workspace() != null) {
                    //select the workspace
                    if (window.get_workspace() != window.get_screen().get_active_workspace()) {
                        window.get_workspace().activate(time_stamp);
                    }
                }

                if (window.is_minimized()) {
                    window.unminimize(time_stamp);
                }

                window.activate_transient(time_stamp);
            });
        }
    }

    private string get_icon_name(Wnck.Window window) {
        string icon_name = null;

        #if HAVE_BAMF
            var xid = (uint32) window.get_xid();
            Bamf.Matcher bamf_matcher = Bamf.Matcher.get_default();
            Bamf.Application app = bamf_matcher.get_application_for_xid(xid);
            string desktop_file = null;

            if (app != null)
                desktop_file = app.get_desktop_file();

            if (desktop_file != null) {
                if (WindowListGroup.cached_icon_name.has_key(desktop_file))
                    icon_name = WindowListGroup.cached_icon_name.get(desktop_file);
                else {
                    try {
                        var file = new KeyFile();
                        file.load_from_file(desktop_file, 0);

                        if (file.has_key(KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON)) {
                            icon_name = file.get_locale_string(KeyFileDesktop.GROUP, KeyFileDesktop.KEY_ICON);
                            WindowListGroup.cached_icon_name.set(desktop_file, icon_name);
                        }
                    } catch (GLib.KeyFileError e) {
                        error("%s", e.message);
                    } catch (GLib.FileError e) {
                        error("%s", e.message);
                    }
                }
            }
        #else
            var application = window.get_application();
            icon_name = Icon.get_icon_name(application.get_icon_name().down());
        #endif

        return icon_name;
    }
}

}
