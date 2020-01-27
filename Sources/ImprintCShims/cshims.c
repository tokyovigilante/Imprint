#ifdef __linux__
#include "include/cshims.h"

#include <termios.h>
#include <gtk/gtk.h>

void *get_gtk_open_dialog (const char *cancel_text, const char *open_text) {
    GtkWidget *dialog;
    dialog = gtk_file_chooser_dialog_new(
        "Choose Book", NULL, GTK_FILE_CHOOSER_ACTION_OPEN,
        cancel_text, GTK_RESPONSE_CANCEL,
        open_text, GTK_RESPONSE_ACCEPT,
        NULL);
    gtk_window_set_modal(dialog, TRUE)
}

#endif
