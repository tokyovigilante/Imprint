#if os(Linux)

import CGTK
import ImprintCShims
import LoggerAPI
import Foundation

class FileChooserGTK {

    class func run () -> String? {
        Log.debug("run")
        let cancelString = "Cancel".cString(using: String.Encoding.utf8)
        let openString = "Open".cString(using: String.Encoding.utf8)

        let widget = get_gtk_open_dialog(cancelString, openString).assumingMemoryBound(to: GtkWidget.self)


        widget.withMemoryRebound(to: GtkDialog.self, capacity: 1) { (dialog: UnsafeMutablePointer<GtkDialog>) in
            let result = gtk_dialog_run(dialog)

        }
        /*let dialog = gtk_file_chooser_dialog_new("Choose Book",
                                      nil,
                                      GTK_FILE_CHOOSER_ACTION_OPEN,
                                      _("_Cancel"),
                                      GTK_RESPONSE_CANCEL,
                                      _("_Open"),
                                      GTK_RESPONSE_ACCEPT,
                                      nil);*/

        /*if (res == GTK_RESPONSE_ACCEPT)
          {
            char *filename;
            GtkFileChooser *chooser = GTK_FILE_CHOOSER (dialog);
            filename = gtk_file_chooser_get_filename (chooser);
            open_file (filename);
            g_free (filename);
          }
        */

        gtk_widget_destroy(widget)

        return nil
    }

}

#endif
